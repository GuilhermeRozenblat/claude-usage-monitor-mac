import AppKit

/// Monta, posiciona e descarta o painel. As views ficam expostas para o
/// MenuBarApp preencher: o controller cuida da forma, não dos dados.
final class MonitorPanelController {
    let header = MonitorHeaderView()
    let trend = TrendView()
    let fiveHour = UsageMeterView(title: L10n.fiveHourMeterTitle)
    let sevenDay = UsageMeterView(title: L10n.sevenDayMeterTitle)
    let context = UsageMeterView(title: L10n.contextMeterTitle)
    let sessionDetails = SessionDetailsView()
    let updatedRow = StatusRowView()
    let integrationRow = StatusRowView()
    let notificationsRow = StatusRowView()
    /// Só aparece quando sobra algo para o utilizador fazer. O que o app
    /// conserta sozinho não deixa rasto aqui.
    let remedyRow = RemedyRowView()

    var onRefresh: (() -> Void)?
    var onCopy: (() -> Void)?
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onReconfigure: (() -> Void)?
    var onDataFolder: (() -> Void)?
    var onQuit: (() -> Void)?
    var onWillOpen: (() -> Void)?

    private let panel: MonitorPanel
    private let disclosure = NSButton()
    private let refreshButton = NSButton()
    private let historyButton = NSButton()
    private let aboutButton = NSButton()
    private let settingsButton = NSButton()
    private let overflowButton = NSButton()
    private let overflowMenu = NSMenu()
    private let stack = NSStackView()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var statusButton: NSStatusBarButton?

    var isVisible: Bool { panel.isVisible }

    /// A pilha de conteúdo, para os testes a medirem sem pôr um painel no ecrã.
    ///
    /// É a pilha, não `panel.contentView`: o NSGlassEffectView é um efeito
    /// composto na GPU e não desenha o conteúdo através de `cacheDisplay`
    /// fora do ecrã; capturá-lo devolve uma imagem vazia.
    var contentViewForTesting: NSView { stack }

