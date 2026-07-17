import AppKit
import QuartzCore

/// A folha de rosto do app: ícone, nome, versão, quem o fez. A ordem é a do
/// painel Sobre do macOS, e nada mais entra sem ganhar o lugar.
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    private let heroView = AboutHeroView()
    private let stack = NSStackView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage Monitor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let glass = NSVisualEffectView(frame: window.contentLayoutRect)
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .followsWindowActiveState
        window.contentView = glass

        super.init(window: window)
        window.delegate = self
        buildContent()
        window.setContentSize(NSSize(width: 360, height: stack.fittingSize.height + 48))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Claude Usage Monitor")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center

        // Nome e versão são um par, como no painel Sobre do sistema: colados,
        // e a versão em corpo pequeno para não disputar a leitura.
        let version = NSTextField(labelWithString: "\(L10n.aboutVersion) \(Self.appVersion)")
        version.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        // Uma linha só. A antiga descrição repetia a status line e a privacidade
        // que os Ajustes já explicam no sítio onde importam.
        let tagline = NSTextField(wrappingLabelWithString: L10n.aboutTagline)
        tagline.font = .systemFont(ofSize: 13, weight: .regular)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center

        let rule = SeparatorView()
        let author = AuthorLineView()

        let closeButton = NSButton(
            title: L10n.aboutContinue,
            target: self,
            action: #selector(closeAbout)
        )
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        [heroView, title, version, tagline, rule, author, closeButton]
            .forEach(stack.addArrangedSubview)

        stack.setCustomSpacing(10, after: heroView)
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(20, after: tagline)
        stack.setCustomSpacing(20, after: author)

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            heroView.widthAnchor.constraint(equalToConstant: 132),
            heroView.heightAnchor.constraint(equalToConstant: 132),
            rule.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.5),
            tagline.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])

        content.setAccessibilityLabel(
            "Claude Usage Monitor. \(L10n.developedBy) Guilherme Rozenblat. \(L10n.madeInBrazil)."
        )
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        heroView.startAnimating()
        playEntrance()
    }

    func windowWillClose(_ notification: Notification) {
        heroView.stopAnimating()
    }

    /// Cada bloco sobe 8 pt e aparece, com 45 ms de atraso entre eles: a leitura
    /// segue a ordem do conteúdo em vez de tudo surgir de uma vez.
    private func playEntrance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let start = CACurrentMediaTime() + 0.05
        for (index, view) in stack.arrangedSubviews.enumerated() {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -8
            rise.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 0.4
            group.beginTime = start + Double(index) * 0.045
            group.fillMode = .backwards
            // Desaceleração exponencial: rápido a sair, suave a assentar.
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            layer.add(group, forKey: "entrance")
        }
    }

    @objc private func closeAbout() {
        close()
    }

    private static var appVersion: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value ?? "--"
    }
}

/// Uma linha, sem cartão: a bandeira já diz o país, e um cartão dentro de uma
/// janela é moldura sobre moldura.
private final class AuthorLineView: NSStackView {
    init() {
        super.init(frame: .zero)

        let flag = NSTextField(labelWithString: "🇧🇷")
        flag.font = .systemFont(ofSize: 17)
        flag.setAccessibilityLabel(L10n.madeInBrazil)

        let credit = NSTextField()
        credit.isEditable = false
        credit.isBordered = false
        credit.drawsBackground = false
        credit.attributedStringValue = Self.credit()

        orientation = .horizontal
        alignment = .centerY
        spacing = 7
        [flag, credit].forEach(addArrangedSubview)
        setAccessibilityLabel("\(L10n.developedBy) Guilherme Rozenblat. \(L10n.madeInBrazil).")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        (arrangedSubviews.last as? NSTextField)?.attributedStringValue = Self.credit()
    }

    /// O nome carrega o peso e a cor de texto normal; o "Desenvolvido por" fica
    /// em secundário. É uma frase, não uma etiqueta com um valor.
    private static func credit() -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\(L10n.developedBy) ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        text.append(NSAttributedString(
            string: "Guilherme Rozenblat",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        return text
    }
}

/// Anel de doze traços que acendem em sequência à volta do ícone.
///
/// Desenho original: reproduzir a marca da Anthropic num app de terceiros é
/// terreno de marca registada. A referência ao Claude fica no nome e na cor.
private final class AboutHeroView: NSView {
    private let haloLayer = CAGradientLayer()
    private let ringLayer = CALayer()
    private var tickLayers: [CALayer] = []
    private let iconView = NSImageView()

    private static let tickCount = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        haloLayer.type = .radial
        haloLayer.locations = [0, 1]
        haloLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        haloLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(haloLayer)

        layer?.addSublayer(ringLayer)
        for _ in 0 ..< Self.tickCount {
            let tick = CALayer()
            tick.cornerRadius = 1
            tickLayers.append(tick)
            ringLayer.addSublayer(tick)
        }

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.2
        iconView.layer?.shadowRadius = 12
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        iconView.setAccessibilityLabel("Claude Usage Monitor")
        addSubview(iconView)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = Palette.claude
            haloLayer.colors = [
                accent.withAlphaComponent(0.22).cgColor,
                accent.withAlphaComponent(0).cgColor,
            ]
            tickLayers.forEach { $0.backgroundColor = accent.cgColor }
            iconView.layer?.shadowOpacity = effectiveAppearance.isDark ? 0.46 : 0.20
        }
    }

    override func layout() {
        super.layout()
        haloLayer.frame = bounds.insetBy(dx: -12, dy: -12)
        ringLayer.frame = bounds

        // Os traços apontam para o centro: cada um roda sobre o próprio eixo e
        // é empurrado para o raio.
        let radius = min(bounds.width, bounds.height) / 2 - 6
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, tick) in tickLayers.enumerated() {
            let angle = CGFloat(index) / CGFloat(Self.tickCount) * .pi * 2 - .pi / 2
            tick.bounds = CGRect(x: 0, y: 0, width: 5, height: 2)
            tick.position = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            tick.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }

        iconView.frame = bounds.insetBy(dx: 26, dy: 26)
    }

    /// O atraso de cada traço é proporcional à sua posição, então a luz dá uma
    /// volta ao anel a cada 3 s. É o único movimento contínuo da janela: o halo
    /// pulsante que existia aqui competia com ele e cansava.
    func startAnimating() {
        stopAnimating()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            tickLayers.forEach { $0.opacity = 0.5 }
            return
        }

        let period: CFTimeInterval = 3
        let beginTime = CACurrentMediaTime()
        for (index, tick) in tickLayers.enumerated() {
            let sweep = CABasicAnimation(keyPath: "opacity")
            sweep.fromValue = 1
            sweep.toValue = 0.18
            sweep.duration = period
            sweep.repeatCount = .infinity
            sweep.beginTime = beginTime - period * Double(index) / Double(Self.tickCount)
            sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
            tick.add(sweep, forKey: "sweep")
        }
    }

    func stopAnimating() {
        tickLayers.forEach { $0.removeAllAnimations() }
    }
}
