import Foundation

struct UsageWindow: Equatable {
    let usedPercentage: Double
    let resetsAt: TimeInterval?
}

struct RateLimits: Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    var hasValues: Bool {
        fiveHour != nil || sevenDay != nil
    }
}

struct SessionSnapshot: Codable, Equatable {
    /// Os valores que o `state.json` traz batem com o que o payload permitiria.
    ///
    /// O payload é validado ao entrar, mas o cache era decodificado em bruto e
    /// alimenta o mesmo formatador: um `contextUsedPercentage` absurdo derruba
    /// o app ao virar texto, tal como derrubava pelas janelas de 5 h e 7 dias.
    var isPlausible: Bool {
        let percentages = [contextUsedPercentage, contextRemainingPercentage].compactMap { $0 }
        guard percentages.allSatisfy({ $0.isFinite && (0 ... 100).contains($0) }) else { return false }
        let counts = [contextWindowSize, contextInputTokens, contextOutputTokens, totalDurationMS]
            .compactMap { $0 }
        guard counts.allSatisfy({ $0 >= 0 }) else { return false }
        if let cost = estimatedCostUSD, !cost.isFinite || cost < 0 { return false }
        return true
    }

    var modelDisplayName: String?
    var contextUsedPercentage: Double?
    var contextRemainingPercentage: Double?
    var contextWindowSize: Int?
    var contextInputTokens: Int?
    var contextOutputTokens: Int?
    var sessionName: String?
    var projectName: String?
    var claudeCodeVersion: String?
    var effortLevel: String?
    var thinkingEnabled: Bool?
    var estimatedCostUSD: Double?
    var totalDurationMS: Int?
}

struct UsageState: Codable, Equatable {
    var fiveHourUsage: Double?
    var fiveHourResetAt: TimeInterval?
    var sevenDayUsage: Double?
    var sevenDayResetAt: TimeInterval?
    var notifiedThresholds: [Int]
    var sevenDayNotifiedThresholds: [Int]
    var usageUpdatedAt: String?
    /// Quando cada janela veio num payload, separadamente.
    ///
    /// A doc do Claude Code diz que `five_hour` e `seven_day` podem faltar
    /// independentemente. Com um carimbo só para as duas, um payload que
    /// trouxesse apenas uma delas renovava o carimbo e a outra ficava
    /// congelada, apresentada como fresca: o app dizia "dados atualizados"
    /// sobre um número velho, e no caso da janela de 5 h esse número está na
    /// barra de menus.
    var fiveHourUpdatedAt: String?
    var sevenDayUpdatedAt: String?
    var lastIngestErrorAt: String?
    var session: SessionSnapshot?
    var sessionUpdatedAt: String?

