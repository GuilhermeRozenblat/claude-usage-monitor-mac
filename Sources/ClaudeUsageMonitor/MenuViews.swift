import AppKit

/// Trilho do medidor. `NSLevelIndicator` existe, mas não aceita raio nem cor
/// própria, e o desenho aqui é menor que a luta contra ele.
private final class UsageProgressView: NSView {
    var value: Double = 0 {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor = Palette.claude {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 6)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = bounds
        let radius = track.height / 2
        // separatorColor já é translúcido (~0.1): sobre o vidro do painel ele
        // desaparecia. tertiaryLabelColor é o tom recessivo cheio do sistema.
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard value > 0 else { return }
        let width = max(track.height, track.width * min(100, max(0, value)) / 100)
        let fill = NSRect(x: track.minX, y: track.minY, width: width, height: track.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

enum MonitorHealth {
    case healthy
    case waiting
    case warning
    case error

    var symbolName: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .waiting: "clock.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var title: String {
        switch self {
        case .healthy: L10n.healthHealthy
        case .waiting: L10n.healthWaiting
        case .warning: L10n.healthWarning
        case .error: L10n.healthError
        }
    }

    var color: NSColor {
        switch self {
        case .healthy: .systemGreen
        case .waiting: .secondaryLabelColor
        case .warning: .systemOrange
        case .error: .systemRed
        }
    }
}

/// Cabeçalho do painel: identidade da conta e saúde do monitor.
final class MonitorHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "Claude Usage Monitor")
    private let statusField = NSTextField(labelWithString: L10n.starting)
    private var healthDetail = L10n.starting

