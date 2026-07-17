import AppKit
import XCTest
@testable import ClaudeUsageMonitor

final class ModelUsageTests: XCTestCase {
    private func sample(_ t: Double, _ h5: Double?, _ model: String?) -> HistorySample {
        HistorySample(t: t, h5: h5, d7: nil, c: nil, m: model)
    }

    func testSplitsTheClimbBetweenModels() {
        let shares = ModelUsage.split([
            sample(0, 0, "Opus"),
            sample(60, 30, "Opus"),
            sample(120, 40, "Sonnet"),
        ])
        XCTAssertEqual(shares.map(\.model), ["Opus", "Sonnet"])
        XCTAssertEqual(shares[0].fraction, 0.75, accuracy: 0.001)
        XCTAssertEqual(shares[1].fraction, 0.25, accuracy: 0.001)
    }

    /// Uma queda é reset de janela, não cota devolvida: o consumo depois dela
    /// conta inteiro, senão o modelo da janela nova ficaria com fração zero.
    func testCountsUsageAfterAResetInFull() {
        let shares = ModelUsage.split([
            sample(0, 0, "Opus"),
            sample(60, 80, "Opus"),
            sample(120, 20, "Sonnet"),
        ])
        XCTAssertEqual(shares.map(\.model), ["Opus", "Sonnet"])
        XCTAssertEqual(shares[0].fraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(shares[1].fraction, 0.2, accuracy: 0.001)
    }

    func testIgnoresSamplesWithoutModelOrUsage() {
        let shares = ModelUsage.split([
            sample(0, 0, "Opus"),
            sample(60, 10, nil),
            sample(120, 20, "Opus"),
            sample(180, nil, "Sonnet"),
        ])
        XCTAssertEqual(shares, [ModelUsage.Share(model: "Opus", fraction: 1)])
    }

    func testNoClimbMeansNothingToSplit() {
        XCTAssertTrue(ModelUsage.split([
            sample(0, 40, "Opus"),
            sample(60, 40, "Opus"),
        ]).isEmpty)
        XCTAssertTrue(ModelUsage.split([]).isEmpty)
    }

    /// Com frações iguais a ordem do dicionário é aleatória, e a barra trocava
    /// de cor entre um refresh e o seguinte.
    func testTiesResolveByNameSoTheOrderIsStable() {
        let samples = [
            sample(0, 0, "Opus"),
            sample(60, 10, "Opus"),
            sample(120, 20, "Sonnet"),
        ]
        let expected = ModelUsage.split(samples)
        for _ in 0 ..< 20 {
            XCTAssertEqual(ModelUsage.split(samples), expected)
        }
        XCTAssertEqual(expected.map(\.model), ["Opus", "Sonnet"])
    }

    func testHistoryRoundTripsTheModel() throws {
        let sample = HistorySample(t: 1, h5: 10, d7: 20, c: 0.5, m: "Opus 4.8")
        let decoded = try JSONDecoder().decode(
            HistorySample.self,
            from: JSONEncoder().encode(sample)
        )
        XCTAssertEqual(decoded, sample)
    }

    /// Amostras gravadas antes deste campo continuam a ler-se, sem modelo.
    func testLegacySampleDecodesWithoutAModel() throws {
        let line = Data(#"{"t":1,"h5":10,"d7":20}"#.utf8)
        let decoded = try JSONDecoder().decode(HistorySample.self, from: line)
        XCTAssertNil(decoded.m)
        XCTAssertEqual(decoded.h5, 10)
    }

    /// Um modelo só não reparte nada: a barra seria uma faixa cheia de uma cor,
    /// que num ecrã de limites se lê como "100% usado".
    func testTheSplitHidesItselfWithASingleModel() {
        let view = ModelSplitView()
        view.show([ModelUsage.Share(model: "Opus", fraction: 1)])
        XCTAssertTrue(view.isHidden)

        view.show([])
        XCTAssertTrue(view.isHidden)

        view.show([
            ModelUsage.Share(model: "Opus", fraction: 0.7),
            ModelUsage.Share(model: "Sonnet", fraction: 0.3),
        ])
        XCTAssertFalse(view.isHidden)
    }

    /// Cinco modelos rebentavam a legenda na largura mínima da janela, e a
    /// quinta fatia era fina demais para se ver.
    func testTheSplitFoldsTheTailIntoOneSlice() throws {
        let view = ModelSplitView()
        view.show((0 ..< 6).map { ModelUsage.Share(model: "M\($0)", fraction: 1.0 / 6) })
        view.layoutSubtreeIfNeeded()

        let labels = allSubviews(of: view).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains(L10n.otherModels))
        XCTAssertFalse(labels.contains("M5"))
        // Três nomeados mais a fatia agregada, e as fatias somam o período todo.
        XCTAssertEqual(labels.filter { $0.hasPrefix("M") }.count, 3)
        XCTAssertTrue(labels.contains("50%"))
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    /// O downsample fica com o pico de cada balde; o modelo tem de vir junto,
    /// senão a série reduzida perde a atribuição por completo.
    func testDownsampleKeepsAModel() {
        let reduced = HistoryStore.downsample(
            (0 ..< 10).map { sample(Double($0) * 60, Double($0), "Opus") },
            limit: 3
        )
        XCTAssertLessThanOrEqual(reduced.count, 3)
        XCTAssertTrue(reduced.allSatisfy { $0.m == "Opus" })
    }
}

extension ModelUsageTests {
    /// Renderiza a janela de histórico com dois modelos: o gráfico e a barra
    /// não são medidos por nenhuma asserção de layout, e só olhando se vê se a
    /// barra respira ou esmaga o rodapé.
    func testHistoryWindowRendersTheSplit() throws {
        L10n.language = .ptBR
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )

        let now = Date()
        let encoder = JSONEncoder()
        var lines = Data()
        for step in 0 ..< 60 {
            let model = step < 40 ? "Opus 4.8 (1M context)" : "Sonnet 4.6"
            let sample = HistorySample(
                t: now.timeIntervalSince1970 - Double(60 - step) * 240,
                h5: Double(step) * 0.9,
                d7: Double(step) * 0.4,
                c: Double(step) * 0.3,
                m: model
            )
            lines.append(try encoder.encode(sample))
            lines.append(0x0A)
        }
        try lines.write(to: paths.historyFile)

        let controller = HistoryWindowController(store: HistoryStore(paths: paths))
        controller.present(fiveHourResetAt: now.timeIntervalSince1970 + 3_600)
        defer { controller.close() }
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)

        if let directory = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"] {
            let out = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try png.write(to: out.appendingPathComponent("history-model-split.png"))
        }
    }
}