    init(
        fiveHourUsage: Double? = nil,
        fiveHourResetAt: TimeInterval? = nil,
        sevenDayUsage: Double? = nil,
        sevenDayResetAt: TimeInterval? = nil,
        notifiedThresholds: [Int] = [],
        sevenDayNotifiedThresholds: [Int] = [],
        usageUpdatedAt: String? = nil,
        fiveHourUpdatedAt: String? = nil,
        sevenDayUpdatedAt: String? = nil,
        lastIngestErrorAt: String? = nil,
        session: SessionSnapshot? = nil,
        sessionUpdatedAt: String? = nil
    ) {
        self.fiveHourUsage = fiveHourUsage
        self.fiveHourResetAt = fiveHourResetAt
        self.sevenDayUsage = sevenDayUsage
        self.sevenDayResetAt = sevenDayResetAt
        self.notifiedThresholds = notifiedThresholds
        self.sevenDayNotifiedThresholds = sevenDayNotifiedThresholds
        self.usageUpdatedAt = usageUpdatedAt
        self.fiveHourUpdatedAt = fiveHourUpdatedAt
        self.sevenDayUpdatedAt = sevenDayUpdatedAt
        self.lastIngestErrorAt = lastIngestErrorAt
        self.session = session
        self.sessionUpdatedAt = sessionUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHourUsage
        case legacyLastUsage = "lastUsage"
        case fiveHourResetAt
        case sevenDayUsage
        case sevenDayResetAt
        case notifiedThresholds
        case sevenDayNotifiedThresholds
        case usageUpdatedAt
        case legacyUpdatedAt = "updatedAt"
        case fiveHourUpdatedAt
        case sevenDayUpdatedAt
        case lastIngestErrorAt
        case session
        case sessionUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHourUsage = try Self.percentage(
            container.decodeIfPresent(Double.self, forKey: .fiveHourUsage)
                ?? container.decodeIfPresent(Double.self, forKey: .legacyLastUsage),
            forKey: .fiveHourUsage,
            in: container
        )
        fiveHourResetAt = try container.decodeIfPresent(TimeInterval.self, forKey: .fiveHourResetAt)
        sevenDayUsage = try Self.percentage(
            container.decodeIfPresent(Double.self, forKey: .sevenDayUsage),
            forKey: .sevenDayUsage,
            in: container
        )
        sevenDayResetAt = try container.decodeIfPresent(TimeInterval.self, forKey: .sevenDayResetAt)
        notifiedThresholds = try container.decodeIfPresent([Int].self, forKey: .notifiedThresholds) ?? []
        sevenDayNotifiedThresholds = try container.decodeIfPresent(
            [Int].self,
            forKey: .sevenDayNotifiedThresholds
        ) ?? []
        usageUpdatedAt = try container.decodeIfPresent(String.self, forKey: .usageUpdatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .legacyUpdatedAt)
        // Estado gravado antes dos carimbos por janela: o melhor que se sabe é
        // o carimbo global. Herdá-lo não piora nada e evita marcar como antigo
        // um dado que acabou de chegar.
        fiveHourUpdatedAt = try container.decodeIfPresent(String.self, forKey: .fiveHourUpdatedAt)
            ?? usageUpdatedAt
        sevenDayUpdatedAt = try container.decodeIfPresent(String.self, forKey: .sevenDayUpdatedAt)
            ?? usageUpdatedAt
        lastIngestErrorAt = try container.decodeIfPresent(String.self, forKey: .lastIngestErrorAt)
        session = try container.decodeIfPresent(SessionSnapshot.self, forKey: .session)
        // O contexto da sessão passa pelo mesmo formatador que as janelas, e
        // portanto pela mesma trava: validar só as janelas deixava a porta
        // aberta ao lado.
        if let session, !session.isPlausible {
            throw DecodingError.dataCorruptedError(
                forKey: .session,
                in: container,
                debugDescription: "sessão com valores impossíveis"
            )
        }
        sessionUpdatedAt = try container.decodeIfPresent(String.self, forKey: .sessionUpdatedAt)
    }

    /// Uma percentagem do cache tem de ser uma percentagem.
    ///
    /// O payload já é validado ao entrar, mas o `state.json` era decodificado
    /// em bruto, e um arquivo corrompido (ou editado à mão: o app tem um botão
    /// que abre esta pasta) com `"fiveHourUsage": 1e19` decodificava sem queixa
    /// e derrubava o app ao formatar o número, a cada arranque, para sempre.
    /// Recusar aqui devolve `.invalid` ao StateStore, que descarta o cache e o
    /// reconstrói no próximo payload: o utilizador não vê nada disto.
    private static func percentage(
        _ value: Double?,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, (0 ... 100).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "percentagem fora de 0...100: \(value)"
            )
        }
        return value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fiveHourUsage, forKey: .fiveHourUsage)
        try container.encodeIfPresent(fiveHourResetAt, forKey: .fiveHourResetAt)
        try container.encodeIfPresent(sevenDayUsage, forKey: .sevenDayUsage)
        try container.encodeIfPresent(sevenDayResetAt, forKey: .sevenDayResetAt)
        try container.encode(notifiedThresholds, forKey: .notifiedThresholds)
        try container.encode(sevenDayNotifiedThresholds, forKey: .sevenDayNotifiedThresholds)
        try container.encodeIfPresent(usageUpdatedAt, forKey: .usageUpdatedAt)
        try container.encodeIfPresent(fiveHourUpdatedAt, forKey: .fiveHourUpdatedAt)
        try container.encodeIfPresent(sevenDayUpdatedAt, forKey: .sevenDayUpdatedAt)
        try container.encodeIfPresent(lastIngestErrorAt, forKey: .lastIngestErrorAt)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(sessionUpdatedAt, forKey: .sessionUpdatedAt)
    }
}

