import AppKit

/// Um NSMenu dimensiona-se pelo item mais largo e desenha a própria moldura,
/// então não aceita vidro nem acompanha views de largura fixa. É por isso que
/// os extras da barra da Apple (Wi-Fi, Som, Central de Controlo) são painéis.
final class MonitorPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Esc fecha o painel, como em qualquer popover do sistema.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Uma linha de estado: símbolo + texto secundário.
final class StatusRowView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// O texto completo vive no tooltip quando a linha trunca, no lugar da
    /// aritmética de fontes que o menu exigia.
    func update(symbol: String, text: String, tint: NSColor = .secondaryLabelColor) {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = tint
        label.stringValue = text
        toolTip = text
        setAccessibilityLabel(text)
    }
}

/// Grade de detalhes da sessão, revelada por um disclosure. Era um submenu de
/// oito itens; aqui é conteúdo, não navegação.
final class SessionDetailsView: NSView {
    /// Ordem das linhas; `update` recebe os valores nesta mesma ordem.
    private static let labels: [() -> String] = [
        { L10n.model },
        { L10n.project },
        { L10n.session },
        { L10n.effort },
        { L10n.duration },
        { L10n.sessionCostLabel },
        { L10n.accumulatedCostLabel },
        { L10n.claudeCodeVersionLabel },
    ]
    private static let costRow = 5

    private let grid: NSGridView
    private var labelFields: [NSTextField] = []
    private var valueFields: [NSTextField] = []

    init() {
        grid = NSGridView(numberOfColumns: 2, rows: 0)
        super.init(frame: .zero)

        for label in Self.labels {
            let name = NSTextField(labelWithString: label())
            name.font = .systemFont(ofSize: 11, weight: .regular)
            name.textColor = .secondaryLabelColor
            name.setContentHuggingPriority(.required, for: .horizontal)
            name.setContentCompressionResistancePriority(.required, for: .horizontal)

            let value = NSTextField(labelWithString: "--")
            value.font = .systemFont(ofSize: 11, weight: .medium)
            value.textColor = .labelColor
            value.alignment = .right
            value.lineBreakMode = .byTruncatingHead
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            labelFields.append(name)
            valueFields.append(value)
            grid.addRow(with: [name, value])
        }

        grid.rowSpacing = 4
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func applyLocalizedTitles() {
        for (index, label) in Self.labels.enumerated() {
            labelFields[index].stringValue = label()
        }
        costTooltip(L10n.costTooltip)
    }

    func update(_ values: [String]) {
        for (index, value) in values.enumerated() where index < valueFields.count {
            valueFields[index].stringValue = value
            valueFields[index].toolTip = value
        }
        setAccessibilityLabel(
            zip(labelFields, valueFields)
                .map { "\($0.stringValue): \($1.stringValue)" }
                .joined(separator: ", ")
        )
    }

    /// O aviso de que o custo não reflete Pro/Max pertence ao número, não à
    /// grade inteira.
    func costTooltip(_ text: String) {
        valueFields[Self.costRow].toolTip = text
        labelFields[Self.costRow].toolTip = text
    }
}

/// A verificação concreta a fazer quando sobra algo para o utilizador.
///
/// Fica escondida enquanto está tudo bem, e o que o app conserta sozinho nunca
/// chega aqui: a linha existir já significa que há uma ação a tomar.
final class RemedyRowView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        iconView.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = .systemOrange
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// `nil` esconde a linha: não há nada a fazer.
    func show(_ text: String?) {
        guard let text else {
            isHidden = true
            return
        }
        label.stringValue = text
        label.preferredMaxLayoutWidth = Metrics.panelWidth - Metrics.gutter * 2 - 20
        setAccessibilityLabel(text)
        isHidden = false
    }
}

/// Separador de 1 px alinhado ao vocabulário do sistema.
final class SeparatorView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}