    init() {
        super.init(frame: .zero)

        iconView.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusField.font = .systemFont(ofSize: 11, weight: .regular)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [titleField, statusField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [iconView, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setHealth(.waiting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setHealth(_ health: MonitorHealth, detail: String? = nil) {
        iconView.image = NSImage(
            systemSymbolName: health.symbolName,
            accessibilityDescription: health.title
        )
        iconView.contentTintColor = health.color
        healthDetail = detail ?? health.title
        statusField.stringValue = healthDetail
        updateAccessibilityLabel()
    }

    func setAccountTitle(_ title: String, fullTitle: String? = nil) {
        titleField.stringValue = title
        titleField.toolTip = fullTitle
        updateAccessibilityLabel(fullAccountTitle: fullTitle)
    }

    private func updateAccessibilityLabel(fullAccountTitle: String? = nil) {
        let account = fullAccountTitle ?? titleField.toolTip ?? titleField.stringValue
        setAccessibilityLabel("Claude Usage Monitor, \(account), \(healthDetail)")
    }
}

/// Sparkline das últimas 24 h e o ritmo projetado ("No ritmo atual: 100% às
/// 14:32") ou o pico do período.
final class TrendView: NSView {
    private let sparkline = SparklineView()
    private let label = NSTextField(labelWithString: L10n.collectingData)
    private var sparklineWidth: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [sparkline, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        // `.gravityAreas` centrava "Coletando dados…" no meio do painel, solto
        // entre os medidores. `.fill` + hugging baixo dá a sobra ao rótulo, que
        // alinha o texto à esquerda como as outras linhas.
        row.distribution = .fill
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        sparklineWidth = sparkline.widthAnchor.constraint(equalToConstant: 96)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            sparklineWidth,
            // 16 pt mapeando 0-100% punha um uso de 19% a 3 pt do chão, colado
            // à linha de base. Mais alto, o traçado ganha corpo sem mudar de
            // escala.
            sparkline.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// O rótulo responde "vou bater o limite?" e, quando não dá para projetar,
    /// "estou a gastar depressa?". O nível já está no medidor logo acima.
    func update(
        samples: [HistorySample],
        projectedLimit: Date?,
        ratePerHour: Double?,
        span: ChartSpan,
        now: Date
    ) {
        sparkline.show(samples: samples, span: span)

        // Sem série, o rótulo recua para a margem em vez de flutuar ao lado de
        // um espaço vazio.
        sparkline.isHidden = !sparkline.hasSeries
        sparklineWidth.constant = sparkline.hasSeries ? 96 : 0

        if let projectedLimit {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateFormat = L10n.clockFormat
            label.stringValue = L10n.paceProjection(formatter.string(from: projectedLimit))
            label.textColor = .labelColor
        } else if let ratePerHour, ratePerHour >= 0.5 {
            label.stringValue = L10n.paceRate(UsageFormatter.percentage(ratePerHour))
            label.textColor = .secondaryLabelColor
        } else if ratePerHour != nil {
            // Mediu-se o ritmo e ele é ~zero: não está a consumir agora.
            label.stringValue = L10n.noRecentUsage
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = L10n.collectingData
            label.textColor = .secondaryLabelColor
        }
        setAccessibilityLabel(label.stringValue)
    }
}

private final class SparklineView: NSView {
    private var samples: [HistorySample] = []
    private var span = ChartSpan(start: 0, end: 1)

    func show(samples: [HistorySample], span: ChartSpan) {
        self.samples = samples
        self.span = span
        needsDisplay = true
    }

    /// Sem série não há eixo: a linha de base sozinha lia-se como um risco
    /// solto no painel, não como um gráfico vazio.
    var hasSeries: Bool {
        samples.filter { $0.h5 != nil }.count > 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hasSeries else { return }

        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 0, y: 0.5))
        baseline.line(to: NSPoint(x: bounds.maxX, y: 0.5))
        baseline.lineWidth = 1
        NSColor.separatorColor.setStroke()
        baseline.stroke()
        guard span.duration > 0 else { return }

        // O teto do eixo acompanha os dados, ao contrário do gráfico grande.
        //
        // O sparkline não tem eixo rotulado: o nível já está no medidor logo
        // acima e na barra dele. O que este gráfico tem para dar é a forma, e
        // 0-100% fixos em 26 pt punham um uso de 22% num fio de 5 pt colado ao
        // chão, onde não se distingue forma nenhuma. O piso de 25% impede que
        // um consumo irrelevante vire montanha.
        let peak = samples.compactMap(\.h5).max() ?? 0
        let ceiling = min(100, max(25, peak * 1.25))
        // A janela de 5 h é curta: um vão de 30 min já é uma pausa real, e
        // interpolar por cima dele inventaria uso que não houve.
        let maxGap = 600.0

        var path: NSBezierPath?
        var segment: [NSPoint] = []
        var previousT: TimeInterval?
        for sample in samples {
            guard let value = sample.h5 else { continue }
            let x = bounds.width * CGFloat(min(1, max(0, (sample.t - span.start) / span.duration)))
            let y = 1 + (bounds.height - 2) * CGFloat(min(ceiling, max(0, value)) / ceiling)
            let point = NSPoint(x: x, y: y)
            if let current = path, let previous = previousT, sample.t - previous <= maxGap {
                current.line(to: point)
                segment.append(point)
            } else {
                strokeSegment(path, points: segment)
                path = NSBezierPath()
                path?.move(to: point)
                segment = [point]
            }
            previousT = sample.t
        }
        strokeSegment(path, points: segment)
    }

    /// Traço mais a área por baixo dele.
    ///
    /// A escala continua 0-100% do limite, como o medidor logo acima: o nível
    /// tem de ler-se igual nos dois. Uma linha de 1,5 pt a 19% quase desaparece
    /// contra o vidro; a área preenchida dá-lhe corpo sem exagerar o valor.
    private func strokeSegment(_ path: NSBezierPath?, points: [NSPoint]) {
        guard let path, let first = points.first, let last = points.last else { return }

        let area = path.copy() as! NSBezierPath
        area.line(to: NSPoint(x: last.x, y: 0))
        area.line(to: NSPoint(x: first.x, y: 0))
        area.close()
        Palette.claude.withAlphaComponent(0.22).setFill()
        area.fill()

        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        Palette.claude.setStroke()
        path.stroke()
    }
}

/// Um medidor: título, valor, trilho e detalhe.
final class UsageMeterView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "--")
    private let progress = UsageProgressView()
    private let detailField = NSTextField(labelWithString: L10n.waitingForData)

    init(title: String) {
        super.init(frame: .zero)

        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .labelColor
        titleField.stringValue = title

        valueField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueField.textColor = .labelColor
        valueField.alignment = .right
        valueField.lineBreakMode = .byTruncatingHead
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailField.font = .systemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let head = NSStackView(views: [titleField, valueField])
        head.orientation = .horizontal
        head.distribution = .fill
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let column = NSStackView(views: [head, progress, detailField])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            head.widthAnchor.constraint(equalTo: column.widthAnchor),
            progress.widthAnchor.constraint(equalTo: column.widthAnchor),
            detailField.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        percentage: Double?,
        value: String,
        detail: String,
        isAvailable: Bool = true
    ) {
        valueField.stringValue = value
        detailField.stringValue = detail
        progress.value = min(100, max(0, percentage ?? 0))
        progress.fillColor = Palette.meter(for: percentage)
        progress.alphaValue = isAvailable ? 1 : 0.28
        valueField.textColor = isAvailable ? .labelColor : .secondaryLabelColor
        setAccessibilityLabel("\(titleField.stringValue), \(value), \(detail)")
    }

    func setTitle(_ title: String) {
        titleField.stringValue = title
    }

    /// Nota sobre o que o número significa (e o que ele não cobre).
    func setValueTooltip(_ text: String) {
        titleField.toolTip = text
        valueField.toolTip = text
    }
}
