import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct HistorySample: Codable, Equatable {
    let t: TimeInterval
    let h5: Double?
    let d7: Double?
    /// Custo de API cumulativo da sessão corrente no momento da amostra.
    var c: Double?
    /// Modelo ativo na amostra, como o Claude Code o nomeia. É o que permite
    /// dizer para onde foi o consumo; a status line não reparte os limites por
    /// modelo, mas diz qual estava a responder.
    var m: String?
    /// Sessão do Claude Code que emitiu a amostra (`session_id`). O custo em
    /// `c` é acumulado por sessão e este arquivo é comum a todas: sem isto não
    /// dá para somar custo sem misturar sessões (ver `CostAggregator`).
    var s: String?

    init(
        t: TimeInterval,
        h5: Double?,
        d7: Double?,
        c: Double? = nil,
        m: String? = nil,
        s: String? = nil
    ) {
        self.t = t
        self.h5 = h5
        self.d7 = d7
        self.c = c
        self.m = m
        self.s = s
    }

    var date: Date { Date(timeIntervalSince1970: t) }
}

/// Série temporal de uso em JSONL (uma amostra por linha), gravada pelo
/// ingest e lida pelo gráfico de histórico. Escrita com O_APPEND para que
/// ingests concorrentes não se corrompam; leitura tolera linhas inválidas.
struct HistoryStore {
    let paths: AppPaths

    /// Espaçamento mínimo entre amostras. O timestamp da última linha válida é
    /// lido do final do JSONL; o mtime não serve porque uma poda também o muda.
    static let minimumSampleInterval: TimeInterval = 60
    static let retention: TimeInterval = 90 * 24 * 3600

    init(paths: AppPaths = .current) {
        self.paths = paths
    }

    func append(
        fiveHour: Double?,
        sevenDay: Double?,
        cost: Double? = nil,
        model: String? = nil,
        session: String? = nil,
        now: Date = Date()
    ) {
        guard fiveHour != nil || sevenDay != nil else { return }
        let stateStore = StateStore(paths: paths)
        guard (try? stateStore.secureDirectory(paths.baseDirectory)) != nil else { return }

        try? FileLock.withExclusiveAccess(at: lockFile) {
            let timestamp = now.timeIntervalSince1970
            if let last = lastSampleTimestamp(),
               timestamp >= last,
               timestamp - last < Self.minimumSampleInterval {
                return
            }

            let sample = HistorySample(
                t: timestamp,
                h5: fiveHour,
                d7: sevenDay,
                c: cost,
                m: model,
                s: session
            )
            var data = try JSONEncoder().encode(sample)
            data.append(0x0A)

            let descriptor = open(paths.historyFile.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.historyFile.path
            )
        }
    }

    /// Quanto se lê da cauda na primeira tentativa. Uma amostra ocupa ~90 B,
    /// então 1 MiB cobre cerca de oito dias: o suficiente para o caminho
    /// quente (o app recarrega os últimos 7 dias a cada ingestão) resolver-se
    /// numa leitura só, em vez de ler a cauda duas vezes.
    private static let initialTailSize: UInt64 = 1024 * 1024

    /// Amostras dentro de `range` a partir de `now`, em ordem cronológica.
    ///
    /// Lê da cauda para trás, e não o arquivo inteiro: as amostras são
    /// acrescentadas em ordem de tempo, então o que interessa está sempre no
    /// fim. Na retenção cheia (90 dias, ~130 mil linhas, 11 MB) decodificar
    /// tudo custava 271 ms **na thread principal**, a cada ingestão, para ficar
    /// com as 300 linhas das últimas 5 h; e o painel abre com um `reload`
    /// síncrono, ou seja, abria 271 ms depois do clique.
    func load(range: TimeInterval, now: Date = Date()) -> [HistorySample] {
        (try? FileLock.withExclusiveAccess(at: lockFile) {
            guard let handle = try? FileHandle(forReadingFrom: paths.historyFile),
                  let size = try? handle.seekToEnd() else { return [] }
            defer { try? handle.close() }

            let cutoff = now.timeIntervalSince1970 - range
            let decoder = JSONDecoder()
            var tail = Self.initialTailSize

            while true {
                let atStart = tail >= size
                let offset = atStart ? 0 : size - tail
                try? handle.seek(toOffset: offset)
                guard let data = try? handle.readToEnd() else { return [] }

                var lines = data.split(separator: 0x0A)
                // A primeira linha da janela costuma vir cortada ao meio; só é
                // inteira quando a janela é o arquivo todo.
                if !atStart, !lines.isEmpty {
                    lines.removeFirst()
                }
                let samples = lines.compactMap { try? decoder.decode(HistorySample.self, from: $0) }

                // Ou já se alcançou uma amostra anterior ao corte (e portanto
                // todas as posteriores estão nesta janela), ou não há mais
                // arquivo para trás.
                if atStart || samples.first.map({ $0.t < cutoff }) == true {
                    return samples
                        .filter { $0.t >= cutoff && $0.t <= now.timeIntervalSince1970 + 60 }
                        .sorted { $0.t < $1.t }
                }
                tail *= 4
            }
        }) ?? []
    }

    /// Reescreve o arquivo sem as amostras além da retenção. Chamado pelo app
    /// (não pelo ingest, que precisa ser rápido).
    func prune(now: Date = Date()) {
        try? FileLock.withExclusiveAccess(at: lockFile) {
            guard let data = try? Data(contentsOf: paths.historyFile) else { return }
            let cutoff = now.timeIntervalSince1970 - Self.retention
            let decoder = JSONDecoder()
            let lines = data.split(separator: 0x0A)
            let kept = lines.filter { line in
                guard let sample = try? decoder.decode(HistorySample.self, from: line) else { return false }
                return sample.t >= cutoff
            }
            guard kept.count < lines.count else { return }

            var output = Data(kept.joined(separator: [0x0A]))
            if !output.isEmpty { output.append(0x0A) }
            try output.write(to: paths.historyFile, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.historyFile.path
            )
        }
    }

    private var lockFile: URL {
        paths.baseDirectory.appendingPathComponent("history.lock")
    }

    /// Lê somente os últimos 8 KiB, suficientes para várias linhas válidas e
    /// sem custo proporcional aos 90 dias de retenção.
    private func lastSampleTimestamp() -> TimeInterval? {
        guard let handle = try? FileHandle(forReadingFrom: paths.historyFile) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > 8_192 ? end - 8_192 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).reversed().compactMap { line in
            try? decoder.decode(HistorySample.self, from: line).t
        }.first
    }

    /// Reduz a série para no máximo `limit` pontos preservando picos (máximo
    /// por balde), que é o que importa para visualizar aproximação do limite.
    static func downsample(_ samples: [HistorySample], limit: Int) -> [HistorySample] {
        guard samples.count > limit, limit > 0,
              let first = samples.first, let last = samples.last, last.t > first.t else {
            return samples
        }
        let span = last.t - first.t
        var buckets: [Int: HistorySample] = [:]
        for sample in samples {
            let index = min(limit - 1, Int(Double(limit) * (sample.t - first.t) / span))
            if let current = buckets[index] {
                let best = HistorySample(
                    t: sample.t,
                    h5: maxOptional(current.h5, sample.h5),
                    d7: maxOptional(current.d7, sample.d7),
                    c: maxOptional(current.c, sample.c),
                    m: sample.m ?? current.m,
                    s: sample.s ?? current.s
                )
                buckets[index] = best
            } else {
                buckets[index] = sample
            }
        }
        return buckets.sorted { $0.key < $1.key }.map(\.value)
    }

    private static func maxOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        default: nil
        }
    }
}
