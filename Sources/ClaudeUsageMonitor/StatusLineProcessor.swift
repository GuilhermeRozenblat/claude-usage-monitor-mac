import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum StatusLineProcessor {
    /// `now` é injetável para os testes: os carimbos têm resolução de segundo,
    /// e dois ingests no mesmo segundo ficam indistinguíveis.
    static func run(
        input: Data,
        store: StateStore = StateStore(),
        now: Date = Date()
    ) throws -> String {
        let snapshot = StatusLineParser.parse(input)
        if let snapshot, snapshot.rateLimits != nil || snapshot.session != nil {
            try store.withExclusiveAccess {
                try updateState(snapshot, store: store, now: now)
            }
        } else if snapshot == nil, !input.isEmpty {
            try? store.withExclusiveAccess {
                recordIngestError(store: store)
            }
        }

        let cachedState = store.load()
        let previousOutput = PreviousStatusLine.run(input: input, paths: store.paths)
        return [previousOutput, UsageFormatter.statusLine(snapshot?.rateLimits, fallback: cachedState)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func updateState(
        _ snapshot: StatusLineSnapshot,
        store: StateStore,
        now: Date
    ) throws {
        var state = store.load() ?? UsageState()
        let timestamp = ISO8601DateFormatter().string(from: now)
        state.lastIngestErrorAt = nil

        if let fiveHour = snapshot.rateLimits?.fiveHour {
            state.notifiedThresholds = ThresholdTracker.updated(
                notified: state.notifiedThresholds,
                thresholds: UsageThresholds.fiveHour,
                usage: fiveHour.usedPercentage,
                previousUsage: state.fiveHourUsage,
                previousResetAt: state.fiveHourResetAt,
                resetAt: fiveHour.resetsAt
            )
            state.fiveHourUsage = fiveHour.usedPercentage
            state.fiveHourResetAt = fiveHour.resetsAt
            // Carimba só a janela que veio: ver `UsageState.fiveHourUpdatedAt`.
            state.fiveHourUpdatedAt = timestamp
        }

        if let sevenDay = snapshot.rateLimits?.sevenDay {
            state.sevenDayNotifiedThresholds = ThresholdTracker.updated(
                notified: state.sevenDayNotifiedThresholds,
                thresholds: UsageThresholds.sevenDay,
                usage: sevenDay.usedPercentage,
                previousUsage: state.sevenDayUsage,
                previousResetAt: state.sevenDayResetAt,
                resetAt: sevenDay.resetsAt
            )
            state.sevenDayUsage = sevenDay.usedPercentage
            state.sevenDayResetAt = sevenDay.resetsAt
            state.sevenDayUpdatedAt = timestamp
        }

        if snapshot.rateLimits != nil {
            state.usageUpdatedAt = timestamp
        }
        if let session = snapshot.session {
            state.session = session
            state.sessionUpdatedAt = timestamp
        }
        try store.save(state)

        if snapshot.rateLimits != nil {
            HistoryStore(paths: store.paths).append(
                fiveHour: state.fiveHourUsage,
                sevenDay: state.sevenDayUsage,
                cost: state.session?.estimatedCostUSD
            )
        }
    }

    /// Deixa um rastro do payload rejeitado para o app exibir, sem quebrar a
    /// status line (o fallback em cache continua sendo impresso).
    private static func recordIngestError(store: StateStore) {
        var state = store.load() ?? UsageState()
        state.lastIngestErrorAt = ISO8601DateFormatter().string(from: Date())
        try? store.save(state)
    }
}

private enum PreviousStatusLine {
    private static let maximumOutputSize = 1_048_576

    static func run(input: Data, paths: AppPaths) -> String {
        guard let data = try? Data(contentsOf: paths.statusLineBackupFile),
              let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              backup["hadStatusLine"] as? Bool == true,
              let statusLine = backup["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String,
              !command.isEmpty else {
            return ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let outputCollector = BoundedOutputCollector(limit: maximumOutputSize)
        let outputFinished = DispatchSemaphore(value: 0)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                outputFinished.signal()
            } else {
                outputCollector.append(chunk)
            }
        }

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()

            if completed.wait(timeout: .now() + 1.5) == .timedOut {
                process.terminate()
                if completed.wait(timeout: .now() + 0.5) == .timedOut {
                    #if canImport(Darwin)
                    kill(process.processIdentifier, SIGKILL)
                    #endif
                    _ = completed.wait(timeout: .now() + 0.5)
                }
            }

            _ = outputFinished.wait(timeout: .now() + 0.5)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            return outputCollector.string()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            return ""
        }
    }
}

private final class BoundedOutputCollector: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var exceededLimit = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }

        let available = max(0, limit - data.count)
        if chunk.count > available {
            exceededLimit = true
        }
        if available > 0 {
            data.append(chunk.prefix(available))
        }
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !exceededLimit else { return "" }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines) ?? ""
    }
}
