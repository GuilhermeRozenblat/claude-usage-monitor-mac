import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class UsageTrendsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    private func rising(
        rate perMinute: Double,
        minutes: Int,
        endUsage: Double,
        endOffset: TimeInterval = 0
    ) -> [HistorySample] {
        (0...minutes).map { minute in
            HistorySample(
                t: now.timeIntervalSince1970 - endOffset - Double((minutes - minute) * 60),
                h5: endUsage - Double(minutes - minute) * perMinute,
                d7: nil
            )
        }
    }

    // MARK: - PaceEstimator

    func testProjectsLimitFromSteadyClimb() throws {
        // 0,5 ponto/min = 30 pontos/h; de 70% faltam 30 pontos → ~1h.
        let samples = rising(rate: 0.5, minutes: 30, endUsage: 70)
        let projected = try XCTUnwrap(PaceEstimator.projectedLimitDate(
            samples: samples,
            currentUsage: 70,
            resetAt: now.timeIntervalSince1970 + 4 * 3_600,
            now: now
        ))
        XCTAssertEqual(projected.timeIntervalSince(now), 3_600, accuracy: 120)
    }

    func testNoProjectionWhenFlatOrFalling() {
        let flat = (0...30).map {
            HistorySample(t: now.timeIntervalSince1970 - Double((30 - $0) * 60), h5: 40, d7: nil)
        }
        XCTAssertNil(PaceEstimator.projectedLimitDate(
            samples: flat,
            currentUsage: 40,
            resetAt: nil,
            now: now
        ))
    }

    func testNoProjectionWhenResetComesFirst() {
        let samples = rising(rate: 0.5, minutes: 30, endUsage: 70)
        XCTAssertNil(PaceEstimator.projectedLimitDate(
            samples: samples,
            currentUsage: 70,
            resetAt: now.timeIntervalSince1970 + 600,
            now: now
        ), "Reset em 10min chega antes da projeção de 1h")
    }

    func testSlicesAfterWindowResetDrop() throws {
        // Janela anterior caindo de 95 para 20 há 20min; depois subida rápida.
        var samples = rising(rate: 1, minutes: 20, endUsage: 95, endOffset: 21 * 60)
        samples += rising(rate: 1, minutes: 20, endUsage: 20)
        let projected = PaceEstimator.projectedLimitDate(
            samples: samples,
            currentUsage: 20,
            resetAt: now.timeIntervalSince1970 + 5 * 3_600,
            now: now
        )
        // 1 ponto/min a partir de 20% → 80min; a janela antiga não contamina.
        let interval = try XCTUnwrap(projected).timeIntervalSince(now)
        XCTAssertEqual(interval, 80 * 60, accuracy: 300)
    }

    func testNoProjectionWithTooFewSamples() {
        let samples = rising(rate: 1, minutes: 1, endUsage: 50)
        XCTAssertNil(PaceEstimator.projectedLimitDate(
            samples: samples,
            currentUsage: 50,
            resetAt: nil,
            now: now
        ))
    }

    // MARK: - CostAggregator

    // As amostras carregam a sessão que as emitiu: sem isso o custo não é
    // atribuível e fica de fora da soma (ver CostPerSessionTests).
    func testAccumulatesIncreasesWithinSession() {
        let samples = [0.10, 0.25, 0.40].enumerated().map { index, cost in
            HistorySample(t: Double(index), h5: 1, d7: nil, c: cost, m: nil, s: "A")
        }
        XCTAssertEqual(CostAggregator.accumulatedCost(samples)!, 0.30, accuracy: 0.0001)
    }

    func testCostDropCountsAsNewSession() {
        let samples = [0.50, 0.80, 0.05, 0.20].enumerated().map { index, cost in
            HistorySample(t: Double(index), h5: 1, d7: nil, c: cost, m: nil, s: "A")
        }
        // +0,30 (0,50→0,80), a sessão recomeçou e 0,05 entra inteiro, +0,15 → 0,50.
        XCTAssertEqual(CostAggregator.accumulatedCost(samples)!, 0.50, accuracy: 0.0001)
    }

    func testCostNilWithoutEnoughData() {
        XCTAssertNil(CostAggregator.accumulatedCost([]))
        XCTAssertNil(CostAggregator.accumulatedCost([
            HistorySample(t: 0, h5: 1, d7: nil, c: 0.5, m: nil, s: "A"),
        ]))
        XCTAssertNil(CostAggregator.accumulatedCost([
            HistorySample(t: 0, h5: 1, d7: nil, c: nil, m: nil, s: "A"),
            HistorySample(t: 1, h5: 2, d7: nil, c: nil, m: nil, s: "A"),
        ]))
    }

    // MARK: - Perfil de marcos na entrega

    func testDeliveryHonorsThresholdProfile() {
        let outcome = ThresholdDelivery.evaluate(
            notified: [25, 50],
            resetId: "A",
            previous: nil,
            dataIsFresh: true,
            enabled: ThresholdProfile.high.fiveHour
        )
        XCTAssertNil(outcome.announce, "25/50 fora do perfil 75%+ não anunciam")
        XCTAssertEqual(outcome.record.delivered, [25, 50], "Mas ficam marcados como entregues")

        let critical = ThresholdDelivery.evaluate(
            notified: [25, 50, 75, 90],
            resetId: "A",
            previous: nil,
            dataIsFresh: true,
            enabled: ThresholdProfile.critical.fiveHour
        )
        XCTAssertEqual(critical.announce, 90)
    }

    func testProfileSets() {
        XCTAssertEqual(ThresholdProfile.all.fiveHour, [25, 50, 75, 90, 100])
        XCTAssertEqual(ThresholdProfile.high.fiveHour, [75, 90, 100])
        XCTAssertEqual(ThresholdProfile.critical.sevenDay, [100])
    }

    // MARK: - Amostra com custo

    func testHistorySampleCostRoundTrip() throws {
        let sample = HistorySample(t: 1_784_000_000, h5: 40, d7: 20, c: 0.1234)
        let data = try JSONEncoder().encode(sample)
        XCTAssertEqual(try JSONDecoder().decode(HistorySample.self, from: data), sample)

        // Linhas antigas sem o campo c continuam decodificáveis.
        let legacy = Data(#"{"t":1784000000,"h5":40,"d7":20}"#.utf8)
        let decoded = try JSONDecoder().decode(HistorySample.self, from: legacy)
        XCTAssertNil(decoded.c)
    }
}

