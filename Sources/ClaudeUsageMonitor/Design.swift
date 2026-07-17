import AppKit

/// Paleta e materiais. Os hexadecimais viviam duplicados em MenuViews e
/// HistoryWindow; aqui existem uma vez só.
enum Palette {
    /// O laranja da marca Claude. Só em preenchimentos e traços, onde o piso
    /// de contraste é 3:1 e não 4.5:1.
    static let claude = NSColor(name: "ClaudeOrange") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0xEF / 255, green: 0x8E / 255, blue: 0x6D / 255, alpha: 1)
            : NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    }

    /// Variante para texto: escurece no modo claro e clareia no escuro até
    /// passar 4.5:1 contra as superfícies do sistema.
    static let claudeText = NSColor(name: "ClaudeAccentText") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0xFF / 255, green: 0xAA / 255, blue: 0x89 / 255, alpha: 1)
            : NSColor(srgbRed: 0x9E / 255, green: 0x3F / 255, blue: 0x27 / 255, alpha: 1)
    }

    /// Série de 7 dias no histórico. Azul contra o laranja: o par sobrevive a
    /// deuteranopia e protanopia, que achatam laranja/verde.
    static let sevenDay = NSColor(name: "SevenDayBlue") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0x71 / 255, green: 0xAD / 255, blue: 0xE3 / 255, alpha: 1)
            : NSColor(srgbRed: 0x32 / 255, green: 0x68 / 255, blue: 0xA0 / 255, alpha: 1)
    }

    /// Tons para repartir consumo por modelo, do maior para o menor.
    ///
    /// Cores opacas, não a marca com alpha: transparência mistura-se com o que
    /// está por baixo, e o tom mais fraco acabava a 1.5:1 contra o fundo, que
    /// é invisível.
    ///
    /// Separam-se por luminosidade e não por matiz. Sob deuteranopia (a mais
    /// comum) o eixo vermelho-verde desaparece e um laranja ao lado de um âmbar
    /// viram a mesma cor; a diferença de luminosidade sobrevive a qualquer
    /// daltonismo. Cada tom mede ≥3:1 contra o fundo da janela, o piso para um
    /// elemento gráfico que carrega informação (ver ModelShareContrastTests).
    ///
    /// São três degraus quentes e não mais: o quarto já não alcança os 3:1 em
    /// nenhum dos modos. Daí o neutro no fim, que é também o que "os outros"
    /// quer dizer.
    ///
    /// Os degraus ocupam toda a faixa de luminosidade que o fundo permite, e a
    /// matiz deriva por cima disso (o tom claro puxa ao amarelo, o escuro ao
    /// vermelho). A deriva soma separação para quem vê as cores todas sem tirar
    /// nada a quem não vê: no eixo amarelo-azul, que a deuteranopia preserva.
    static func modelShare(rank: Int) -> NSColor {
        NSColor(name: "ModelShare\(min(rank, 3))") { appearance in
            let ramp = appearance.isDark
                ? [(0xFF, 0xC6, 0x92), (0xE1, 0x79, 0x5C), (0xA6, 0x51, 0x48), (0x8E, 0x8E, 0x93)]
                : [(0xCC, 0x6C, 0x3E), (0x9D, 0x37, 0x2B), (0x56, 0x1E, 0x1A), (0x6E, 0x6E, 0x73)]
            let (red, green, blue) = ramp[min(rank, ramp.count - 1)]
            return NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
    }

    /// Preto ou branco, o que for legível sobre `background`.
    ///
    /// Escolhido pela luminância medida e não fixado numa das duas: a rampa dos
    /// modelos atravessa toda a faixa de luminosidade, então nenhuma tinta
    /// única serve para os dois extremos. Ver `ModelShareContrastTests`.
    static func ink(on background: NSColor) -> NSColor {
        guard let color = background.usingColorSpace(.sRGB) else { return .white }
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
        let onWhite = 1.05 / (luminance + 0.05)
        let onBlack = (luminance + 0.05) / 0.05
        return onBlack >= onWhite ? .black : .white
    }

    /// Cor do medidor por severidade. Abaixo de 75% a marca; acima, o
    /// vocabulário semântico do sistema.
    static func meter(for percentage: Double?) -> NSColor {
        guard let percentage else { return .tertiaryLabelColor }
        if percentage >= 90 { return .systemRed }
        if percentage >= 75 { return .systemOrange }
        return claude
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Escala de espaçamento do painel. Um único passo de 4 pt mantém o ritmo
/// vertical previsível sem inventar valores por view.
enum Metrics {
    static let panelWidth: CGFloat = 340
    static let gutter: CGFloat = 16
    static let cornerRadius: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    /// Folga transparente à volta do vidro para a sombra caber. A janela é
    /// maior que o painel visível por esta margem de cada lado.
    static let shadowMargin: CGFloat = 20
}

/// Superfície de vidro do sistema. Liquid Glass real no macOS 26; nas versões
/// anteriores, o material de vibrância mais próximo. O chamador só vê uma view
/// que embrulha conteúdo; a escolha do material não vaza.
enum Glass {
    /// Envolve `content` numa superfície de vidro arredondada.
    ///
    /// O vidro vai dentro de um container com máscara em vez de ir direto para
    /// a janela. O NSGlassEffectView é composto na GPU e não escreve o alpha
    /// dos cantos no backing da janela, então o macOS media a janela como um
    /// retângulo cheio e desenhava a sombra quadrada à volta do vidro
    /// arredondado. A máscara do container recorta o alpha de facto.
    static func wrap(_ content: NSView, cornerRadius: CGFloat = Metrics.cornerRadius) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false

        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.contentView = content
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            ])
            surface = effect
        }

        surface.translatesAutoresizingMaskIntoConstraints = false
        let container = MaskedContainerView(cornerRadius: cornerRadius)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    /// Superfície completa do painel: vidro arredondado mais a sombra.
    ///
    /// A sombra é desenhada por nós porque a da janela não serve: o macOS
    /// deriva-a do alpha do backing, o vidro não escreve lá os cantos, e o
    /// resultado era uma sombra quadrada à volta de um painel arredondado.
    /// Com `hasShadow = false` e um shadowPath explícito, o formato é nosso.
    static func panelSurface(_ content: NSView) -> NSView {
        let glass = wrap(content)
        let host = ShadowHostView(cornerRadius: Metrics.cornerRadius, margin: Metrics.shadowMargin)
        host.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: host.topAnchor, constant: Metrics.shadowMargin),
            glass.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -Metrics.shadowMargin),
            glass.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: Metrics.shadowMargin),
            glass.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -Metrics.shadowMargin),
        ])
        return host
    }
}

/// Recorta o conteúdo num retângulo de cantos contínuos (o "squircle" que o
/// macOS usa em toda a parte; `.circular` deixa o canto com cara de raio de
/// CSS, não de janela do sistema).
private final class MaskedContainerView: NSView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

/// View transparente que só existe para projetar a sombra do painel. O
/// `shadowPath` acompanha o retângulo do vidro, então a sombra é arredondada
/// mesmo sem o layer ter conteúdo próprio.
private final class ShadowHostView: NSView {
    private let cornerRadius: CGFloat
    private let margin: CGFloat

    init(cornerRadius: CGFloat, margin: CGFloat) {
        self.cornerRadius = cornerRadius
        self.margin = margin
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: margin, dy: margin)
        layer?.shadowPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}