extension ModelUsageTests {
    /// Sem linha de base não há degrau para medir.
    ///
    /// Uma amostra pode não ter `h5`: o `HistoryStore.append` aceita amostras só
    /// com o limite de 7 dias, e cada janela pode faltar por si só no payload.
    /// Tratar essa ausência como zero fazia a amostra seguinte contar a janela
    /// inteira como consumo novo, e o modelo que por acaso respondesse a seguir
    /// levava o crédito de tudo o que os outros gastaram antes.
    func testAMissingBaselineIsNotZero() {
        let shares = ModelUsage.split([
            sample(0, 0, "Opus"),
            sample(60, 40, "Opus"),
            // Só o limite de 7 dias veio nesta: sem h5, sem base de comparação.
            HistorySample(t: 120, h5: nil, d7: 20, c: nil, m: "Sonnet"),
            sample(180, 50, "Sonnet"),
        ])
        // O Sonnet subiu a janela de 40 para 50: 10 pontos, e não 50.
        XCTAssertEqual(shares.map(\.model), ["Opus", "Sonnet"])
        XCTAssertEqual(shares[0].fraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(shares[1].fraction, 0.2, accuracy: 0.001)
    }
}

/// A leitura do histórico é feita pela cauda, e uma leitura por janela tem de
/// devolver exatamente o mesmo que ler o arquivo inteiro devolvia.
final class HistoryTailLoadTests: XCTestCase {
    private func store(lines: Int, now: Date) throws -> HistoryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
        let encoder = JSONEncoder()
        var data = Data()
        // Da mais antiga para a mais recente, como o ingest acrescenta.
        for index in stride(from: lines - 1, through: 0, by: -1) {
            let sample = HistorySample(
                t: now.timeIntervalSince1970 - Double(index) * 60,
                h5: Double(index % 100),
                d7: 20,
                c: 1.5,
                m: "Opus 4.8",
                s: "sessao"
            )
            data.append(try encoder.encode(sample))
            data.append(0x0A)
        }
        try data.write(to: paths.historyFile)
        return HistoryStore(paths: paths)
    }

