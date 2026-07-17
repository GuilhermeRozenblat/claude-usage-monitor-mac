import Foundation

/// Projeções e agregações locais sobre as amostras do histórico. Tudo aqui é
/// estimativa derivada de dados já coletados, sem nenhuma chamada externa.
enum PaceEstimator {
    /// Janela de amostras considerada para medir o ritmo atual.
    static let lookback: TimeInterval = 45 * 60

    /// Ritmo mínimo (pontos percentuais por hora) para valer uma projeção;
    /// abaixo disso é ruído de medição.
    static let minimumSlopePerHour = 2.0

    /// Projeta quando a janela de 5 horas atinge 100% mantido o ritmo recente,
    /// ou nil quando não há ritmo relevante ou o reset chega antes.
    /// Ritmo recente em pontos percentuais por hora, ou nil quando não há
    /// amostras suficientes para medir. Devolve o valor mesmo abaixo do mínimo
    /// da projeção: "2% por hora" continua a ser uma resposta a "estou a gastar
    /// muito?", mesmo quando não dá para projetar o limite.
    static func slopePerHour(samples: [HistorySample], now: Date) -> Double? {
        let cutoff = now.timeIntervalSince1970 - lookback
        var points = samples.compactMap { sample -> (t: Double, value: Double)? in
            guard sample.t >= cutoff, sample.t <= now.timeIntervalSince1970 + 60,
                  let value = sample.h5 else { return nil }
            return (sample.t, value)
        }

        // Uma queda dentro da janela indica reset: só o trecho posterior mede
        // o ritmo da janela atual.
        if let lastDrop = points.indices.dropFirst().last(where: { index in
            points[index].value < points[index - 1].value - UsageThresholds.resetDropTolerance
        }) {
            points = Array(points[lastDrop...])
        }
        guard points.count >= 3 else { return nil }

        // Regressão linear simples: inclinação em pontos percentuais/segundo.
        let n = Double(points.count)
        let meanT = points.reduce(0) { $0 + $1.t } / n
        let meanV = points.reduce(0) { $0 + $1.value } / n
        let covariance = points.reduce(0) { $0 + ($1.t - meanT) * ($1.value - meanV) }
        let variance = points.reduce(0) { $0 + ($1.t - meanT) * ($1.t - meanT) }
        guard variance > 0 else { return nil }
        return covariance / variance * 3_600
    }

    static func projectedLimitDate(
        samples: [HistorySample],
        currentUsage: Double,
        resetAt: TimeInterval?,
        now: Date
    ) -> Date? {
        guard currentUsage < 100 else { return nil }
        guard let ratePerHour = slopePerHour(samples: samples, now: now),
              ratePerHour >= minimumSlopePerHour else { return nil }
        let slope = ratePerHour / 3_600
        let secondsToLimit = (100 - currentUsage) / slope
        let target = now.addingTimeInterval(secondsToLimit)

        // Se o reset chega antes da projeção, o limite não será atingido.
        if let resetAt, resetAt.isFinite, resetAt > 0,
           target.timeIntervalSince1970 >= resetAt {
            return nil
        }
        return target
    }
}

enum CostAggregator {
    /// Soma estimada do custo de API em um conjunto de amostras. O custo por
    /// sessão é cumulativo e zera em sessão nova, então soma-se os aumentos;
    /// uma queda indica sessão nova e o valor corrente entra inteiro.
    /// A primeira amostra é baseline (custo anterior ao período não conta).
    static func accumulatedCost(_ samples: [HistorySample]) -> Double? {
        let costs = samples.compactMap(\.c)
        guard costs.count >= 2 else { return nil }

        var total = 0.0
        for (previous, current) in zip(costs, costs.dropFirst()) {
            total += current >= previous ? current - previous : current
        }
        return total
    }
}
