import Foundation
import XCTest
@testable import ClaudeUsageMonitor

/// A doc do Claude Code diz que `five_hour` e `seven_day` podem faltar
/// independentemente uma da outra. Estes testes provam o que o app faz quando
/// isso acontece.
final class StaleWindowTests: XCTestCase {
    private func temporaryPaths() throws -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
    }

    private func ingest(_ json: String, store: StateStore, now: Date) throws {
        _ = try StatusLineProcessor.run(input: Data(json.utf8), store: store, now: now)
    }

    /// Um payload com as duas janelas, seguido de um payload só com a de 5 h.
    /// O valor de 7 dias fica congelado no state, e é isso que o app mostra.
    func testSevenDayGoesStaleWhenItDisappearsFromThePayload() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let first = Date(timeIntervalSince1970: 1_784_000_000)
        let second = first.addingTimeInterval(600)
        let future = first.timeIntervalSince1970 + 4 * 24 * 3_600

        try ingest("""
        {"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":\(first.timeIntervalSince1970 + 3_600)},
        "seven_day":{"used_percentage":80,"resets_at":\(future)}}}
        """, store: store, now: first)
        XCTAssertEqual(store.load()?.sevenDayUsage, 80)

        // Agora o Claude Code manda só a janela de 5 h.
        try ingest("""
        {"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":\(first.timeIntervalSince1970 + 3_600)}}}
        """, store: store, now: second)

        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.fiveHourUsage, 25, "a janela de 5 h atualizou")

        // O valor de 7 dias continua lá, de um payload anterior.
        XCTAssertEqual(state.sevenDayUsage, 80, "7 dias ficou congelado")

        // O carimbo global foi renovado pela janela de 5 h. Sozinho, ele faria
        // o app tratar os 80% velhos como dado fresco.
        XCTAssertEqual(UsageFormatter.dataAge(state.usageUpdatedAt, relativeTo: second), 0)

        // A correção: o carimbo de 7 dias ficou 10 minutos para trás, então o
        // app sabe que os 80% não vieram no último payload e pode dizê-lo.
        XCTAssertEqual(
            UsageFormatter.dataAge(state.sevenDayUpdatedAt, relativeTo: second),
            600,
            "7 dias carrega a própria idade"
        )
        XCTAssertEqual(UsageFormatter.dataAge(state.fiveHourUpdatedAt, relativeTo: second), 0)
    }

    /// O caso espelhado, e o pior: o percentual da barra de menus vem da janela
    /// de 5 h. Se ela some do payload, a barra mostra um número velho enquanto
    /// o cabeçalho diz "dados atualizados".
    func testFiveHourGoesStaleWhenItDisappearsFromThePayload() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let first = Date(timeIntervalSince1970: 1_784_000_000)
        let second = first.addingTimeInterval(600)
        let future = first.timeIntervalSince1970 + 4 * 24 * 3_600

        try ingest("""
        {"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":\(first.timeIntervalSince1970 + 3_600)},
        "seven_day":{"used_percentage":20,"resets_at":\(future)}}}
        """, store: store, now: first)

        try ingest("""
        {"rate_limits":{"seven_day":{"used_percentage":30,"resets_at":\(future)}}}
        """, store: store, now: second)

        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.fiveHourUsage, 90, "5 h ficou congelado em 90%")
        XCTAssertEqual(
            UsageFormatter.dataAge(state.fiveHourUpdatedAt, relativeTo: second),
            600,
            "o carimbo de 5 h ficou para trás: a barra pode marcar o número como antigo"
        )
        XCTAssertEqual(UsageFormatter.dataAge(state.sevenDayUpdatedAt, relativeTo: second), 0)
    }
}

