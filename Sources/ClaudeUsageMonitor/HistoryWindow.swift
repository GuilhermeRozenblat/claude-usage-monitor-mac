import AppKit
import UniformTypeIdentifiers

private final class ChartLegendSwatch: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// Para onde foi o consumo do período, repartido por modelo.
///
/// Só aparece com dois ou mais modelos. Com um só, a barra seria uma faixa
/// cheia de uma cor, que num ecrã de limites se lê como "100% usado", e a
/// legenda repetiria o modelo que os detalhes da sessão já mostram.
final class ModelSplitView: NSView {
    private let bar = ModelSplitBar()
    private let rows = NSStackView()
    private let caption = NSTextField(labelWithString: L10n.modelSplitTitle)

    /// Quatro é o número de tons que a paleta separa (ver `Palette.modelShare`),
    /// e também o que cabe sem esmagar o gráfico acima.
    private static let maximumSegments = 4

    private lazy var collapsed = heightAnchor.constraint(equalToConstant: 0)

    init() {
        super.init(frame: .zero)

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4

        let stack = NSStackView(views: [caption, bar, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(8, after: bar)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Alta o suficiente para o nome caber lá dentro; as barras de cada
            // modelo continuam finas, que é o peso certo para uma lista.
            bar.heightAnchor.constraint(equalToConstant: 18),
            bar.widthAnchor.constraint(equalTo: widthAnchor),
            rows.widthAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(_ shares: [ModelUsage.Share]) {
        let shares = Self.capped(shares)
        // Limpa antes de decidir esconder. Esta view é presa por constraints e
        // não vive numa stack, então `isHidden` não a encolhe: escondida, ela
        // continuava a ocupar a altura das linhas da renderização anterior, e
        // com um modelo só (o caso comum) o gráfico perdia ~46 pt para um vão
        // permanente que ninguém via de onde vinha.
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        isHidden = shares.count < 2
        collapsed.isActive = isHidden
        guard !isHidden else { return }

        bar.shares = shares
        bar.showsLabels = true
        bar.needsDisplay = true
        for (index, share) in shares.enumerated() {
            let row = ModelShareRowView(share: share, rank: index, percentage: Self.percentage(share.fraction))
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(
            "\(L10n.modelSplitTitle): " + shares
                .map { "\($0.model) \(Self.percentage($0.fraction))" }
                .joined(separator: ", ")
        )
    }

    /// A cauda vira uma fatia só: cinco modelos rebentavam a legenda, e a
    /// quinta fatia seria fina demais para se ver na barra.
    private static func capped(_ shares: [ModelUsage.Share]) -> [ModelUsage.Share] {
        guard shares.count > maximumSegments else { return shares }
        let rest = shares.dropFirst(maximumSegments - 1).reduce(0) { $0 + $1.fraction }
        return Array(shares.prefix(maximumSegments - 1))
            + [ModelUsage.Share(model: L10n.otherModels, fraction: rest)]
    }

    /// Percentagem inteira: a barra já mostra a proporção exata, e "33,4%" ao
    /// lado de um nome de modelo é precisão que ninguém pediu.
    private static func percentage(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

}

/// Uma linha por modelo: nome, a sua fatia como barra própria, e a percentagem.
///
/// A barra combinada acima compara os modelos entre si; estas comparam cada um
/// com o período inteiro, que é a leitura que a fatia de uma barra empilhada
/// não dá quando é estreita. A barra é também a amostra de cor da linha: um
/// quadradinho ao lado dela seria a mesma cor duas vezes.
private final class ModelShareRowView: NSView {
    private let bar = ModelSplitBar()

    init(share: ModelUsage.Share, rank: Int, percentage: String) {
        super.init(frame: .zero)

        let name = NSTextField(labelWithString: share.model)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bar.shares = [share]
        bar.rank = rank

        let value = NSTextField(labelWithString: percentage)
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        value.textColor = .secondaryLabelColor
        value.alignment = .right

        let row = NSStackView(views: [name, bar, value])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Colunas fixas para os nomes e as percentagens alinharem entre
            // linhas: sem isto cada linha assenta na sua largura e as barras
            // começam em sítios diferentes.
            name.widthAnchor.constraint(equalToConstant: 170),
            value.widthAnchor.constraint(equalToConstant: 34),
            bar.heightAnchor.constraint(equalToConstant: 6),
        ])
        setAccessibilityLabel("\(share.model) \(percentage)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class ModelSplitBar: NSView {
    var shares: [ModelUsage.Share] = []
    /// Onde as cores começam. Numa linha de um modelo só, a fatia mantém o tom
    /// do lugar que ocupa na barra combinada.
    var rank = 0
    /// Escreve o nome do modelo dentro da fatia. Só a barra combinada o faz: as
    /// linhas de cada modelo já têm o nome ao lado.
    var showsLabels = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.separatorColor.setFill()
        track.fill()

        // As fatias são recortadas pela pista: assim as pontas ficam
        // arredondadas e as junções no meio ficam retas, sem desenhar cada
        // segmento com um raio diferente.
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        var x = bounds.minX
        for (index, share) in shares.enumerated() {
            let width = bounds.width * CGFloat(share.fraction)
            let color = Palette.modelShare(rank: rank + index)
            color.setFill()
            NSBezierPath(rect: NSRect(x: x, y: bounds.minY, width: width, height: bounds.height)).fill()
            if showsLabels {
                drawLabel(share.model, in: NSRect(x: x, y: bounds.minY, width: width, height: bounds.height), on: color)
            }
            x += width

            // Um fio do fundo entre fatias vizinhas. Tons da mesma família
            // separam-se por luminosidade, e dois degraus seguidos encostados
            // leem-se como uma mancha só; o corte diz onde uma acaba.
            if index < shares.count - 1 {
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(rect: NSRect(x: x - 0.75, y: bounds.minY, width: 1.5, height: bounds.height)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// O nome centrado na sua fatia, e só quando lá cabe inteiro.
    ///
    /// Nada de reticências: uma fatia estreita renderia "Op…", que não nomeia
    /// nada e ainda suja a barra. O nome completo está na linha do modelo logo
    /// abaixo, então aqui ele é um atalho, não a única via.
    private func drawLabel(_ model: String, in slice: NSRect, on background: NSColor) {
        let label = NSAttributedString(
            string: model,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: Palette.ink(on: background),
            ]
        )
        let size = label.size()
        guard size.width + 12 <= slice.width else { return }
        label.draw(at: NSPoint(
            x: slice.midX - size.width / 2,
            y: slice.midY - size.height / 2
        ))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

enum HistoryRange: Int, CaseIterable {
    /// A janela de 5 h corrente, não as últimas 5 h. Ver `ChartSpan`.
    case window
    case day
    case week
    case month
    case quarter

    var seconds: TimeInterval {
        switch self {
        case .window: 5 * 3600
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        case .quarter: 90 * 24 * 3600
        }
    }

    var title: String {
        switch self {
        case .window: L10n.rangeCurrentWindow
        case .day: L10n.range24h
        case .week: L10n.range7d
        case .month: L10n.range30d
        case .quarter: L10n.range90d
        }
    }

    var tickFormat: String {
        self == .day || self == .window ? L10n.clockFormat : L10n.shortDateTimeFormat
    }
}

/// O intervalo que o eixo X cobre.
///
/// A janela de 5 h é ancorada no reset que o Claude Code informa, não em
/// "agora": ela vai de `resets_at − 5h` até `resets_at`. Uma janela rolante de
/// "últimas 5 h" atravessaria o reset e desenharia um penhasco de 90% para 0%
/// que parece queda de uso e não é. É o mesmo artefato que o PaceEstimator já
/// descarta para não corromper a projeção de ritmo.
struct ChartSpan: Equatable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }

    /// Sem reset conhecido não há janela ativa, e o gráfico recua para o
    /// intervalo rolante, que nesse caso não cruza reset nenhum.
    static func resolve(range: HistoryRange, resetAt: TimeInterval?, now: Date) -> ChartSpan {
        let current = now.timeIntervalSince1970
        if range == .window, let resetAt, resetAt.isFinite, resetAt > current {
            return ChartSpan(start: resetAt - range.seconds, end: resetAt)
        }
        return ChartSpan(start: current - range.seconds, end: current)
    }
}

final class HistoryWindowController: NSWindowController {
    private let store: HistoryStore
    private let chart = HistoryChartView()
    private let rangeControl = NSSegmentedControl(
        labels: HistoryRange.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let statsField = NSTextField(labelWithString: "")
    private let modelSplit = ModelSplitView()
    private var range: HistoryRange = .day
    /// O reset da janela de 5 h, alimentado pelo MenuBarApp a cada reload: é o
    /// que ancora o eixo do range `.window`.
    private var fiveHourResetAt: TimeInterval?
    /// Escondida nos planos que não reportam limite semanal: uma legenda para
    /// uma série que nunca é traçada só faz procurar uma linha que não existe.
    private var sevenDayLegend = NSView()

    init(store: HistoryStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.historyWindowTitle
        window.minSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        rangeControl.selectedSegment = range.rawValue
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged)

        sevenDayLegend = legendEntry(color: Palette.sevenDay, label: L10n.sevenDayMeterTitle)
        let legend = NSStackView(views: [
            legendEntry(color: Palette.claude, label: L10n.fiveHourMeterTitle),
            sevenDayLegend,
        ])
        legend.orientation = .horizontal
        legend.spacing = 14

        statsField.font = .systemFont(ofSize: 11)
        statsField.textColor = .secondaryLabelColor

        let exportButton = NSButton(
            title: L10n.exportHistory,
            target: self,
            action: #selector(exportHistory)
        )
        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .small
        exportButton.font = .systemFont(ofSize: 11)

        [rangeControl, legend, chart, modelSplit, statsField, exportButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            rangeControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rangeControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            legend.centerYAnchor.constraint(equalTo: rangeControl.centerYAnchor),
            legend.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            chart.topAnchor.constraint(equalTo: rangeControl.bottomAnchor, constant: 10),
            chart.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            chart.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            chart.bottomAnchor.constraint(equalTo: modelSplit.topAnchor, constant: -10),
            modelSplit.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            modelSplit.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            modelSplit.bottomAnchor.constraint(equalTo: statsField.topAnchor, constant: -10),
            statsField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statsField.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            exportButton.centerYAnchor.constraint(equalTo: statsField.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            statsField.trailingAnchor.constraint(
                lessThanOrEqualTo: exportButton.leadingAnchor,
                constant: -12
            ),
        ])
    }

    @objc private func exportHistory() {
        let samples = store.load(range: HistoryStore.retention)
        guard !samples.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L10n.nothingToExport
            alert.alertStyle = .informational
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(L10n.exportFileName).csv"
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let formatter = ISO8601DateFormatter()
            var csv = "timestamp,five_hour_pct,seven_day_pct,session_cost_usd\n"
            csv.reserveCapacity(samples.count * 64)
            for sample in samples {
                csv.append([
                    formatter.string(from: sample.date),
                    sample.h5.map { String($0) } ?? "",
                    sample.d7.map { String($0) } ?? "",
                    sample.c.map { String($0) } ?? "",
                ].joined(separator: ","))
                csv.append("\n")
            }
            do {
                try Data(csv.utf8).write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = L10n.couldNotExportHistory
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func legendEntry(color: NSColor, label: String) -> NSView {
        let swatch = ChartLegendSwatch(color: color)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 3).isActive = true

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 11)
        text.textColor = .secondaryLabelColor

        let row = NSStackView(views: [swatch, text])
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        return row
    }

    func present(fiveHourResetAt: TimeInterval? = nil) {
        self.fiveHourResetAt = fiveHourResetAt
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible(fiveHourResetAt: TimeInterval? = nil) {
        self.fiveHourResetAt = fiveHourResetAt
        guard window?.isVisible == true else { return }
        refresh()
    }

    private func refresh(now: Date = Date()) {
        let span = ChartSpan.resolve(range: range, resetAt: fiveHourResetAt, now: now)
        // Recortado ao eixo, e não só carregado: o intervalo de carga cobre a
        // janela de 5 h mas começa antes dela (a carga vai de `agora − 5h` e a
        // janela começa em `reset − 5h`, que é depois). As amostras nesse
        // pedaço são da janela ANTERIOR: sem recorte, o `xPosition` grampeava-as
        // todas em cima do eixo Y (uma cerca vertical de 0 a 98% colada ao
        // 0%) e o rodapé anunciava o pico delas ("Pico: 5 h 97,5%") como se
        // fosse o da janela em curso, que ia em 20%.
        let raw = store.load(range: range.seconds, now: now)
            .filter { $0.t >= span.start && $0.t <= span.end }
        let samples = HistoryStore.downsample(raw, limit: 500)
        chart.show(samples: samples, range: range, span: span, now: now)
        // A repartição sai das amostras cruas: o downsample fica com o pico de
        // cada balde e descarta os degraus de onde a atribuição por modelo vem.
        modelSplit.show(ModelUsage.split(raw))

        // O limite semanal não existe em todo plano, e cada janela pode faltar
        // por si só. A legenda e o rodapé seguem o que o payload de facto traz.
        let peak5 = samples.compactMap(\.h5).max()
        let peak7 = samples.compactMap(\.d7).max()
        sevenDayLegend.isHidden = peak7 == nil

        var parts: [String] = []
        if let peak5 {
            parts.append(L10n.peakFiveHour("\(UsageFormatter.percentage(peak5))%"))
        }
        if let peak7 {
            parts.append(L10n.peakSevenDay("\(UsageFormatter.percentage(peak7))%"))
        }
        statsField.stringValue = parts.isEmpty ? "" : L10n.historyPeak(parts)
    }

    @objc private func rangeChanged() {
        range = HistoryRange(rawValue: rangeControl.selectedSegment) ?? .day
        refresh()
    }
}

final class HistoryChartView: NSView {
    private var samples: [HistorySample] = []
    private var range: HistoryRange = .day
    private var now = Date()
    private var span = ChartSpan(start: 0, end: 1)
    private var hoverLocation: NSPoint?
    private var trackingArea: NSTrackingArea?

    private let insets = NSEdgeInsets(top: 26, left: 40, bottom: 22, right: 12)

    func show(samples: [HistorySample], range: HistoryRange, span: ChartSpan, now: Date) {
        self.samples = samples
        self.range = range
        self.span = span
        self.now = now
        hoverLocation = nil
        needsDisplay = true
        updateAccessibility()
    }

    /// O gráfico é desenhado à mão: sem isto o VoiceOver não anuncia nada além
    /// da janela. Resume a série no lugar do traçado.
    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        guard samples.count > 1 else {
            let empty = range == .window ? L10n.noUsageInWindow : L10n.noHistoryYet
            setAccessibilityLabel("\(L10n.historyWindowTitle). \(empty)")
            return
        }
        // Mesma regra do rodapé: só se anuncia o limite que o plano informa.
        var parts: [String] = []
        if let peak5 = samples.compactMap(\.h5).max() {
            parts.append(L10n.peakFiveHour("\(UsageFormatter.percentage(peak5))%"))
        }
        if let peak7 = samples.compactMap(\.d7).max() {
            parts.append(L10n.peakSevenDay("\(UsageFormatter.percentage(peak7))%"))
        }
        let peaks = parts.isEmpty ? "" : L10n.historyPeak(parts)
        setAccessibilityLabel("\(L10n.historyWindowTitle), \(range.title). \(peaks)")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        hoverLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverLocation = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let plot = bounds.insetBy(insets)
        guard plot.width > 40, plot.height > 40 else { return }

        drawGrid(in: plot)

        guard samples.count > 1 else {
            drawEmptyState()
            return
        }

        drawSeries(values: samples.map(\.d7), color: Palette.sevenDay, in: plot)
        drawSeries(values: samples.map(\.h5), color: Palette.claude, in: plot)
        drawTimeTicks(in: plot)
        drawNowMarker(in: plot)
        drawHover(in: plot)
    }

    /// Na janela de 5 h o eixo termina no reset, que está no futuro: sem esta
    /// marca não se sabe onde acaba o traçado e começa o que ainda falta.
    private func drawNowMarker(in plot: NSRect) {
        let current = now.timeIntervalSince1970
        guard range == .window, current > span.start, current < span.end else { return }

        let x = xPosition(current, in: plot)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: plot.minY))
        line.line(to: NSPoint(x: x, y: plot.maxY))
        line.lineWidth = 1
        line.setLineDash([2, 3], count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        line.stroke()

        let label = NSAttributedString(
            string: L10n.chartNowMarker,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        // Dentro do gráfico, encostado ao topo e ao lado da linha. A faixa acima
        // do gráfico já é da nota do eixo e da leitura do cursor: com a janela
        // recém-começada a linha fica à esquerda e saía "% do limite do seu
        // planagora", uma palavra por cima da outra.
        let size = label.size()
        let fitsRight = x + 5 + size.width <= plot.maxX
        let origin = NSPoint(
            x: fitsRight ? x + 5 : x - 5 - size.width,
            y: plot.maxY - size.height - 3
        )
        label.draw(at: origin)
    }

    /// As cores são dinâmicas e resolvem-se sozinhas em `draw`, mas o AppKit
    /// não repinta views de desenho próprio quando a aparência muda.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Escalas

    private func xPosition(_ t: TimeInterval, in plot: NSRect) -> CGFloat {
        guard span.duration > 0 else { return plot.minX }
        let fraction = (t - span.start) / span.duration
        return plot.minX + plot.width * CGFloat(min(1, max(0, fraction)))
    }

    private func yPosition(_ value: Double, in plot: NSRect) -> CGFloat {
        plot.minY + plot.height * CGFloat(min(100, max(0, value)) / 100)
    }

    // MARK: Camadas

    /// O eixo é sempre 0–100% do limite do próprio plano, nunca auto-escalado
    /// aos dados. A Anthropic não publica limites absolutos, então a
    /// percentagem é a única escala que significa o mesmo em qualquer plano; e
    /// auto-escalar faria 18% de uso desenhar uma montanha. O vazio acima da
    /// linha é a folga que resta, e é informação.
    private func drawGrid(in plot: NSRect) {
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // A faixa acima do gráfico é uma linha só, e a leitura sob o cursor tem
        // prioridade sobre a nota: com o cursor à esquerda, as duas escreviam no
        // mesmo sítio, uma por cima da outra. A nota diz sempre o mesmo; a
        // leitura é o que o utilizador foi lá buscar.
        if hoverLocation == nil {
            let note = NSAttributedString(
                string: L10n.chartAxisNote,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
            note.draw(at: NSPoint(x: plot.minX, y: plot.maxY + 6))
        }

        for value in stride(from: 0.0, through: 100, by: 25) {
            let y = yPosition(value, in: plot)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            path.lineWidth = 1
            NSColor.separatorColor.setStroke()
            path.stroke()

            let text = NSAttributedString(string: "\(Int(value))%", attributes: label)
            text.draw(at: NSPoint(x: plot.minX - text.size().width - 6, y: y - text.size().height / 2))
        }

        // Referência de atenção em 90%, alinhada ao limiar crítico dos medidores.
        let y = yPosition(90, in: plot)
        let reference = NSBezierPath()
        reference.move(to: NSPoint(x: plot.minX, y: y))
        reference.line(to: NSPoint(x: plot.maxX, y: y))
        reference.lineWidth = 1
        reference.setLineDash([3, 3], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.45).setStroke()
        reference.stroke()
    }

    private func drawSeries(values: [Double?], color: NSColor, in plot: NSRect) {
        // Quebra a linha quando há um vão sem amostras (Claude Code parado):
        // interpolar sobre o vão inventaria dados que não existem.
        let maxGap = max(range.seconds / 48, 900)
        var path: NSBezierPath?
        var previousT: TimeInterval?

        for (index, sample) in samples.enumerated() {
            guard let value = values[index] else {
                path?.strokeSeries(color)
                path = nil
                previousT = nil
                continue
            }
            let point = NSPoint(x: xPosition(sample.t, in: plot), y: yPosition(value, in: plot))
            if let current = path, let previous = previousT, sample.t - previous <= maxGap {
                current.line(to: point)
            } else {
                path?.strokeSeries(color)
                path = NSBezierPath()
                path?.move(to: point)
            }
            previousT = sample.t
        }
        path?.strokeSeries(color)
    }

    private func drawTimeTicks(in plot: NSRect) {
        let (start, end) = (span.start, span.end)
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = range.tickFormat
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        for fraction in [0.0, 0.5, 1.0] {
            let t = start + (end - start) * fraction
            let text = NSAttributedString(
                string: formatter.string(from: Date(timeIntervalSince1970: t)),
                attributes: label
            )
            var x = xPosition(t, in: plot) - text.size().width * CGFloat(fraction)
            x = min(max(x, plot.minX), plot.maxX - text.size().width)
            text.draw(at: NSPoint(x: x, y: plot.minY - text.size().height - 5))
        }
    }

    private func drawHover(in plot: NSRect) {
        guard let hoverLocation, plot.insetBy(dx: -8, dy: -8).contains(hoverLocation),
              !samples.isEmpty else { return }

        let (start, end) = (span.start, span.end)
        let t = start + (end - start) * Double((hoverLocation.x - plot.minX) / plot.width)
        guard let nearest = samples.min(by: { abs($0.t - t) < abs($1.t - t) }) else { return }
        let x = xPosition(nearest.t, in: plot)

        let crosshair = NSBezierPath()
        crosshair.move(to: NSPoint(x: x, y: plot.minY))
        crosshair.line(to: NSPoint(x: x, y: plot.maxY))
        crosshair.lineWidth = 1
        NSColor.separatorColor.setStroke()
        crosshair.stroke()

        if let value = nearest.h5 {
            drawMarker(at: NSPoint(x: x, y: yPosition(value, in: plot)), color: Palette.claude)
        }
        if let value = nearest.d7 {
            drawMarker(at: NSPoint(x: x, y: yPosition(value, in: plot)), color: Palette.sevenDay)
        }

        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = range.tickFormat
        var parts = [formatter.string(from: nearest.date)]
        if let value = nearest.h5 { parts.append("5h: \(UsageFormatter.percentage(value))%") }
        if let value = nearest.d7 { parts.append("7d: \(UsageFormatter.percentage(value))%") }

        let readout = NSAttributedString(
            string: parts.joined(separator: " · "),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let size = readout.size()
        let origin = NSPoint(
            x: min(max(x - size.width / 2, plot.minX), plot.maxX - size.width),
            y: plot.maxY + 6
        )
        readout.draw(at: origin)
    }

    private func drawMarker(at point: NSPoint, color: NSColor) {
        let ringRect = NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: ringRect).fill()
        color.setFill()
        NSBezierPath(ovalIn: ringRect.insetBy(dx: 2, dy: 2)).fill()
    }

    private func drawEmptyState() {
        // Logo depois de um reset a janela está vazia mas o histórico não:
        // dizer "sem histórico" ali seria falso.
        let message = range == .window ? L10n.noUsageInWindow : L10n.noHistoryYet
        // Quebra em várias linhas: a frase inteira não cabe numa linha só na
        // largura mínima da janela, e antes era cortada nas bordas.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSAttributedString(
            string: message,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        let width = min(320, bounds.width - 32)
        let height = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).height
        text.draw(with: NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        ), options: [.usesLineFragmentOrigin])
    }
}

private extension NSBezierPath {
    func strokeSeries(_ color: NSColor) {
        lineWidth = 2
        lineJoinStyle = .round
        lineCapStyle = .round
        color.setStroke()
        stroke()
    }
}

private extension NSRect {
    func insetBy(_ insets: NSEdgeInsets) -> NSRect {
        NSRect(
            x: minX + insets.left,
            y: minY + insets.bottom,
            width: width - insets.left - insets.right,
            height: height - insets.top - insets.bottom
        )
    }
}
