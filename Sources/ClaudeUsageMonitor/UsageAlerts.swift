import Foundation

enum UsageThresholds {
    static let fiveHour = [25, 50, 75, 90, 100]
    static let sevenDay = [75, 90, 100]

    /// Queda de uso (em pontos percentuais) que indica reinício da janela
    /// mesmo quando o resets_at não mudou ou está ausente.
    static let resetDropTolerance = 10.0
}

/// Perfil de entrega escolhido pelo usuário. O ingest sempre rastreia todos os
/// marcos em state.json; o perfil só filtra o que vira notificação. Trocar de
/// perfil não exige nada do lado do ingest.
enum ThresholdProfile: String, CaseIterable {
    case all
    case high
    case critical

    var fiveHour: [Int] {
        switch self {
        case .all: UsageThresholds.fiveHour
        case .high: [75, 90, 100]
        case .critical: [90, 100]
        }
    }

    var sevenDay: [Int] {
        switch self {
        case .all: UsageThresholds.sevenDay
        case .high: [90, 100]
        case .critical: [100]
        }
    }
}

enum AlertPolicy {
    /// Idade máxima do dado para ainda valer um alerta de threshold; acima
    /// disso o cruzamento é marcado como entregue sem notificar.
    static let maxAlertAge: TimeInterval = 30 * 60

    /// Idade a partir da qual o dado é considerado obsoleto na UI.
    static let staleAfter: TimeInterval = 15 * 60

    /// Janela após o reset em que ainda faz sentido anunciar "uso liberado".
    static let resetAnnounceWindow: TimeInterval = 30 * 60

    /// Uso mínimo atingido na janela anterior para anunciar o reinício.
    static let resetAnnounceMinimumThreshold = 75
}

/// Lado do ingest: mantém em state.json quais thresholds a janela atual já
/// cruzou. É a fonte única de verdade; o app de menu bar apenas entrega.
enum ThresholdTracker {
    static func updated(
        notified: [Int],
        thresholds: [Int],
        usage: Double,
        previousUsage: Double?,
        previousResetAt: TimeInterval?,
        resetAt: TimeInterval?
    ) -> [Int] {
        let resetChanged = previousResetAt != nil && resetAt != nil && previousResetAt != resetAt
        let usageDropped = previousUsage
            .map { usage < $0 - UsageThresholds.resetDropTolerance } ?? false

        var crossed = previousUsage == nil
            ? thresholds.filter { Double($0) <= usage }
            : notified
        if resetChanged || usageDropped {
            crossed = []
        }
        crossed.append(contentsOf: thresholds.filter {
            Double($0) <= usage && !crossed.contains($0)
        })
        return Array(Set(crossed)).sorted()
    }
}

/// Registro persistido (UserDefaults) de quais cruzamentos já foram entregues
/// como notificação para uma janela.
struct ThresholdDeliveryRecord: Equatable {
    var resetId: String
    var delivered: [Int]

    var dictionary: [String: Any] {
        ["resetId": resetId, "delivered": delivered]
    }

    init(resetId: String, delivered: [Int]) {
        self.resetId = resetId
        self.delivered = delivered
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary,
              let resetId = dictionary["resetId"] as? String,
              let delivered = dictionary["delivered"] as? [Int] else {
            return nil
        }
        self.init(resetId: resetId, delivered: delivered)
    }
}

/// Lado do app: decide o que anunciar comparando os cruzamentos registrados
/// pelo ingest com o que já foi entregue.
enum ThresholdDelivery {
    struct Outcome: Equatable {
        var announce: Int?
        var record: ThresholdDeliveryRecord
    }

    /// Quando há mais de um cruzamento pendente (app fechado durante a subida),
    /// anuncia apenas o maior em vez de empilhar notificações. `dataIsFresh`
    /// falso marca os pendentes como entregues sem anunciar (dado velho demais).
    /// `enabled` limita o anúncio aos marcos do perfil escolhido; os demais são
    /// marcados como entregues em silêncio (trocar de perfil não gera backlog).
    static func evaluate(
        notified: [Int],
        resetId: String,
        previous: ThresholdDeliveryRecord?,
        dataIsFresh: Bool,
        enabled: [Int]? = nil
    ) -> Outcome {
        var delivered = previous?.resetId == resetId ? (previous?.delivered ?? []) : []
        // Um conjunto entregue com itens fora do notificado significa que o
        // ingest iniciou nova janela sem mudar o resetId (resets_at ausente).
        if delivered.contains(where: { !notified.contains($0) }) {
            delivered = []
        }

        let pending = notified.filter { !delivered.contains($0) }
        let record = ThresholdDeliveryRecord(resetId: resetId, delivered: notified.sorted())
        let announceable = enabled.map { allowed in pending.filter(allowed.contains) } ?? pending
        guard dataIsFresh, let highest = announceable.max() else {
            return Outcome(announce: nil, record: record)
        }
        return Outcome(announce: highest, record: record)
    }
}

/// Decide se vale anunciar que a janela reiniciou: apenas uma vez
/// por janela, logo após o reset e somente se a janela anterior chegou alto.
enum WindowResetAnnouncement {
    static func evaluate(
        resetAt: TimeInterval?,
        maxNotifiedThreshold: Int?,
        alreadyAnnounced: String?,
        now: Date
    ) -> String? {
        guard let resetAt, resetAt.isFinite, resetAt > 0 else { return nil }
        let identifier = String(resetAt)
        guard alreadyAnnounced != identifier else { return nil }
        guard let maxNotifiedThreshold,
              maxNotifiedThreshold >= AlertPolicy.resetAnnounceMinimumThreshold else {
            return nil
        }
        let elapsed = now.timeIntervalSince1970 - resetAt
        guard elapsed >= 0, elapsed <= AlertPolicy.resetAnnounceWindow else { return nil }
        return identifier
    }
}
