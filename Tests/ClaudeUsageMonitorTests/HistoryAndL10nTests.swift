import AppKit
import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class HistoryAndL10nTests: XCTestCase {
    // MARK: - L10n

    func testLanguageDetectionPrefersFirstKnownLanguage() {
        XCTAssertEqual(L10n.detect(preferred: ["pt-BR", "en"]), .ptBR)
        XCTAssertEqual(L10n.detect(preferred: ["pt-PT"]), .ptBR)
        XCTAssertEqual(L10n.detect(preferred: ["es-MX", "en-US"]), .es)
        XCTAssertEqual(L10n.detect(preferred: ["fr-FR", "es-ES"]), .es)
        XCTAssertEqual(L10n.detect(preferred: ["en-US", "pt-BR"]), .en)
        XCTAssertEqual(L10n.detect(preferred: ["fr-FR", "de-DE"]), .en)
        XCTAssertEqual(L10n.detect(preferred: []), .en)
    }

    func testLanguagePreferenceResolvesManualAndAutomaticChoices() {
        XCTAssertEqual(LanguagePreference.automatic.resolved(preferred: ["es-AR"]), .es)
        XCTAssertEqual(LanguagePreference.automatic.resolved(preferred: ["ja-JP"]), .en)
        XCTAssertEqual(LanguagePreference.en.resolved(preferred: ["pt-BR"]), .en)
        XCTAssertEqual(LanguagePreference.ptBR.resolved(preferred: ["en-US"]), .ptBR)
        XCTAssertEqual(LanguagePreference.es.resolved(preferred: ["en-US"]), .es)
    }

    func testLanguagePreferencePersistsAndInvalidValueFallsBackToAutomatic() throws {
        let suite = "ClaudeUsageMonitorTests.Language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LanguageSettings(defaults: defaults)

        XCTAssertEqual(settings.preference, .automatic)
        settings.set(.es)
        XCTAssertEqual(LanguageSettings(defaults: defaults).preference, .es)

        defaults.set("unsupported", forKey: LanguageSettings.key)
        XCTAssertEqual(settings.preference, .automatic)
    }

    /// O relógio era "HH:mm" fixo em todos os idiomas: um utilizador dos EUA
    /// via "14:32" onde o sistema inteiro lhe mostra "2:32 PM". O formato tem
    /// de sair do locale, não de um literal.
    func testClockFormatFollowsLocaleConventions() {
        let previous = L10n.language
        defer { L10n.language = previous }

        L10n.language = .en
        let english = L10n.clockFormat
        XCTAssertTrue(
            english.contains("h") && english.contains("a"),
            "Inglês dos EUA usa relógio de 12 h com AM/PM, obteve \(english)"
        )

        // 24 h = campo "H", sem o marcador "a" de AM/PM. O número de "H" é do
        // locale e não nosso: pt-BR escreve "09:05" e es-ES escreve "9:05",
        // o literal "HH:mm" antigo impunha o zero à esquerda aos dois.
        for language in [AppLanguage.ptBR, .es] {
            L10n.language = language
            let format = L10n.clockFormat
            XCTAssertTrue(format.contains("H"), "\(language) usa 24 h, obteve \(format)")
            XCTAssertFalse(format.contains("a"), "\(language) não usa AM/PM, obteve \(format)")
        }
    }

    /// Os formatos de data vinham de literais por idioma e todos fixavam 24 h.
    func testDateFormatsAreLocaleDerivedAndNotHardcoded() {
        let previous = L10n.language
        defer { L10n.language = previous }

        L10n.language = .en
        XCTAssertFalse(
            L10n.shortDateTimeFormat.contains("HH"),
            "Inglês não deveria forçar 24 h, obteve \(L10n.shortDateTimeFormat)"
        )

        L10n.language = .ptBR
        // Um formato derivado do locale continua a nomear mês e hora.
        XCTAssertTrue(L10n.shortDateTimeFormat.contains("MMM"))
        XCTAssertTrue(L10n.updatedTimeFormat.contains("ss"))
    }

    func testSpanishStringsAndFormatting() {
        let previous = L10n.language
        L10n.language = .es
        defer { L10n.language = previous }

        XCTAssertEqual(L10n.fiveHourMeterTitle, "Límite de 5 horas")
        XCTAssertEqual(L10n.languageMenuTitle, "Idioma")
        XCTAssertEqual(L10n.madeInBrazil, "Hecho en Brasil")
        XCTAssertEqual(L10n.effortLevel("xhigh"), "muy alto")
        XCTAssertEqual(UsageFormatter.elapsedTime(120), "hace 2min")
        XCTAssertEqual(L10n.recentSessionWithoutLimits, "Claude Code activo • límites no enviados")

        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 41,
            fiveHourResetAt: now.timeIntervalSince1970 + 8_100
        )
        XCTAssertEqual(
            UsageFormatter.summary(state, relativeTo: now),
            "5 horas: 41% (se reinicia en 2h 15min)"
        )
    }

    func testEnglishIsDefaultForFormatter() {
        L10n.language = .en
        defer { L10n.language = .ptBR }

        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 41,
            fiveHourResetAt: now.timeIntervalSince1970 + 8_100,
            usageUpdatedAt: "2026-07-15T19:00:00Z"
        )
        let summary = UsageFormatter.summary(state, relativeTo: now)
        XCTAssertTrue(summary.contains("5 hours: 41% (resets in 2h 15min)"), summary)

        let expired = UsageState(fiveHourUsage: 90, fiveHourResetAt: now.timeIntervalSince1970 - 60)
        XCTAssertEqual(
            UsageFormatter.summary(expired, relativeTo: now),
            "5 hours: waiting for a new window"
        )
        XCTAssertEqual(UsageFormatter.elapsedTime(30), "now")
        XCTAssertEqual(UsageFormatter.elapsedTime(120), "2min ago")
    }

    func testPortugueseStringsPreserved() {
        L10n.language = .ptBR
        XCTAssertEqual(UsageFormatter.elapsedTime(120), "há 2min")
        XCTAssertEqual(
            L10n.noRecentData("há 20min"),
            "Última atualização há 20min • envie no Claude Code"
        )
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let output = UsageFormatter.statusLine(
            RateLimits(
                fiveHour: UsageWindow(usedPercentage: 40, resetsAt: now.timeIntervalSince1970 + 3_600),
                sevenDay: nil
            ),
            relativeTo: now
        )
        XCTAssertTrue(output.contains("reinicia em 1h"), output)
    }

    // MARK: - HistoryStore

    func testAppendAndLoadRoundTrip() throws {
        let paths = try temporaryPaths()
        let store = HistoryStore(paths: paths)

        store.append(fiveHour: 40, sevenDay: 20)
        let samples = store.load(range: 3_600)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].h5, 40)
        XCTAssertEqual(samples[0].d7, 20)
    }

    func testAppendThrottlesByLastSampleTimestamp() throws {
        let paths = try temporaryPaths()
        let store = HistoryStore(paths: paths)

        store.append(fiveHour: 40, sevenDay: nil)
        store.append(fiveHour: 55, sevenDay: nil)
        XCTAssertEqual(store.load(range: 3_600).count, 1, "Segunda amostra em <60s deveria ser descartada")
    }

    func testAppendSkipsWhenNoValues() throws {
        let paths = try temporaryPaths()
        HistoryStore(paths: paths).append(fiveHour: nil, sevenDay: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.historyFile.path))
    }

    func testLoadFiltersRangeAndToleratesGarbage() throws {
        let paths = try temporaryPaths()
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        var lines = [
            #"{"t":1783996400,"h5":10,"d7":5}"#,
            "not-json",
            #"{"t":1783999400,"h5":50,"d7":25}"#,
            #"{"t":1700000000,"h5":99,"d7":99}"#,
        ]
        lines.append("")
        try lines.joined(separator: "\n").data(using: .utf8)!.write(to: paths.historyFile)

        let samples = HistoryStore(paths: paths).load(range: 3_600 * 2, now: now)
        XCTAssertEqual(samples.map(\.h5), [10, 50], "Deveria filtrar por período e ignorar lixo")
    }

    func testPruneDropsOldSamples() throws {
        let paths = try temporaryPaths()
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let old = now.timeIntervalSince1970 - HistoryStore.retention - 60
        let recent = now.timeIntervalSince1970 - 60
        try """
        {"t":\(old),"h5":10,"d7":5}
        {"t":\(recent),"h5":50,"d7":25}
        """.data(using: .utf8)!.write(to: paths.historyFile)

        let store = HistoryStore(paths: paths)
        store.prune(now: now)
        let samples = store.load(range: HistoryStore.retention, now: now)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].h5, 50)
    }

    func testPruneDoesNotThrottleANewerSample() throws {
        let paths = try temporaryPaths()
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let old = now.timeIntervalSince1970 - HistoryStore.retention - 60
        let recent = now.timeIntervalSince1970 - 120
        try """
        {"t":\(old),"h5":10,"d7":5}
        {"t":\(recent),"h5":50,"d7":25}
        """.data(using: .utf8)!.write(to: paths.historyFile)

        let store = HistoryStore(paths: paths)
        store.prune(now: now)
        store.append(fiveHour: 55, sevenDay: 30, now: now)

        XCTAssertEqual(store.load(range: HistoryStore.retention, now: now).map(\.h5), [50, 55])
    }

    func testDownsampleKeepsPeaks() {
        let base: TimeInterval = 1_784_000_000
        var samples: [HistorySample] = []
        for index in 0..<1_000 {
            let timestamp = base + Double(index * 60)
            let fiveHour = index == 500 ? 98.0 : Double(index % 50)
            samples.append(HistorySample(t: timestamp, h5: fiveHour, d7: nil))
        }
        let reduced = HistoryStore.downsample(samples, limit: 100)
        let fiveHourValues = reduced.compactMap { $0.h5 }
        XCTAssertLessThanOrEqual(reduced.count, 100)
        XCTAssertEqual(fiveHourValues.max(), 98, "O pico deveria sobreviver ao downsample")
        XCTAssertEqual(reduced, reduced.sorted { $0.t < $1.t }, "Ordem cronológica preservada")
    }

    func testIngestRecordsHistorySample() throws {
        let paths = try temporaryPaths()
        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":60,"resets_at":1900000000}}}"#.utf8)
        _ = try StatusLineProcessor.run(input: input, store: StateStore(paths: paths))

        let samples = HistoryStore(paths: paths).load(range: 3_600)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].h5, 60)
    }

    func testHistoryChartRenders() throws {
        L10n.language = .ptBR
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        // Duas rampas de uso com uma lacuna de 4h no meio para validar a
        // quebra de linha, e um pico acima da referência de 90%.
        var samples: [HistorySample] = []
        for minute in stride(from: 0, to: 600, by: 5) {
            samples.append(HistorySample(
                t: now.timeIntervalSince1970 - 24 * 3600 + Double(minute) * 60,
                h5: min(96, Double(minute) / 6),
                d7: 20 + Double(minute) / 40
            ))
        }
        for minute in stride(from: 840, to: 1_380, by: 5) {
            samples.append(HistorySample(
                t: now.timeIntervalSince1970 - 24 * 3600 + Double(minute) * 60,
                h5: Double(minute - 840) / 8,
                d7: 35 + Double(minute - 840) / 60
            ))
        }

        let chart = HistoryChartView(frame: NSRect(x: 0, y: 0, width: 648, height: 300))
        chart.show(
            samples: samples,
            range: .day,
            span: ChartSpan.resolve(range: .day, resetAt: nil, now: now),
            now: now
        )
        chart.wantsLayer = true
        let lightPNG = try renderChart(chart, appearance: .aqua)
        let darkPNG = try renderChart(chart, appearance: .darkAqua)
        XCTAssertGreaterThan(lightPNG.count, 2_000)
        XCTAssertGreaterThan(darkPNG.count, 2_000)
        XCTAssertNotEqual(lightPNG, darkPNG)

        if let directory = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try lightPNG.write(to: root.appendingPathComponent("history-chart-light.png"))
            try darkPNG.write(to: root.appendingPathComponent("history-chart-dark.png"))
        }
    }

    private func renderChart(
        _ chart: HistoryChartView,
        appearance name: NSAppearance.Name
    ) throws -> Data {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        chart.appearance = appearance
        appearance.performAsCurrentDrawingAppearance {
            chart.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        chart.needsDisplay = true
        return try renderedPNG(chart)
    }

    func testTrendViewRenders() throws {
        L10n.language = .ptBR
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let samples = (0..<48).map { index in
            HistorySample(
                t: now.timeIntervalSince1970 - Double((48 - index) * 60),
                h5: 30 + Double(index),
                d7: nil
            )
        }
        let projection = PaceEstimator.projectedLimitDate(
            samples: samples,
            currentUsage: 77,
            resetAt: now.timeIntervalSince1970 + 4 * 3_600,
            now: now
        )
        XCTAssertNotNil(projection, "Subida de 1 ponto/min deveria projetar limite")

        let view = TrendView()
        view.appearance = NSAppearance(named: .aqua)
        view.update(
            samples: samples,
            projectedLimit: projection,
            ratePerHour: PaceEstimator.slopePerHour(samples: samples, now: now),
            span: ChartSpan.resolve(range: .window, resetAt: nil, now: now),
            now: now
        )
        // Auto Layout: sem uma largura dada, a view fica com bounds zero e não
        // há bitmap para capturar.
        view.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: Metrics.panelWidth - Metrics.gutter * 2,
                height: view.fittingSize.height
            )
        )
        view.layoutSubtreeIfNeeded()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(
            srgbRed: 0xFC / 255, green: 0xFC / 255, blue: 0xFB / 255, alpha: 1
        ).cgColor

        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 500)

        if let directory = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent("trend-view.png"))
        }
    }

    func testAboutWindowContainsAuthorAndBrazilBadge() throws {
        L10n.language = .ptBR
        let controller = AboutWindowController()
        controller.window?.appearance = NSAppearance(named: .aqua)
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let labels = allSubviews(of: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains { $0.contains("Guilherme Rozenblat") })
        XCTAssertTrue(labels.contains("🇧🇷"))
        // "Feito no Brasil" saiu do ecrã: a bandeira já o diz, e o texto ao lado
        // dela repetia-o. Continua a existir para quem usa VoiceOver.
        XCTAssertTrue(
            allSubviews(of: content).contains {
                ($0.accessibilityLabel() ?? "").contains(L10n.madeInBrazil)
            }
        )

        let lightPNG = try renderedPNG(content)
        controller.window?.appearance = NSAppearance(named: .darkAqua)
        content.layoutSubtreeIfNeeded()
        let darkPNG = try renderedPNG(content)
        XCTAssertGreaterThan(lightPNG.count, 1_000)
        XCTAssertGreaterThan(darkPNG.count, 1_000)
        XCTAssertNotEqual(lightPNG, darkPNG)
        if let directory = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try lightPNG.write(to: root.appendingPathComponent("about-window-light.png"))
            try darkPNG.write(to: root.appendingPathComponent("about-window-dark.png"))
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    private func renderedPNG(_ view: NSView) throws -> Data {
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
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
}