/// O `state.json` é cache: um arquivo ilegível conserta-se sozinho, sem pedir
/// nada ao utilizador e sem perder dado que o próximo payload não reponha.
final class SelfHealingCacheTests: XCTestCase {
    private func temporaryPaths() throws -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
    }

    func testCorruptedCacheIsDiscardedAndRebuiltByTheNextPayload() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        try Data("{ isto não é JSON".utf8).write(to: paths.stateFile)

        guard case .invalid = store.loadResult() else {
            return XCTFail("um arquivo corrompido deveria ler como .invalid")
        }

        XCTAssertTrue(store.discardUnreadableState(), "o app apaga o cache sozinho")
        guard case .missing = store.loadResult() else {
            return XCTFail("depois de descartado, o estado é .missing")
        }

        // E o próximo payload reconstrói tudo: nada se perdeu.
        _ = try StatusLineProcessor.run(
            input: Data(#"{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":9999999999}}}"#.utf8),
            store: store
        )
        XCTAssertEqual(store.load()?.fiveHourUsage, 42)
    }

    /// Um estado válido nunca é descartado por engano.
    func testValidCacheIsNeverDiscarded() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        try store.save(UsageState(fiveHourUsage: 30))

        XCTAssertFalse(store.discardUnreadableState())
        XCTAssertEqual(store.load()?.fiveHourUsage, 30)
    }
}

/// O `state.json` é cache e vive numa pasta que o app oferece para abrir. Um
/// valor impossível lá dentro tem de virar cache descartável, nunca um número
/// na tela nem uma trava no arranque.
final class CorruptStateTests: XCTestCase {
    private func decode(_ json: String) -> StateLoadResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
        try? Data(json.utf8).write(to: paths.stateFile)
        return StateStore(paths: paths).loadResult()
    }

    func testAnImpossiblePercentageIsTreatedAsACorruptCache() {
        // 1e19 decodificava, e `Int(1e19)` derruba o processo ao formatar.
        guard case .invalid = decode(#"{"fiveHourUsage":1e19,"notifiedThresholds":[]}"#) else {
            return XCTFail("percentagem impossível aceite como estado válido")
        }
        guard case .invalid = decode(#"{"fiveHourUsage":-5,"notifiedThresholds":[]}"#) else {
            return XCTFail("percentagem negativa aceite como estado válido")
        }
        guard case .invalid = decode(#"{"sevenDayUsage":101,"notifiedThresholds":[]}"#) else {
            return XCTFail("percentagem acima de 100 aceite como estado válido")
        }
    }

    func testAValidPercentageStillLoads() {
        guard case let .loaded(state) = decode(#"{"fiveHourUsage":53.1,"notifiedThresholds":[]}"#) else {
            return XCTFail("estado válido recusado")
        }
        XCTAssertEqual(state.fiveHourUsage, 53.1)
    }
}

/// A status line anterior é um processo filho que não controlamos: pode não ler
/// o stdin, pode não terminar, e nada disso pode derrubar ou travar o ingest.
final class PreviousStatusLineTests: XCTestCase {
    private func store(previousCommand: String) throws -> StateStore {
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
        let backup: [String: Any] = [
            "hadStatusLine": true,
            "statusLine": ["type": "command", "command": previousCommand],
        ]
        try JSONSerialization.data(withJSONObject: backup).write(to: paths.statusLineBackupFile)
        return StateStore(paths: paths)
    }

    /// O buffer de um pipe é 64 KiB. Com um payload maior e um comando que não
    /// lê o stdin (o caso comum), o ingest morria de SIGPIPE e a status line do
    /// utilizador desaparecia inteira, a nossa linha incluída.
    func testALargePayloadSurvivesACommandThatIgnoresStdin() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "rate_limits": ["five_hour": ["used_percentage": 10, "resets_at": 4_102_444_800]],
            "enchimento": String(repeating: "x", count: 200_000),
        ])
        let output = try StatusLineProcessor.run(
            input: payload,
            store: store(previousCommand: "echo statusline-anterior")
        )
        XCTAssertTrue(output.contains("statusline-anterior"), "a linha do utilizador sumiu")
        XCTAssertTrue(output.contains("10%"), "a nossa linha sumiu")
    }

    /// E um comando que trava tem de bater no timeout, não bloquear a escrita.
    func testAHangingCommandDoesNotBlockTheIngest() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "rate_limits": ["five_hour": ["used_percentage": 10, "resets_at": 4_102_444_800]],
            "enchimento": String(repeating: "x", count: 200_000),
        ])
        let started = Date()
        let output = try StatusLineProcessor.run(
            input: payload,
            store: store(previousCommand: "sleep 30")
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "o ingest ficou preso na escrita")
        XCTAssertTrue(output.contains("10%"))
    }
}
