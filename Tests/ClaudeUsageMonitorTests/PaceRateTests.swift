import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class PaceRateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    private func ramp(from: Double, to: Double, minutes: Int) -> [HistorySample] {
        (0...minutes).map { i in
            let progress = Double(i) / Double(minutes)
            return HistorySample(
                t: now.timeIntervalSince1970 - Double(minutes - i) * 60,
                h5: from + (to - from) * progress,
                d7: nil,
                c: nil
            )
        }
    }

    /// O ritmo alimenta o rótulo do sparkline: 10 pontos em 30 min são 20%/h.
    func testRateIsMeasuredInPointsPerHour() throws {
        let rate = try XCTUnwrap(
            PaceEstimator.slopePerHour(samples: ramp(from: 10, to: 20, minutes: 30), now: now)
        )
        XCTAssertEqual(rate, 20, accuracy: 0.5)
    }

    /// Consumo parado mede ~0: é o estado "sem consumo agora", não "a recolher
    /// dados". A distinção importa porque uma diz que está tudo calmo e a outra
    /// diz que o app ainda não sabe.
    func testFlatUsageMeasuresZeroRatherThanNil() throws {
        let rate = try XCTUnwrap(
            PaceEstimator.slopePerHour(samples: ramp(from: 40, to: 40, minutes: 30), now: now)
        )
        XCTAssertEqual(rate, 0, accuracy: 0.1)
    }

    /// Poucas amostras não são ritmo: aí sim é "a recolher dados".
    func testTooFewSamplesGiveNoRate() {
        XCTAssertNil(PaceEstimator.slopePerHour(samples: ramp(from: 10, to: 12, minutes: 1), now: now))
        XCTAssertNil(PaceEstimator.slopePerHour(samples: [], now: now))
    }

    /// O ritmo devolve valores abaixo do mínimo da projeção. A projeção exige
    /// 2%/h para não projetar ruído, mas "1%/h" continua a ser uma resposta
    /// honesta a "estou a gastar muito?".
    func testRateIsReportedBelowTheProjectionThreshold() throws {
        let samples = ramp(from: 40, to: 40.5, minutes: 30)
        let rate = try XCTUnwrap(PaceEstimator.slopePerHour(samples: samples, now: now))
        XCTAssertLessThan(rate, PaceEstimator.minimumSlopePerHour)
        XCTAssertNil(
            PaceEstimator.projectedLimitDate(
                samples: samples,
                currentUsage: 40.5,
                resetAt: now.timeIntervalSince1970 + 3_600,
                now: now
            ),
            "abaixo do mínimo não se projeta"
        )
    }
}
