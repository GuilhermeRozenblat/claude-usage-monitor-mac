import AppKit
import XCTest
@testable import ClaudeUsageMonitor

/// A paleta da repartição por modelo é uma promessa de legibilidade, e uma
/// promessa dessas merece um teste: cores escolhidas a olho passam a estar
/// erradas assim que alguém mexe num tom.
final class ModelShareContrastTests: XCTestCase {
    /// Piso da WCAG para um elemento gráfico que carrega informação.
    private let minimumAgainstBackground = 3.0
    /// Separação mínima de luminosidade entre tons vizinhos. Não é contraste
    /// de leitura, é "dá para ver que mudou de fatia".
    private let minimumBetweenRanks = 1.25

    func testEveryToneClearsTheFloorInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let (background, tones) = try resolve(name)
            for (rank, tone) in tones.enumerated() {
                let ratio = contrast(tone, background)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    minimumAgainstBackground,
                    "tom \(rank) em \(name.rawValue) mede \(ratio):1 contra o fundo"
                )
            }
        }
    }

    func testNeighbouringTonesAreTellableApart() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let (_, tones) = try resolve(name)
            for (first, second) in zip(tones, tones.dropFirst()) {
                let ratio = contrast(first, second)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    minimumBetweenRanks,
                    "tons vizinhos em \(name.rawValue) medem \(ratio):1 entre si"
                )
            }
        }
    }

    /// Uma cor dinâmica só resolve dentro do contexto de desenho: `usingColorSpace`
    /// fora dele responde na aparência do sistema, então medir cá fora media o
    /// tema de quem corre o teste, não o tema pedido.
    private func resolve(_ name: NSAppearance.Name) throws -> (background: Double, tones: [Double]) {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var background = 0.0
        var tones: [Double] = []
        appearance.performAsCurrentDrawingAppearance {
            background = (try? luminance(.windowBackgroundColor)) ?? 1
            tones = (0 ..< 4).compactMap { try? luminance(Palette.modelShare(rank: $0)) }
        }
        XCTAssertEqual(tones.count, 4, "algum tom não resolveu em \(name.rawValue)")
        return (background, tones)
    }

    /// O nome do modelo é escrito dentro da fatia, então cada tom tem de
    /// aguentar texto por cima: 4.5:1, o piso de leitura, que é mais exigente
    /// que os 3:1 do gráfico. Nenhuma tinta fixa serve para a rampa toda, e é
    /// por isso que `Palette.ink` escolhe pela luminância medida.
    func testEveryToneCarriesReadableText() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var ratios: [Double] = []
            appearance.performAsCurrentDrawingAppearance {
                ratios = (0 ..< 4).compactMap { rank in
                    let tone = Palette.modelShare(rank: rank)
                    guard let background = try? luminance(tone),
                          let ink = try? luminance(Palette.ink(on: tone)) else { return nil }
                    return contrast(ink, background)
                }
            }
            XCTAssertEqual(ratios.count, 4)
            for (rank, ratio) in ratios.enumerated() {
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "texto sobre o tom \(rank) em \(name.rawValue) mede \(ratio):1"
                )
            }
        }
    }

    /// Os tons têm de ser opacos: alpha mistura-se com o que estiver por baixo,
    /// e nesse caso a medição acima não vale nada.
    func testTonesAreOpaque() throws {
        for rank in 0 ..< 4 {
            let color = try XCTUnwrap(Palette.modelShare(rank: rank).usingColorSpace(.sRGB))
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001, "tom \(rank) translúcido")
        }
    }

    /// Fora da rampa a cor não pode ficar `nil` nem estourar o índice: quem
    /// desenha pergunta pelo rank que tem, não pelo que a paleta tem.
    func testRanksBeyondTheRampFallBackToTheLastTone() throws {
        let last = try XCTUnwrap(Palette.modelShare(rank: 3).usingColorSpace(.sRGB))
        let beyond = try XCTUnwrap(Palette.modelShare(rank: 9).usingColorSpace(.sRGB))
        XCTAssertEqual(beyond.redComponent, last.redComponent, accuracy: 0.001)
        XCTAssertEqual(beyond.blueComponent, last.blueComponent, accuracy: 0.001)
    }

    private func luminance(_ color: NSColor) throws -> Double {
        let resolved = try XCTUnwrap(color.usingColorSpace(.sRGB))
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(resolved.redComponent)
            + 0.7152 * channel(resolved.greenComponent)
            + 0.0722 * channel(resolved.blueComponent)
    }

    private func contrast(_ first: Double, _ second: Double) -> Double {
        let (lighter, darker) = first > second ? (first, second) : (second, first)
        return ((lighter + 0.05) / (darker + 0.05) * 100).rounded() / 100
    }
}
