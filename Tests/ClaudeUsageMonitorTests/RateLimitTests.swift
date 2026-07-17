import AppKit
import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class RateLimitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.language = .ptBR
    }

    func testParsesAndFormatsRateLimits() throws {
        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":33,"resets_at":1784140200},"seven_day":{"used_percentage":24,"resets_at":1784300400}}}"#.utf8)
        let limits = try XCTUnwrap(RateLimitParser.parse(input))

        XCTAssertEqual(limits.fiveHour?.usedPercentage, 33)
        XCTAssertEqual(limits.sevenDay?.usedPercentage, 24)
        let beforeReset = Date(timeIntervalSince1970: 1_784_000_000)
        XCTAssertTrue(UsageFormatter.statusLine(limits, relativeTo: beforeReset).contains("reinicia"))
    }

    func testClaudeAccountUsesAuthenticatedProfileEmail() throws {
        let auth = Data(#"{"loggedIn":true,"authMethod":"claude.ai"}"#.utf8)
        let profile = Data(#"{"oauthAccount":{"emailAddress":"person@example.com"}}"#.utf8)

        XCTAssertEqual(
            ClaudeAccountReader.parse(authData: auth, profileData: profile),
            .loggedIn(ClaudeAccount(email: "person@example.com", authMethod: "claude.ai"))
        )
    }

    func testClaudeAccountPrefersEmailFromAuthStatus() throws {
        let auth = Data(#"{"loggedIn":true,"authMethod":"oauth","emailAddress":"current@example.com"}"#.utf8)
        let profile = Data(#"{"oauthAccount":{"emailAddress":"old@example.com"}}"#.utf8)

        XCTAssertEqual(
            ClaudeAccountReader.parse(authData: auth, profileData: profile),
            .loggedIn(ClaudeAccount(email: "current@example.com", authMethod: "oauth"))
        )
    }

    func testClaudeAccountDoesNotShowStaleEmailAfterLogout() throws {
        let auth = Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8)
        let profile = Data(#"{"oauthAccount":{"emailAddress":"old@example.com"}}"#.utf8)

        XCTAssertEqual(
            ClaudeAccountReader.parse(authData: auth, profileData: profile),
            .loggedOut
        )
    }

    func testClaudeAccountDoesNotAssociateOAuthEmailWithAPIKey() {
        let auth = Data(#"{"loggedIn":true,"authMethod":"api_key"}"#.utf8)
        let profile = Data(#"{"oauthAccount":{"emailAddress":"old@example.com"}}"#.utf8)

        XCTAssertEqual(
            ClaudeAccountReader.parse(authData: auth, profileData: profile),
            .loggedIn(ClaudeAccount(email: nil, authMethod: "api_key"))
        )
    }

    func testClaudeAccountRejectsInvalidAuthOutput() {
        XCTAssertEqual(
            ClaudeAccountReader.parse(authData: Data("not-json".utf8), profileData: nil),
            .unavailable
        )
    }

    func testClaudeExecutableCanBeFoundOnInheritedPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let emptyHome = root.appendingPathComponent("home", isDirectory: true)
        XCTAssertEqual(
            ClaudeAccountReader.findExecutable(
                homeDirectory: emptyHome,
                environment: ["PATH": root.path]
            ),
            executable
        )
    }

    func testRejectsInvalidPercentage() {
        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":101}}}"#.utf8)
        XCTAssertNil(RateLimitParser.parse(input))
    }

    func testDiscardsInvalidResetTimestamp() throws {
        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":-1}}}"#.utf8)
        let limits = try XCTUnwrap(RateLimitParser.parse(input))
        XCTAssertNil(limits.fiveHour?.resetsAt)
    }

    func testFormatsRelativeResetAndExpiredWindow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = UsageFormatter.resetDescription(
            now.timeIntervalSince1970 + 5_400,
            relativeTo: now
        )
        let expired = UsageFormatter.resetDescription(
            now.timeIntervalSince1970 - 1,
            relativeTo: now
        )

        XCTAssertTrue(try XCTUnwrap(future).contains("• em 1h 30min"))
        XCTAssertFalse(try XCTUnwrap(future).contains("2023"))
        XCTAssertFalse(try XCTUnwrap(expired).contains("2023"))
        XCTAssertTrue(UsageFormatter.isExpired(now.timeIntervalSince1970, relativeTo: now))
    }

    func testStatusLineHidesExpiredUsage() {
        let limits = RateLimits(
            fiveHour: UsageWindow(usedPercentage: 88, resetsAt: 1_700_000_000),
            sevenDay: nil
        )
        let output = UsageFormatter.statusLine(
            limits,
            relativeTo: Date(timeIntervalSince1970: 1_700_000_001)
        )
        XCTAssertEqual(output, "Claude 5h: -- (aguardando nova janela)")
    }

    func testStateRoundTrip() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let state = UsageState(
            fiveHourUsage: 33,
            fiveHourResetAt: 1_784_140_200,
            sevenDayUsage: 24,
            sevenDayResetAt: 1_784_300_400,
            notifiedThresholds: [25],
            sevenDayNotifiedThresholds: [75],
            usageUpdatedAt: "2026-07-15T18:00:00Z",
            fiveHourUpdatedAt: "2026-07-15T18:00:00Z",
            sevenDayUpdatedAt: "2026-07-15T17:30:00Z",
            lastIngestErrorAt: "2026-07-15T17:00:00Z"
        )

        try store.save(state)
        XCTAssertEqual(store.load(), state)
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.stateFile.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    /// Estado gravado antes dos carimbos por janela: cada janela herda o
    /// carimbo global, que é o melhor que se sabe sobre ela. Sem isto, um
    /// utilizador que atualiza o app veria as duas janelas marcadas como
    /// antigas até o próximo payload.
    func testLegacyStateInheritsTheGlobalTimestampPerWindow() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        try Data("""
        {"fiveHourUsage":33,"sevenDayUsage":24,"notifiedThresholds":[],
        "sevenDayNotifiedThresholds":[],"usageUpdatedAt":"2026-07-15T18:00:00Z"}
        """.utf8).write(to: paths.stateFile)

        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.fiveHourUpdatedAt, "2026-07-15T18:00:00Z")
        XCTAssertEqual(state.sevenDayUpdatedAt, "2026-07-15T18:00:00Z")
    }

    func testStateLoadDistinguishesMissingAndInvalidFiles() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)

        guard case .missing = store.loadResult() else {
            return XCTFail("Estado ausente deveria ser identificado")
        }

        try Data("not-json".utf8).write(to: paths.stateFile)
        guard case .invalid = store.loadResult() else {
            return XCTFail("Estado inválido deveria ser identificado")
        }
    }

    func testProcessorStartsNewThresholdWindowAfterReset() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let first = Data(#"{"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1800000000}}}"#.utf8)
        let second = Data(#"{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1800018000}}}"#.utf8)

        _ = try StatusLineProcessor.run(input: first, store: store)
        XCTAssertEqual(store.load()?.notifiedThresholds, [25, 50, 75])

        _ = try StatusLineProcessor.run(input: second, store: store)
        XCTAssertEqual(store.load()?.notifiedThresholds, [25])
        XCTAssertEqual(store.load()?.fiveHourUsage, 30)
    }

    func testParsesOfficialSessionFields() throws {
        let input = Data(#"{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/Users/test/project"},"session_name":"review","version":"2.1.90","context_window":{"total_input_tokens":15500,"total_output_tokens":1200,"context_window_size":200000,"used_percentage":8,"remaining_percentage":92},"effort":{"level":"high"},"thinking":{"enabled":true},"cost":{"total_cost_usd":0.01234,"total_duration_ms":45000}}"#.utf8)
        let session = try XCTUnwrap(StatusLineParser.parse(input)?.session)

        XCTAssertEqual(session.modelDisplayName, "Opus")
        XCTAssertEqual(session.projectName, "project")
        XCTAssertEqual(session.sessionName, "review")
        XCTAssertEqual(session.contextUsedPercentage, 8)
        XCTAssertEqual(session.contextInputTokens, 15_500)
        XCTAssertEqual(session.contextWindowSize, 200_000)
        XCTAssertEqual(session.effortLevel, "high")
        XCTAssertEqual(session.thinkingEnabled, true)
        XCTAssertEqual(session.estimatedCostUSD, 0.01234)
    }

    func testSessionKeepsZeroCountersAndRemainingOnlyPayload() throws {
        let input = Data(#"{"context_window":{"total_input_tokens":0,"total_output_tokens":0,"remaining_percentage":100},"cost":{"total_duration_ms":0}}"#.utf8)
        let session = try XCTUnwrap(StatusLineParser.parse(input)?.session)

        XCTAssertEqual(session.contextInputTokens, 0)
        XCTAssertEqual(session.contextOutputTokens, 0)
        XCTAssertEqual(session.contextRemainingPercentage, 100)
        XCTAssertEqual(session.totalDurationMS, 0)
    }

    func testLongProjectPathKeepsTheFinalComponent() throws {
        let longParent = String(repeating: "very-long-directory/", count: 12)
        let input = Data("{\"workspace\":{\"project_dir\":\"/Users/test/\(longParent)important-project\"}}".utf8)
        let session = try XCTUnwrap(StatusLineParser.parse(input)?.session)
        XCTAssertEqual(session.projectName, "important-project")
    }

    func testProcessorDoesNotPersistTranscriptOrFullProjectPath() throws {
        let paths = try temporaryPaths()
        let input = Data(#"{"transcript_path":"/private/secret/conversation.jsonl","workspace":{"project_dir":"/Users/test/private-project"},"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12}}}"#.utf8)

        _ = try StatusLineProcessor.run(input: input, store: StateStore(paths: paths))
        let saved = String(decoding: try Data(contentsOf: paths.stateFile), as: UTF8.self)
        XCTAssertFalse(saved.contains("conversation.jsonl"))
        XCTAssertFalse(saved.contains("/Users/test"))
        XCTAssertTrue(saved.contains("private-project"))
    }

    func testAcceptsWeeklyWindowWithoutFiveHourWindow() throws {
        let paths = try temporaryPaths()
        let input = Data(#"{"rate_limits":{"seven_day":{"used_percentage":44,"resets_at":1900000000}}}"#.utf8)
        let limits = try XCTUnwrap(RateLimitParser.parse(input))
        XCTAssertNil(limits.fiveHour)
        XCTAssertEqual(limits.sevenDay?.usedPercentage, 44)

        _ = try StatusLineProcessor.run(input: input, store: StateStore(paths: paths))
        XCTAssertNil(StateStore(paths: paths).load()?.fiveHourUsage)
        XCTAssertEqual(StateStore(paths: paths).load()?.sevenDayUsage, 44)
    }

    func testMissingWindowDoesNotEraseCachedUsage() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let complete = Data(#"{"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":40}}}"#.utf8)
        let fiveOnly = Data(#"{"rate_limits":{"five_hour":{"used_percentage":25}}}"#.utf8)

        _ = try StatusLineProcessor.run(input: complete, store: store)
        _ = try StatusLineProcessor.run(input: fiveOnly, store: store)

        XCTAssertEqual(store.load()?.fiveHourUsage, 25)
        XCTAssertEqual(store.load()?.sevenDayUsage, 40)
    }

    func testStatusLineFallsBackToPersistedStateWhenLimitsMissing() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 41,
            fiveHourResetAt: 1_784_140_200,
            sevenDayUsage: 28,
            sevenDayResetAt: 1_784_300_400,
            notifiedThresholds: [25],
            usageUpdatedAt: "2026-07-15T19:00:00Z"
        )
        let output = UsageFormatter.statusLine(nil, fallback: state, relativeTo: now)
        XCTAssertTrue(output.contains("Claude 5h: 41%"), output)
        XCTAssertTrue(output.contains("7d: 28%"), output)
        XCTAssertTrue(output.contains("reinicia"), output)
    }

    func testStatusLineWithoutLimitsOrFallbackShowsPlaceholder() {
        XCTAssertEqual(UsageFormatter.statusLine(nil), "Claude 5h: --")
    }

    func testStatusLineMarksCriticalUsage() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let limits = RateLimits(
            fiveHour: UsageWindow(usedPercentage: 95, resetsAt: 1_784_140_200),
            sevenDay: nil
        )
        let output = UsageFormatter.statusLine(limits, relativeTo: now)
        XCTAssertTrue(output.contains("95%"), output)
        XCTAssertTrue(output.contains("⚠️"), output)
    }

    func testPercentageStripsFloatingPointNoise() {
        XCTAssertEqual(UsageFormatter.percentage(28.000000000000004), "28")
        XCTAssertEqual(UsageFormatter.percentage(33), "33")
        XCTAssertEqual(UsageFormatter.percentage(33.5), "33.5")
    }

    func testProcessorShowsCachedUsageWhenPayloadOmitsRateLimits() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let withLimits = Data(#"{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1900000000},"seven_day":{"used_percentage":40,"resets_at":1900100000}}}"#.utf8)
        let withoutLimits = Data(#"{"model":{"display_name":"Opus"}}"#.utf8)

        _ = try StatusLineProcessor.run(input: withLimits, store: store)
        let output = try StatusLineProcessor.run(input: withoutLimits, store: store)

        XCTAssertTrue(output.contains("Claude 5h: 20%"), output)
        XCTAssertTrue(output.contains("7d: 40%"), output)
    }

    func testMigratesLegacyStateKeys() throws {
        let paths = try temporaryPaths()
        let legacy = Data(#"{"lastUsage":35,"fiveHourResetAt":1900000000,"sevenDayUsage":12,"notifiedThresholds":[25],"updatedAt":"2026-07-15T18:00:00Z"}"#.utf8)
        try legacy.write(to: paths.stateFile)

        let store = StateStore(paths: paths)
        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.fiveHourUsage, 35)
        XCTAssertEqual(state.usageUpdatedAt, "2026-07-15T18:00:00Z")

        try store.save(state)
        let saved = String(decoding: try Data(contentsOf: paths.stateFile), as: UTF8.self)
        XCTAssertTrue(saved.contains("fiveHourUsage"))
        XCTAssertFalse(saved.contains("lastUsage"))
    }

    func testUsageFormattersForSessionDetails() {
        XCTAssertEqual(UsageFormatter.tokenCount(15_500), "15.5k")
        XCTAssertEqual(UsageFormatter.tokenCount(1_000_000), "1.0M")
        XCTAssertEqual(UsageFormatter.duration(milliseconds: 5_400_000), "1h 30min")
    }

    func testSettingsInstallAndUninstallRestorePreviousStatusLine() throws {
        let paths = try temporaryPaths()
        let previous: [String: Any] = [
            "model": "opus",
            "statusLine": ["type": "command", "command": "printf previous"],
        ]
        try writeJSON(previous, to: paths.claudeSettingsFile)

        let executable = "/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        try SettingsManager.install(executablePath: executable, paths: paths)
        XCTAssertTrue(try SettingsManager.isInstalled(executablePath: executable, paths: paths))

        try SettingsManager.uninstall(executablePath: executable, paths: paths)
        let restored = try readJSON(paths.claudeSettingsFile)
        let statusLine = restored["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "printf previous")
        XCTAssertEqual(restored["model"] as? String, "opus")
    }

    func testSettingsRepairsIncorrectStatusLineType() throws {
        let paths = try temporaryPaths()
        let executable = "/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        let command = SettingsManager.desiredCommand(executablePath: executable)
        try writeJSON(
            ["statusLine": ["type": "text", "command": command]],
            to: paths.claudeSettingsFile
        )

        XCTAssertFalse(try SettingsManager.isInstalled(executablePath: executable, paths: paths))
        XCTAssertEqual(
            try SettingsManager.integrationStatus(executablePath: executable, paths: paths),
            .misconfigured
        )

        try SettingsManager.install(executablePath: executable, paths: paths)
        let repaired = try readJSON(paths.claudeSettingsFile)["statusLine"] as? [String: Any]
        XCTAssertEqual(repaired?["type"] as? String, "command")
        XCTAssertTrue(try SettingsManager.isInstalled(executablePath: executable, paths: paths))
    }

    func testUninstallPreservesStatusLineChangedByUser() throws {
        let paths = try temporaryPaths()
        let executable = "/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        try SettingsManager.install(executablePath: executable, paths: paths)
        try writeJSON(
            ["statusLine": ["type": "command", "command": "printf user-value"]],
            to: paths.claudeSettingsFile
        )

        try SettingsManager.uninstall(executablePath: executable, paths: paths)
        let settings = try readJSON(paths.claudeSettingsFile)
        let statusLine = settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "printf user-value")
    }

    func testPreviousStatusLineOutputIsBounded() throws {
        let paths = try temporaryPaths()
        let backup: [String: Any] = [
            "hadStatusLine": true,
            "statusLine": [
                "type": "command",
                "command": "/usr/bin/yes x | /usr/bin/head -c 1100000",
            ],
        ]
        try writeJSON(backup, to: paths.statusLineBackupFile)
        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#.utf8)

        let output = try StatusLineProcessor.run(input: input, store: StateStore(paths: paths))
        XCTAssertEqual(output, "Claude 5h: 10%")
    }

    func testSettingsMigrationRecognizesLegacyMonitor() {
        XCTAssertTrue(SettingsManager.isMonitorCommand(
            "/bin/zsh '/Users/test/Library/Application Support/ClaudeUsageMonitor/app/run-monitor.command' --ingest-statusline"
        ))
        XCTAssertTrue(SettingsManager.isMonitorCommand(
            "'/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor' --ingest-statusline"
        ))
        XCTAssertFalse(SettingsManager.isMonitorCommand(
            "printf ClaudeUsageMonitor --ingest-statusline"
        ))
        XCTAssertFalse(SettingsManager.isMonitorCommand(
            "printf ClaudeUsageMonitor --ingest-statusline extra"
        ))
    }

    func testSettingsCommandUsesAbsoluteExecutablePath() {
        let command = SettingsManager.desiredCommand(
            executablePath: "dist/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        )
        XCTAssertTrue(command.hasPrefix("'/"))
        XCTAssertTrue(command.hasSuffix(" --ingest-statusline"))
    }

    func testIntegrationDetectsDisableAllHooks() throws {
        let paths = try temporaryPaths()
        let executable = "/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        try SettingsManager.install(executablePath: executable, paths: paths)
        var settings = try readJSON(paths.claudeSettingsFile)
        settings["disableAllHooks"] = true
        try writeJSON(settings, to: paths.claudeSettingsFile)

        XCTAssertEqual(
            try SettingsManager.integrationStatus(executablePath: executable, paths: paths),
            .disabledByHooks
        )
    }

    func testIntegrationReportsActiveConfiguration() throws {
        let paths = try temporaryPaths()
        let executable = "/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"
        try SettingsManager.install(executablePath: executable, paths: paths)
        XCTAssertEqual(
            try SettingsManager.integrationStatus(executablePath: executable, paths: paths),
            .active
        )
    }

    func testMenuViewsRenderAtStableSizes() throws {
        let meter = UsageMeterView(title: "Limite de 5 horas")
        meter.update(
            percentage: 42,
            value: "42%",
            detail: "Reinício: 15/07, 20:30 • em 4h"
        )
        let header = MonitorHeaderView()
        header.setAccountTitle("person@example.com")
        header.setHealth(.healthy, detail: "Dados recebidos e integração ativa")
        [meter, header].forEach {
            $0.wantsLayer = true
        }

        // As views dimensionam-se por Auto Layout dentro do painel: o teste dá
        // a largura de conteúdo do painel e deixa a altura resolver-se, em vez
        // de comparar com um tamanho fixo que já não existe.
        let contentWidth = Metrics.panelWidth - Metrics.gutter * 2
        [meter, header].forEach { view in
            view.frame = NSRect(
                origin: .zero,
                size: NSSize(width: contentWidth, height: view.fittingSize.height)
            )
            view.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(meter.frame.height, 0)
        XCTAssertGreaterThan(header.frame.height, 0)

        let light = try renderMenuViews(meter: meter, header: header, appearance: .aqua)
        let dark = try renderMenuViews(meter: meter, header: header, appearance: .darkAqua)
        XCTAssertGreaterThan(light.meter.count, 500)
        XCTAssertGreaterThan(light.header.count, 500)
        XCTAssertGreaterThan(dark.meter.count, 500)
        XCTAssertGreaterThan(dark.header.count, 500)
        XCTAssertNotEqual(light.meter, dark.meter)
        XCTAssertNotEqual(light.header, dark.header)

        if let directory = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try light.meter.write(to: root.appendingPathComponent("usage-meter-light.png"))
            try dark.meter.write(to: root.appendingPathComponent("usage-meter-dark.png"))
            try light.header.write(to: root.appendingPathComponent("monitor-header-light.png"))
            try dark.header.write(to: root.appendingPathComponent("monitor-header-dark.png"))
        }
    }

    private func renderMenuViews(
        meter: NSView,
        header: NSView,
        appearance name: NSAppearance.Name
    ) throws -> (meter: Data, header: Data) {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        [meter, header].forEach { view in
            view.appearance = appearance
            appearance.performAsCurrentDrawingAppearance {
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            view.needsDisplay = true
        }
        return (try renderedPNG(meter), try renderedPNG(header))
    }

    private func temporaryPaths() throws -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
    }

    private func writeJSON(_ object: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: file, options: .atomic)
    }

    private func readJSON(_ file: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func renderedPNG(_ view: NSView) throws -> Data {
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
