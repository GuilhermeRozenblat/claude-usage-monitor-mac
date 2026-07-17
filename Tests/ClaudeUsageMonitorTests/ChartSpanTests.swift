import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class ChartSpanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    /// O eixo da janela termina no reset e começa 5 h antes dele, não em
    /// "agora". É a diferença entre mostrar uma janela e mostrar duas metades
    /// coladas por um penhasco.
    func testWindowSpanIsAnchoredOnTheResetNotOnNow() {
        let resetAt = now.timeIntervalSince1970 + 3_600 // reset daqui a 1 h
        let span = ChartSpan.resolve(range: .window, resetAt: resetAt, now: now)

        XCTAssertEqual(span.end, resetAt)
        XCTAssertEqual(span.start, resetAt - 5 * 3_600)
        XCTAssertEqual(span.duration, 5 * 3_600)
        // "Agora" cai dentro da janela, perto do fim: 4 h gastas, 1 h por gastar.
        XCTAssertGreaterThan(now.timeIntervalSince1970, span.start)
        XCTAssertLessThan(now.timeIntervalSince1970, span.end)
    }

    /// A janela começa sempre depois de `agora − 5h` (o reset está no futuro),
    /// então carregar 5 h de histórico a partir de agora cobre-a inteira. Se
    /// isto deixar de valer, o gráfico perde o início da janela.
    func testWindowStartIsAlwaysWithinTheLastFiveHours() {
        for minutesToReset in [1, 60, 180, 299] {
            let resetAt = now.timeIntervalSince1970 + Double(minutesToReset) * 60
            let span = ChartSpan.resolve(range: .window, resetAt: resetAt, now: now)
            XCTAssertGreaterThanOrEqual(
                span.start,
                now.timeIntervalSince1970 - 5 * 3_600,
                "reset em \(minutesToReset)min deixaria o início da janela fora da carga"
            )
        }
    }

    /// Sem reset conhecido não há janela ativa: recua para o intervalo rolante
    /// em vez de inventar uma âncora.
    func testWindowFallsBackToRollingWithoutAReset() {
        let span = ChartSpan.resolve(range: .window, resetAt: nil, now: now)
        XCTAssertEqual(span.end, now.timeIntervalSince1970)
        XCTAssertEqual(span.start, now.timeIntervalSince1970 - 5 * 3_600)
    }

    /// Um reset já vencido não ancora nada: a janela dele acabou.
    func testExpiredResetFallsBackToRolling() {
        let span = ChartSpan.resolve(
            range: .window,
            resetAt: now.timeIntervalSince1970 - 60,
            now: now
        )
        XCTAssertEqual(span.end, now.timeIntervalSince1970)
    }

    /// Os ranges históricos continuam rolantes: só a janela é ancorada.
    func testHistoricalRangesIgnoreTheReset() {
        let resetAt = now.timeIntervalSince1970 + 3_600
        for range in [HistoryRange.day, .week, .month, .quarter] {
            let span = ChartSpan.resolve(range: range, resetAt: resetAt, now: now)
            XCTAssertEqual(span.end, now.timeIntervalSince1970, "\(range) não deveria ancorar")
            XCTAssertEqual(span.duration, range.seconds)
        }
    }

    /// O seletor de range é construído a partir de `allCases`, e o índice do
    /// segmento é o `rawValue`: se a ordem mudar, o clique seleciona outro range.
    func testRangeRawValuesMatchSegmentOrder() {
        for (index, range) in HistoryRange.allCases.enumerated() {
            XCTAssertEqual(range.rawValue, index)
        }
        XCTAssertEqual(HistoryRange.window.rawValue, 0)
    }
}

/// O eixo da janela de 5 h é ancorado no reset, mas a carga do histórico começa
/// em `agora − 5h`, que é antes. O pedaço entre os dois é da janela anterior.
final class WindowClippingTests: XCTestCase {
    /// Sem recorte, `xPosition` grampeava as amostras da janela anterior em
    /// cima do eixo Y e o rodapé anunciava o pico delas como o da janela atual.
    func testTheWindowRangeExcludesThePreviousWindow() {
        let now = Date()
        let span = ChartSpan.resolve(
            range: .window,
            resetAt: now.timeIntervalSince1970 + 4 * 3600,
            now: now
        )
        // A janela atual começou há uma hora.
        XCTAssertEqual(span.start, now.timeIntervalSince1970 - 3600, accuracy: 1)

        // Como a janela de histórico carregada é de 5 h, quatro horas de
        // amostras ficam fora do eixo: são da janela que já reiniciou. O reset
        // cai entre duas amostras (a 60 s uma da outra, nunca no mesmo
        // instante), então as da janela anterior estão todas antes do corte.
        let loaded = (0 ..< 300).map { minute in
            HistorySample(
                t: now.timeIntervalSince1970 - Double(minute) * 60,
                h5: minute > 60 ? 98 : 20,
                d7: nil,
                c: nil,
                m: "Opus",
                s: "A"
            )
        }
        let clipped = loaded.filter { $0.t >= span.start && $0.t <= span.end }
        XCTAssertEqual(clipped.count, 61, "só a hora decorrida da janela atual")
        XCTAssertEqual(clipped.compactMap(\.h5).max(), 20, "o pico veio da janela anterior")
    }
}