struct StatusLineSnapshot: Equatable {
    let rateLimits: RateLimits?
    let session: SessionSnapshot?
    /// Identificador da sessão do Claude Code que emitiu o payload. Estável
    /// durante a sessão e único entre sessões. Não vai para o `state.json`:
    /// serve para carimbar a amostra do histórico, onde é o que permite somar
    /// custo sem misturar sessões concorrentes (ver `CostAggregator`).
    let sessionId: String?
}

private struct StatusLinePayload: Decodable {
    let rateLimits: RateLimitPayload?
    let model: ModelPayload?
    let workspace: WorkspacePayload?
    let contextWindow: ContextWindowPayload?
    let sessionId: String?
    let sessionName: String?
    let version: String?
    let effort: EffortPayload?
    let thinking: ThinkingPayload?
    let cost: CostPayload?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
        case model
        case workspace
        case contextWindow = "context_window"
        case sessionId = "session_id"
        case sessionName = "session_name"
        case version
        case effort
        case thinking
        case cost
    }

    var normalized: StatusLineSnapshot {
        let limits = RateLimits(
            fiveHour: rateLimits?.fiveHour?.normalized,
            sevenDay: rateLimits?.sevenDay?.normalized
        )
        let session = SessionSnapshot(
            modelDisplayName: clean(model?.displayName),
            contextUsedPercentage: percentage(contextWindow?.usedPercentage),
            contextRemainingPercentage: percentage(contextWindow?.remainingPercentage),
            contextWindowSize: positive(contextWindow?.contextWindowSize),
            contextInputTokens: nonnegative(contextWindow?.totalInputTokens),
            contextOutputTokens: nonnegative(contextWindow?.totalOutputTokens),
            sessionName: clean(sessionName),
            projectName: projectName(workspace?.projectDirectory),
            claudeCodeVersion: clean(version),
            effortLevel: clean(effort?.level),
            thinkingEnabled: thinking?.enabled,
            estimatedCostUSD: nonnegative(cost?.totalCostUSD),
            totalDurationMS: nonnegative(cost?.totalDurationMS)
        )

        return StatusLineSnapshot(
            rateLimits: limits.hasValues ? limits : nil,
            session: session.hasValues ? session : nil,
            sessionId: clean(sessionId)
        )
    }

    /// Texto vindo do payload, pronto para exibir: sem espaço à volta, sem
    /// caracteres de controlo e no máximo 120 caracteres.
    ///
    /// Os controlos saem porque este texto é impresso num terminal pelo
    /// `--show`: um diretório com sequências de escape no nome chegava lá
    /// inteiro e podia reescrever a linha.
    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let printable = value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let normalized = String(String.UnicodeScalarView(printable))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(120))
    }

    private func projectName(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return clean(URL(fileURLWithPath: normalized).lastPathComponent)
    }

    private func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func nonnegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

private struct RateLimitPayload: Decodable {
    let fiveHour: WindowPayload?
    let sevenDay: WindowPayload?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct WindowPayload: Decodable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var normalized: UsageWindow? {
        guard let usedPercentage, usedPercentage.isFinite,
              (0...100).contains(usedPercentage) else {
            return nil
        }
        let validReset = resetsAt.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        return UsageWindow(usedPercentage: usedPercentage, resetsAt: validReset)
    }
}

private struct ModelPayload: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct WorkspacePayload: Decodable {
    let projectDirectory: String?

    enum CodingKeys: String, CodingKey {
        case projectDirectory = "project_dir"
    }
}

private struct ContextWindowPayload: Decodable {
    let totalInputTokens: Int?
    let totalOutputTokens: Int?
    let contextWindowSize: Int?
    let usedPercentage: Double?
    let remainingPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case contextWindowSize = "context_window_size"
        case usedPercentage = "used_percentage"
        case remainingPercentage = "remaining_percentage"
    }
}

private struct EffortPayload: Decodable {
    let level: String?
}

private struct ThinkingPayload: Decodable {
    let enabled: Bool?
}

private struct CostPayload: Decodable {
    let totalCostUSD: Double?
    let totalDurationMS: Int?

    enum CodingKeys: String, CodingKey {
        case totalCostUSD = "total_cost_usd"
        case totalDurationMS = "total_duration_ms"
    }
}