    /// Solta a pilha do vidro e dimensiona-a, para os testes a renderizarem.
    ///
    /// O NSGlassEffectView não participa no Auto Layout: não propaga o tamanho
    /// do `contentView` para cima, então medir a partir da raiz devolve só a
    /// margem da sombra. Fora do vidro a pilha mede-se sozinha.
    @discardableResult
    func layOutForTesting() -> NSView {
        stack.removeFromSuperview()
        stack.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Metrics.panelWidth, height: stack.fittingSize.height)
        )
        stack.layoutSubtreeIfNeeded()
        return stack
    }

    init() {
        panel = MonitorPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // A sombra é nossa (ver Glass.panelSurface): a da janela sai quadrada.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.setAccessibilityLabel("Claude Usage Monitor")

        buildContent()
    }

    deinit {
        removeMonitors()
    }

    // MARK: Construção

    private func buildContent() {
        configureButtons()

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.rowSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: Metrics.gutter,
            left: Metrics.gutter,
            bottom: Metrics.gutter,
            right: Metrics.gutter
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A largura é fixa e declarada, não herdada do painel: sem isto,
        // `fittingSize.height` resolve-se na largura natural do conteúdo (~166
        // pt) e devolve uma altura que não corresponde ao painel de 340 pt.
        stack.widthAnchor.constraint(equalToConstant: Metrics.panelWidth).isActive = true

        // Os medidores respiram por espaçamento; as réguas separam zonas, não
        // linhas. Um separador entre cada item lia-se como ruído.
        let sections: [NSView] = [
            header,
            SeparatorView(),
            fiveHour,
            trend,
            sevenDay,
            context,
            SeparatorView(),
            disclosure,
            sessionDetails,
            SeparatorView(),
            updatedRow,
            integrationRow,
            notificationsRow,
            remedyRow,
            SeparatorView(),
            actionBar(),
        ]
        sections.forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -Metrics.gutter * 2)
                .isActive = true
        }

        // Ritmo: os medidores ficam mais próximos entre si do que das zonas
        // vizinhas, e a tendência cola no medidor de 5 h que ela descreve.
        stack.setCustomSpacing(6, after: fiveHour)
        stack.setCustomSpacing(Metrics.rowSpacing + 2, after: trend)
        stack.setCustomSpacing(6, after: updatedRow)
        stack.setCustomSpacing(6, after: integrationRow)

        sessionDetails.isHidden = true

        panel.contentView = Glass.panelSurface(stack)
        applyLocalizedTitles()
        resize()
    }

    private func configureButtons() {
        // A bezel `.disclosure` desenha o triângulo e ignora o título, o que
        // deixava um ">" solto no meio do painel. Um botão sem moldura com
        // chevron + texto diz o que revela e alinha à esquerda.
        disclosure.isBordered = false
        disclosure.setButtonType(.onOff)
        disclosure.imagePosition = .imageLeading
        disclosure.alignment = .left
        disclosure.target = self
        disclosure.action = #selector(toggleDetails)
        updateDisclosureImage()

        // Só ícones: três botões com rótulo não cabem em 340 pt e o AppKit
        // trunca-os para "…". É também o vocabulário da Central de Controlo.
        // O texto vive no tooltip e no rótulo de acessibilidade.
        for (button, symbol, action) in [
            (refreshButton, "arrow.clockwise", #selector(refresh)),
            (historyButton, "chart.xyaxis.line", #selector(history)),
            (aboutButton, "info.circle", #selector(about)),
            (settingsButton, "gearshape", #selector(settings)),
            (overflowButton, "ellipsis", #selector(showOverflow)),
        ] as [(NSButton, String, Selector)] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        }
    }

    private func updateDisclosureImage() {
        let symbol = disclosure.state == .on ? "chevron.down" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        disclosure.image = image
        disclosure.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
    }

    private func actionBar() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            refreshButton, historyButton, aboutButton, spacer, settingsButton, overflowButton,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        // `.gravityAreas` (o padrão) centra o conjunto e ignora o espaçador;
        // `.fill` deixa o espaçador empurrar ajustes e "•••" para a direita.
        row.distribution = .fill
        row.spacing = 6
        return row
    }

    /// Ações raras vivem atrás do "•••": o painel mostra o que se usa a toda a
    /// hora, não tudo o que o app sabe fazer.
    private func rebuildOverflowMenu() {
        overflowMenu.removeAllItems()
        let entries: [(String, Selector)] = [
            (L10n.copyUsageSummary, #selector(copy)),
            (L10n.reconfigureClaudeCode, #selector(reconfigure)),
            (L10n.openDataFolder, #selector(dataFolder)),
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            overflowMenu.addItem(item)
        }
        overflowMenu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        overflowMenu.addItem(quit)
    }

    func applyLocalizedTitles() {
        fiveHour.setTitle(L10n.fiveHourMeterTitle)
        sevenDay.setTitle(L10n.sevenDayMeterTitle)
        context.setTitle(L10n.contextMeterTitle)
        sessionDetails.applyLocalizedTitles()

        disclosure.title = " " + L10n.sessionDetails
        disclosure.font = .systemFont(ofSize: 11, weight: .medium)
        disclosure.contentTintColor = .secondaryLabelColor
        disclosure.setAccessibilityLabel(L10n.sessionDetails)

        // Botões só de ícone: o rótulo tem de existir para o VoiceOver e para
        // o tooltip, senão a ação fica anónima.
        for (button, label) in [
            (refreshButton, L10n.refreshDisplay),
            (historyButton, L10n.usageHistory),
            (aboutButton, L10n.about),
            (settingsButton, L10n.settings),
            (overflowButton, L10n.moreOptions),
        ] {
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }

        rebuildOverflowMenu()
        resize()
    }

    // MARK: Apresentação

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        statusButton = button
        onWillOpen?()
        resize()
        position(relativeTo: button)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
        statusButton?.highlight(false)
    }

    /// A janela é maior que o painel visível: a sombra precisa de folga
    /// transparente à volta do vidro para não ser recortada na borda.
    private func resize() {
        stack.layoutSubtreeIfNeeded()
        let margin = Metrics.shadowMargin * 2
        panel.setContentSize(NSSize(
            width: Metrics.panelWidth + margin,
            height: stack.fittingSize.height + margin
        ))
    }

    /// Ancorado ao botão da barra, preso ao ecrã.
    ///
    /// As contas são todas sobre o vidro, não sobre a janela: a janela leva
    /// `shadowMargin` de folga transparente de cada lado, e alinhar por ela
    /// deixaria o painel visivelmente descentrado e afastado da barra.
    private func position(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let inset = Metrics.shadowMargin
        let screenEdge: CGFloat = 8
        let gapBelowMenuBar: CGFloat = 6

        // O vidro fica centrado na janela, logo centrar a janela centra o vidro.
        var x = anchor.midX - size.width / 2
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(
                max(x, visible.minX + screenEdge - inset),
                visible.maxX - size.width + inset - screenEdge
            )
        }
        // Topo do vidro = topo da janela menos a folga.
        let y = anchor.minY - gapBelowMenuBar - size.height + inset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Descarte

    /// O painel fecha ao clicar fora. O monitor local ignora cliques no
    /// próprio painel e no botão da barra: este já alterna sozinho, e fechá-lo
    /// aqui faria o clique reabrir o painel logo a seguir.
    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel, event.window !== self.statusButton?.window {
                self.hide()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        [localMonitor, globalMonitor].forEach { monitor in
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    // MARK: Ações

    @objc private func toggleDetails() {
        let showing = disclosure.state == .on
        updateDisclosureImage()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        if showing {
            // A janela cresce antes do conteúdo aparecer: revelar dentro de
            // uma janela ainda curta espremia as linhas durante a animação, e
            // só no fim a altura saltava para o lugar.
            sessionDetails.isHidden = false
            sessionDetails.alphaValue = 0
            resize()
            if let statusButton {
                position(relativeTo: statusButton)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sessionDetails.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sessionDetails.animator().isHidden = true
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.sessionDetails.alphaValue = 1
                self.resize()
                if let statusButton = self.statusButton {
                    self.position(relativeTo: statusButton)
                }
            }
        }
    }

    @objc private func refresh() { onRefresh?() }
    @objc private func copy() { onCopy?() }

    @objc private func history() {
        hide()
        onHistory?()
    }

    @objc private func settings() {
        hide()
        onSettings?()
    }

    @objc private func about() {
        hide()
        onAbout?()
    }

    @objc private func reconfigure() { onReconfigure?() }
    @objc private func dataFolder() { onDataFolder?() }
    @objc private func quitApp() { onQuit?() }

    @objc private func showOverflow() {
        overflowMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: overflowButton.bounds.maxY + 4),
            in: overflowButton
        )
    }
}