/// O custo é acumulado por sessão do Claude Code, mas o `history.jsonl` é um só
/// para todas elas.
final class CostPerSessionTests: XCTestCase {
    private func sample(_ t: Double, cost: Double, session: String?) -> HistorySample {
        HistorySample(t: t, h5: nil, d7: nil, c: cost, m: nil, s: session)
    }

    /// Dois projetos abertos ao mesmo tempo: as amostras intercalam-se e cada
    /// alternância parecia uma sessão nova, somando de novo o custo inteiro da
    /// outra. Seis amostras bastavam para relatar US$ 6,22 onde se gastou 0,12.
    func testInterleavedSessionsDoNotInflateTheTotal() throws {
        let samples = [
            sample(0, cost: 3.00, session: "A"),
            sample(60, cost: 0.05, session: "B"),
            sample(120, cost: 3.05, session: "A"),
            sample(180, cost: 0.06, session: "B"),
            sample(240, cost: 3.10, session: "A"),
            sample(300, cost: 0.07, session: "B"),
        ]
        let total = try XCTUnwrap(CostAggregator.accumulatedCost(samples))
        // A subiu 0,10 e B subiu 0,02. Mais nada aconteceu.
        XCTAssertEqual(total, 0.12, accuracy: 0.0001)
    }

    /// Dentro de uma sessão o custo zera quando ela recomeça, e aí o valor
    /// corrente conta inteiro.
    func testCostResetWithinASessionCountsInFull() throws {
        let total = try XCTUnwrap(CostAggregator.accumulatedCost([
            sample(0, cost: 1.00, session: "A"),
            sample(60, cost: 1.50, session: "A"),
            sample(120, cost: 0.20, session: "A"),
        ]))
        XCTAssertEqual(total, 0.70, accuracy: 0.0001)
    }

    /// A primeira amostra de cada sessão é linha de base: o que ela gastou
    /// antes do período não pertence ao período.
    func testTheFirstSampleOfEachSessionIsABaseline() throws {
        let total = try XCTUnwrap(CostAggregator.accumulatedCost([
            sample(0, cost: 9.00, session: "A"),
            sample(60, cost: 9.25, session: "A"),
        ]))
        XCTAssertEqual(total, 0.25, accuracy: 0.0001)
    }

    /// Amostras gravadas antes de existir o campo não dão para atribuir.
    /// Preferimos não somar a somar errado.
    func testLegacySamplesWithoutASessionAreIgnored() {
        XCTAssertNil(CostAggregator.accumulatedCost([
            sample(0, cost: 3.00, session: nil),
            sample(60, cost: 0.05, session: nil),
        ]))
    }

    /// O caso da atualização: o período tem amostras novas e antigas. Somar só
    /// as novas daria um número menor que o gasto real, e sem dizer que é
    /// parcial. Melhor assumir que não se sabe até as antigas saírem da janela.
    func testAPeriodMixingOldAndNewSamplesHasNoTrustworthyTotal() {
        XCTAssertNil(CostAggregator.accumulatedCost([
            sample(0, cost: 3.00, session: nil),
            sample(60, cost: 3.20, session: nil),
            sample(120, cost: 0.05, session: "A"),
            sample(180, cost: 0.25, session: "A"),
        ]))
    }

    func testASingleSampleInASessionHasNothingToMeasure() {
        XCTAssertNil(CostAggregator.accumulatedCost([sample(0, cost: 3.00, session: "A")]))
    }
}
