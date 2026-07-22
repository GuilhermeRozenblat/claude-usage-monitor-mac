import Foundation

enum StateLoadResult {
    case missing
    case loaded(UsageState)
    case invalid
}

struct AppPaths {
    let baseDirectory: URL
    let stateFile: URL
    let statusLineBackupFile: URL
    let claudeSettingsFile: URL

    var historyFile: URL {
        baseDirectory.appendingPathComponent("history.jsonl")
    }

    static var current: AppPaths {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDirectory = environment["CLAUDE_USAGE_MONITOR_BASE_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? home.appendingPathComponent(
            "Library/Application Support/ClaudeUsageMonitor",
            isDirectory: true
        )
        let settings = environment["CLAUDE_USAGE_MONITOR_SETTINGS_FILE"].map {
            URL(fileURLWithPath: $0)
        } ?? home.appendingPathComponent(".claude/settings.json")

        return AppPaths(
            baseDirectory: baseDirectory,
            stateFile: baseDirectory.appendingPathComponent("state.json"),
            statusLineBackupFile: baseDirectory.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: settings
        )
    }
}

struct StateStore {
    let paths: AppPaths

    init(paths: AppPaths = .current) {
        self.paths = paths
    }

    func load() -> UsageState? {
        guard case let .loaded(state) = loadResult() else { return nil }
        return state
    }

    func loadResult() -> StateLoadResult {
        guard FileManager.default.fileExists(atPath: paths.stateFile.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: paths.stateFile),
              let state = try? JSONDecoder().decode(UsageState.self, from: data) else {
            return .invalid
        }
        return .loaded(state)
    }

    /// Descarta um cache ilegível e devolve `true` se conseguiu.
    ///
    /// O `state.json` é cache: percentuais, resets e marcos são todos
    /// reconstruídos no próximo payload da status line. Um arquivo corrompido
    /// não é um problema para o utilizador resolver à mão: apaga-se e espera-se
    /// o próximo ingest, que chega na primeira resposta do Claude Code.
    ///
    /// Devolve `false` quando o arquivo não pôde ser removido (tipicamente
    /// permissão), que é o caso em que o utilizador precisa mesmo de saber.
    @discardableResult
    func discardUnreadableState() -> Bool {
        // Sob o lock do state: entre o check e o remove, um ingest pode gravar
        // um state.json válido que seria apagado sem motivo.
        let removed = try? withExclusiveAccess { () -> Bool in
            guard case .invalid = loadResult() else { return false }
            do {
                try FileManager.default.removeItem(at: paths.stateFile)
                return true
            } catch {
                return false
            }
        }
        return removed ?? false
    }

    func save(_ state: UsageState) throws {
        try secureDirectory(paths.baseDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(state)
        data.append(0x0A)
        try data.write(to: paths.stateFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.stateFile.path
        )
    }

    /// Serializa o ciclo completo read-modify-write entre diferentes sessões
    /// do Claude Code. A gravação atômica evita JSON parcial; este lock evita
    /// que dois processos válidos sobrescrevam campos atualizados pelo outro.
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        try secureDirectory(paths.baseDirectory)
        let lockFile = paths.baseDirectory.appendingPathComponent("state.lock")
        return try FileLock.withExclusiveAccess(at: lockFile, body)
    }

    func secureDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }
}