private extension SessionSnapshot {
    var hasValues: Bool {
        modelDisplayName != nil || contextUsedPercentage != nil ||
            contextRemainingPercentage != nil || contextWindowSize != nil ||
            contextInputTokens != nil || contextOutputTokens != nil ||
            sessionName != nil || projectName != nil || claudeCodeVersion != nil ||
            effortLevel != nil || thinkingEnabled != nil || estimatedCostUSD != nil ||
            totalDurationMS != nil
    }
}

enum StatusLineParser {
    static func parse(_ data: Data) -> StatusLineSnapshot? {
        try? JSONDecoder().decode(StatusLinePayload.self, from: data).normalized
    }
}

enum RateLimitParser {
    static func parse(_ data: Data) -> RateLimits? {
        StatusLineParser.parse(data)?.rateLimits
    }
}

enum UsageDataRecency: Equatable {
    case fresh
    case recentSessionWithoutLimits
    case stale(TimeInterval)
    case unknown

    static func evaluate(
        _ state: UsageState,
        relativeTo now: Date = Date(),
        staleAfter: TimeInterval
    ) -> UsageDataRecency {
        guard let usageAge = UsageFormatter.dataAge(state.usageUpdatedAt, relativeTo: now) else {
            return .unknown
        }
        guard usageAge > staleAfter else { return .fresh }

        if let sessionAge = UsageFormatter.dataAge(state.sessionUpdatedAt, relativeTo: now),
           sessionAge <= staleAfter {
            return .recentSessionWithoutLimits
        }
        return .stale(usageAge)
    }
}

enum UsageFormatter {
    /// Usage percentage at/above which the window is highlighted as critical.
    static let warningThreshold = 90.0

    static func percentage(_ value: Double) -> String {
        // Round to one decimal first so floating-point noise (e.g. 28.000000000000004,
        // which JSON decoding routinely produces) renders as "28" instead of "28.0".
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.1f", rounded)
    }

