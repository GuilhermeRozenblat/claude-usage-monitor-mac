import AppKit
import XCTest
@testable import ClaudeUsageMonitor

final class SettingsWindowTests: XCTestCase {
    private func controller() -> SettingsWindowController {
        SettingsWindowController(
            alertPreferences: AlertPreferences(defaults: scratchDefaults()),
            shortcut: GlobalShortcut(defaults: scratchDefaults()),
            onReconfigure: {},
            onDataFolder: {},
            onLanguageChange: {}
        )
    }

    /// Os toggles escrevem em UserDefaults: um suite próprio impede o teste de
    /// mexer nas preferências reais de quem o corre.
    private func scratchDefaults() -> UserDefaults {
        let suite = "ClaudeUsageMonitorTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// Todos os painéis têm de assentar na mesma largura, senão a janela salta
    /// de tamanho ao trocar de aba.
    func testPanesShareOneWidthAndFitTheirContent() throws {
        let panes = controller().panesForTesting
        XCTAssertFalse(panes.isEmpty)
        for pane in panes {
            let size = pane.view.fittingSize
            XCTAssertGreaterThan(size.height, 60, "painel vazio")
            XCTAssertLessThan(size.height, 460, "painel alto demais para ajustes")
        }
    }

    func testPanesRenderInBothAppearances() throws {
        let previewDir = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"]
        let panes = controller().panesForTesting

        for (index, pane) in panes.enumerated() {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let resolved = try XCTUnwrap(NSAppearance(named: appearance))
                let view = pane.view
                view.appearance = resolved
                view.wantsLayer = true
                resolved.performAsCurrentDrawingAppearance {
                    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                }
                // De propósito mais alto que o conteúdo: é assim que a janela
                // fica quando a outra aba é maior. Renderizar no tamanho justo
                // escondia um vão de 95 pt que a grade abria ao esticar.
                view.frame = NSRect(
                    origin: .zero,
                    size: NSSize(width: view.fittingSize.width, height: view.fittingSize.height + 60)
                )
                view.layoutSubtreeIfNeeded()

                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 2_000, "painel \(index) \(name) parece vazio")

                if let previewDir {
                    let root = URL(fileURLWithPath: previewDir, isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try png.write(to: root.appendingPathComponent("settings-\(index)-\(name).png"))
                }
            }
        }
    }
}
