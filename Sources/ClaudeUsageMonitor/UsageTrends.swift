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

/// Reparte o consumo da janela de 5 h pelos modelos que responderam.
///
/// A status line não informa limites por modelo, só o agregado e qual modelo
/// estava ativo. Então isto não é uma leitura: é uma atribuição. Entre duas
/// amostras, o que a janela subiu conta para o modelo da amostra mais recente.
enum ModelUsage {
    struct Share: Equatable {
        let model: String
        /// Fração do consumo do período, de 0 a 1.
        let fraction: Double
    }

    static func split(_ samples: [HistorySample]) -> [Share] {
        var totals: [String: Double] = [:]
        // Só pares com as duas pontas medidas: uma amostra pode não ter `h5` (o
        // histórico aceita amostras só de 7 dias, e cada janela pode faltar por
        // si só no payload). Sem linha de base não há degrau, e tomar a
        // ausência por zero fazia a amostra seguinte contar a janela inteira
        // como consumo novo do modelo que por acaso respondesse a seguir.
        let measured = samples.filter { $0.h5 != nil }
        for (previous, current) in zip(measured, measured.dropFirst()) {
            guard let model = current.m,
                  let value = current.h5, value.isFinite,
                  let previousValue = previous.h5, previousValue.isFinite else { continue }
            // Uma queda é reset de janela, não devolução de cota: o valor atual
            // é tudo o que a janela nova já consumiu. Mesma regra do custo.
            let delta = value >= previousValue ? value - previousValue : value
            guard delta > 0 else { continue }
            totals[model, default: 0] += delta
        }

        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [] }
        return totals
            .map { Share(model: $0.key, fraction: $0.value / total) }
            // Desempate pelo nome: com frações iguais a ordem do dicionário é
            // aleatória e a barra trocava de cor a cada refresh.
            .sorted { ($0.fraction, $1.model) > ($1.fraction, $0.model) }
    }
}

enum CostAggregator {
    /// Soma estimada do custo de API em um conjunto de amostras.
    ///
    /// Soma-se por sessão, e não a série toda. O `c` de cada amostra é o custo
    /// acumulado **daquela sessão** do Claude Code, mas o `history.jsonl` é um
    /// só para todas: com dois projetos abertos as amostras intercalam-se
    /// (US$ 3,00 da sessão A, US$ 0,05 da B, US$ 3,05 da A...). Somar isso como
    /// uma série única lia cada alternância como sessão nova e voltava a somar
    /// o custo inteiro da outra: seis amostras bastavam para relatar US$ 6,22
    /// onde se gastou US$ 0,12.
    ///
    /// Dentro de cada sessão o custo é cumulativo e zera em sessão nova, então
    /// somam-se os aumentos e uma queda entra inteira. A primeira amostra de
    /// cada sessão é baseline: o que ela gastou antes do período não conta.
    static func accumulatedCost(_ samples: [HistorySample]) -> Double? {
        // Um período que mistura amostras atribuíveis e antigas (gravadas antes
        // de o histórico carregar a sessão) não tem total verdadeiro: as
        // antigas contam para o gasto mas não dá para saber de que sessão
        // vieram. Somar só as novas devolveria um número menor que o real sem
        // dizer que é parcial, e um custo que parece baixo é pior do que um
        // custo que se assume não saber. Volta sozinho quando as antigas saem
        // da janela: sete dias, no máximo.
        if samples.contains(where: { $0.c != nil && $0.s == nil }) { return nil }

        var perSession: [String: [Double]] = [:]
        for sample in samples {
            guard let session = sample.s, let cost = sample.c else { continue }
            perSession[session, default: []].append(cost)
        }

        var total: Double?
        for costs in perSession.values where costs.count >= 2 {
            var session = 0.0
            for (previous, current) in zip(costs, costs.dropFirst()) {
                session += current >= previous ? current - previous : current
            }
            total = (total ?? 0) + session
        }
        return total
    }
}