    static func tokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return String(value)
    }

    static func duration(milliseconds: Int) -> String {
        let minutes = max(0, milliseconds / 60_000)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)min" : "\(hours)h"
        }
        return "\(minutes)min"
    }

    static func reset(_ epochSeconds: TimeInterval?) -> String? {
        guard let epochSeconds, epochSeconds.isFinite, epochSeconds > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = L10n.shortDateTimeFormat
        return formatter.string(from: Date(timeIntervalSince1970: epochSeconds))
    }

    static func resetDescription(
        _ epochSeconds: TimeInterval?,
        relativeTo now: Date = Date()
    ) -> String? {
        guard let epochSeconds, epochSeconds.isFinite, epochSeconds > 0 else { return nil }
        let resetDate = Date(timeIntervalSince1970: epochSeconds)
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = L10n.fullDateTimeFormat
        let absolute = formatter.string(from: resetDate)
        let interval = resetDate.timeIntervalSince(now)

        guard interval > 0 else { return absolute }
        return "\(absolute) • \(remainingTime(interval))"
    }

    static func updatedDescription(_ value: String?, relativeTo now: Date = Date()) -> String {
        guard let date = isoDate(value) else {
            return L10n.awaitingData
        }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = L10n.updatedTimeFormat
        return "\(formatter.string(from: date)) (\(elapsedTime(now.timeIntervalSince(date))))"
    }

    static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Idade do dado em segundos, ou nil quando o timestamp é ausente/inválido.
    static func dataAge(_ value: String?, relativeTo now: Date = Date()) -> TimeInterval? {
        isoDate(value).map { now.timeIntervalSince($0) }
    }

    /// Resumo compacto do estado, compartilhado por --show, notificação de
    /// atualização manual e "Copiar resumo de uso".
    static func summary(_ state: UsageState, relativeTo now: Date = Date()) -> String {
        var parts: [String] = []
        parts.append(summaryWindow(
            L10n.fiveHoursLabel,
            usage: state.fiveHourUsage,
            resetAt: state.fiveHourResetAt,
            now: now
        ))
        if let weekly = summaryWindowIfAvailable(
            L10n.sevenDaysLabel,
            usage: state.sevenDayUsage,
            resetAt: state.sevenDayResetAt,
            now: now
        ) {
            parts.append(weekly)
        }
        if let context = state.session?.contextUsedPercentage {
            parts.append("\(L10n.contextLabel): \(percentage(context))%")
        }
        return parts.joined(separator: " • ")
    }

    private static func summaryWindow(
        _ label: String,
        usage: Double?,
        resetAt: TimeInterval?,
        now: Date
    ) -> String {
        summaryWindowIfAvailable(label, usage: usage, resetAt: resetAt, now: now)
            ?? "\(label): \(L10n.summaryUnavailable)"
    }

    private static func summaryWindowIfAvailable(
        _ label: String,
        usage: Double?,
        resetAt: TimeInterval?,
        now: Date
    ) -> String? {
        guard let usage else { return nil }
        if isExpired(resetAt, relativeTo: now) {
            return "\(label): \(L10n.waitingNewWindow)"
        }
        let resetSuffix = resetCountdown(resetAt, relativeTo: now)
            .map { " \(L10n.summaryResets($0))" } ?? ""
        return "\(label): \(percentage(usage))%\(resetSuffix)"
    }

    static func isExpired(_ epochSeconds: TimeInterval?, relativeTo now: Date = Date()) -> Bool {
        guard let epochSeconds, epochSeconds.isFinite, epochSeconds > 0 else { return false }
        return epochSeconds <= now.timeIntervalSince1970
    }

    static func statusLine(
        _ limits: RateLimits?,
        fallback state: UsageState? = nil,
        relativeTo now: Date = Date()
    ) -> String {
        // Prefer live windows from the payload; fall back per-window to the last
        // persisted values so the limits and reset times stay visible even when
        // Claude Code omits `rate_limits` (right after /clear, between API
        // responses, or when logged in with an API key).
        let fiveHour = limits?.fiveHour ?? state.flatMap { cached in
            cached.fiveHourUsage.map {
                UsageWindow(usedPercentage: $0, resetsAt: cached.fiveHourResetAt)
            }
        }
        let sevenDay = limits?.sevenDay ?? state.flatMap { cached in
            cached.sevenDayUsage.map {
                UsageWindow(usedPercentage: $0, resetsAt: cached.sevenDayResetAt)
            }
        }

        var parts: [String] = []
        if let fiveHour {
            parts.append(statusWindow("Claude 5h", fiveHour, now: now))
        }
        if let sevenDay {
            parts.append(statusWindow("7d", sevenDay, now: now))
        }
        return parts.isEmpty ? "Claude 5h: --" : parts.joined(separator: " | ")
    }

    private static func statusWindow(_ label: String, _ window: UsageWindow, now: Date) -> String {
        if isExpired(window.resetsAt, relativeTo: now) {
            return "\(label): -- (\(L10n.waitingNewWindow))"
        }
        let marker = window.usedPercentage >= warningThreshold ? " ⚠️" : ""
        let resetSuffix = resetCountdown(window.resetsAt, relativeTo: now)
            .map { " \(L10n.summaryResets($0))" } ?? ""
        return "\(label): \(percentage(window.usedPercentage))%\(marker)\(resetSuffix)"
    }

    /// Compact relative countdown to a reset ("in 2h 15min"), or nil when there
    /// is no valid future reset timestamp. More glanceable than an absolute date.
    private static func resetCountdown(
        _ epochSeconds: TimeInterval?,
        relativeTo now: Date
    ) -> String? {
        guard let epochSeconds, epochSeconds.isFinite, epochSeconds > 0 else { return nil }
        let interval = epochSeconds - now.timeIntervalSince1970
        guard interval > 0 else { return nil }
        return remainingTime(interval)
    }

    private static func remainingTime(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let remainingMinutes = minutes % 60

        if days > 0 {
            return L10n.inTime(hours > 0 ? "\(days)d \(hours)h" : "\(days)d")
        }
        if hours > 0 {
            return L10n.inTime(
                remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)min" : "\(hours)h"
            )
        }
        return L10n.inTime("\(minutes)min")
    }

    static func elapsedTime(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return L10n.now }
        let minutes = Int(interval / 60)
        if minutes < 60 { return L10n.agoTime("\(minutes)min") }
        let hours = minutes / 60
        if hours < 24 { return L10n.agoTime("\(hours)h") }
        return L10n.agoTime("\(hours / 24)d")
    }
}
