import AppKit
import XCTest
@testable import ClaudeUsageMonitor

final class MonitorPanelTests: XCTestCase {
    /// O painel monta-se por Auto Layout a partir de uma pilha de secções. Se
    /// alguma restrição entrar em conflito, ou uma secção colapsar, isto
    /// aparece como altura absurda ou como um render vazio, antes de chegar à
    /// barra de menus.
    func testPanelAssemblesAtPlausibleSize() throws {
        let controller = MonitorPanelController()
        let content = controller.contentViewForTesting
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.fittingSize.width, Metrics.panelWidth)
        // Cabeçalho + três medidores + tendência + estados + ações não cabem
        // em menos de 300 pt, e não deveriam passar da altura de um ecrã.
        XCTAssertGreaterThan(content.fittingSize.height, 300)
        XCTAssertLessThan(content.fittingSize.height, 700)
    }

    /// Os detalhes começam recolhidos: abrir o painel não deve despejar oito
    /// linhas de metadados em cima de quem só quer ver a percentagem.
    func testSessionDetailsStartCollapsedAndAddHeightWhenShown() throws {
        let controller = MonitorPanelController()
        let content = controller.contentViewForTesting
        content.layoutSubtreeIfNeeded()
        let collapsed = content.fittingSize.height

        XCTAssertTrue(controller.sessionDetails.isHidden)
        controller.sessionDetails.isHidden = false
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(content.fittingSize.height, collapsed)
    }

    func testPanelRendersInBothAppearances() throws {
        let controller = MonitorPanelController()
        controller.header.setAccountTitle("person@example.com")
        controller.header.setHealth(.healthy, detail: L10n.healthyDetail)
        controller.fiveHour.update(percentage: 42, value: "42%", detail: L10n.resets("20:30"))
        controller.sevenDay.update(percentage: 18, value: "18%", detail: L10n.resets("21/07"))
        controller.context.update(percentage: 31, value: "31%", detail: "24k tokens • 69% livre")
        // Sem `update`, a sparkline fica visível e vazia a ocupar 96 pt, e o
        // rótulo parece centrado. O app real chama-a sempre.
        controller.trend.update(
            samples: [],
            projectedLimit: nil,
            ratePerHour: nil,
            span: ChartSpan.resolve(range: .window, resetAt: nil, now: Date()),
            now: Date()
        )
        controller.updatedRow.update(symbol: "clock.arrow.circlepath", text: L10n.usageUpdated("agora"))
        controller.integrationRow.update(
            symbol: "checkmark.circle.fill",
            text: L10n.integration(L10n.integrationActive),
            tint: .systemGreen
        )
        controller.notificationsRow.update(
            symbol: "bell.fill",
            text: L10n.notifications(L10n.notificationsActive)
        )
        controller.sessionDetails.update([
            "Sonnet 4.5", "api-gateway", "refactor auth", "alto • thinking ativo",
            "12min", "US$ 0,42", L10n.costPeriodValue("US$ 1,20", "US$ 8,90"), "2.1.0",
        ])

        let content = controller.contentViewForTesting
        let previewDir = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MONITOR_PREVIEW_DIR"]
        // Os detalhes abertos são o estado mais alto do painel: é aqui que uma
        // grade desalinhada ou um valor cortado aparece.
        controller.sessionDetails.isHidden = false

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let resolved = try XCTUnwrap(NSAppearance(named: appearance))
            content.appearance = resolved
            // No app o vidro dá o fundo. Fora do ecrã não há vidro, e sem um
            // fundo o texto branco do modo escuro sai invisível: o PNG mentia
            // sobre um painel que está correto.
            content.wantsLayer = true
            resolved.performAsCurrentDrawingAppearance {
                content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            controller.layOutForTesting()

            let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            // Um PNG em branco do tamanho do painel já passa dos 500 bytes: o piso
            // tem de ser alto o suficiente para exigir conteúdo desenhado.
            XCTAssertGreaterThan(png.count, 5_000, "Painel \(name) parece vazio")

            if let previewDir {
                let root = URL(fileURLWithPath: previewDir, isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try png.write(to: root.appendingPathComponent("panel-\(name).png"))
            }
        }
    }
}