    /// Um arquivo maior que a janela inicial de leitura: se a cauda fosse curta
    /// demais, faltariam amostras e o gráfico mentiria por omissão.
    func testATailReadFindsEverySampleInRange() throws {
        let now = Date()
        // 20 mil linhas ≈ 1,8 MiB, ou seja, quase o dobro da primeira janela:
        // sem alargar a leitura, faltariam amostras.
        let store = try store(lines: 20_000, now: now)

        let fiveHours = store.load(range: 5 * 3600, now: now)
        // 301, não 300: a amostra que cai exatamente no corte pertence ao
        // período (o filtro é `>= cutoff`), e as outras 300 são os minutos.
        XCTAssertEqual(fiveHours.count, 301, "5 h a uma amostra por minuto")
        XCTAssertEqual(fiveHours, fiveHours.sorted { $0.t < $1.t })
        XCTAssertEqual(fiveHours.last?.t ?? 0, now.timeIntervalSince1970, accuracy: 1)

        // Um período maior que a janela inicial obriga a alargar a leitura.
        let everything = store.load(range: 90 * 24 * 3600, now: now)
        XCTAssertEqual(everything.count, 20_000)
        XCTAssertEqual(everything.first?.m, "Opus 4.8", "a linha cortada ao meio foi descartada a mais")
    }

    func testAnEmptyOrMissingFileLoadsNothing() throws {
        let now = Date()
        XCTAssertTrue(try store(lines: 0, now: now).load(range: 3600, now: now).isEmpty)
    }

    /// O arquivo inteiro cabendo na primeira janela é o caso comum, e aí a
    /// primeira linha é inteira e não pode ser descartada.
    func testASmallFileKeepsItsFirstLine() throws {
        let now = Date()
        let samples = try store(lines: 3, now: now).load(range: 3600, now: now)
        XCTAssertEqual(samples.count, 3)
    }
}

extension HistoryTailLoadTests {
    /// A leitura pela cauda assume que as amostras estão em ordem de tempo, e
    /// estão: o ingest acrescenta com o relógio, sob lock. Este teste fixa o que
    /// acontece quando essa premissa quebra (o relógio anda para trás), para a
    /// premissa ser uma decisão e não um acidente: a janela inicial cobre ~2
    /// dias, então um salto menor do que isso não perde amostra nenhuma.
    func testABackwardClockJumpWithinTheInitialWindowLosesNothing() throws {
        let now = Date()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )

        // Ordem de gravação: uma hora atrás, depois "duas horas atrás" (o
        // relógio recuou), depois agora.
        let stamps = [-3600.0, -7200.0, 0.0]
        var data = Data()
        for offset in stamps {
            let sample = HistorySample(
                t: now.timeIntervalSince1970 + offset,
                h5: 10, d7: nil, c: nil, m: "Opus", s: "A"
            )
            data.append(try JSONEncoder().encode(sample))
            data.append(0x0A)
        }
        try data.write(to: paths.historyFile)

        let samples = HistoryStore(paths: paths).load(range: 5 * 3600, now: now)
        XCTAssertEqual(samples.count, 3, "amostra perdida por causa do salto de relógio")
        XCTAssertEqual(samples.map(\.t), samples.map(\.t).sorted(), "saída fora de ordem")
    }
}
