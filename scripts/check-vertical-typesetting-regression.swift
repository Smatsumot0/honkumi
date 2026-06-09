import CoreGraphics
import Darwin
import Foundation

nonisolated enum AlphanumericOrientation {
    case stacked
    case sideways
    case tateChuYoko
}

@main
struct VerticalTypesettingRegressionCheck {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        let sidewaysCells = VerticalTextTypesetter
            .cells(
                from: "TypeScript Next.js React Hello World abcdef ABCDEF 1234567890",
                alphanumericOrientation: .sideways
            )
            .flatMap { $0 }

        for run in ["TypeScript Next.js React Hello World abcdef ABCDEF 1234567890"] {
            expect(sidewaysCells.contains(run), "half-width alphanumeric text should stay in one sideways run")
        }
        expect(!sidewaysCells.contains("T"), "TypeScript should not be split into single letters")

        let tateChuYokoCells = VerticalTextTypesetter
            .cells(from: "12と123とTypeScript Next.js", alphanumericOrientation: .tateChuYoko)
            .flatMap { $0 }
        expect(tateChuYokoCells.contains("12"), "two ASCII digits should use tate-chu-yoko")
        expect(tateChuYokoCells.contains("123"), "three ASCII digits should stay in one run")
        expect(tateChuYokoCells.contains("TypeScript Next.js"), "English words should stay in one run")

        let ellipsisCells = VerticalTextTypesetter.cells(from: "……。", alphanumericOrientation: .sideways)
        expect(ellipsisCells.count == 3, "double ellipsis should reserve two cells before punctuation")
        expect(ellipsisCells.first == ["……"], "double ellipsis should be drawn as one tight glyph run")
        expect(ellipsisCells.last == ["。"], "punctuation after ellipsis should keep its own cell")

        let commaGlyph = VerticalTextTypesetter.glyph(for: "、", alphanumericOrientation: .sideways)
        expect(commaGlyph.xOffset < 0.24, "punctuation should be moved left from the old offset")
        expect(commaGlyph.yOffset > -0.22, "punctuation should be moved down from the old offset")

        let smallKanaGlyph = VerticalTextTypesetter.glyph(for: "ュ", alphanumericOrientation: .sideways)
        expect(smallKanaGlyph.xOffset < 0.16, "small kana should be moved left from the old offset")
        expect(smallKanaGlyph.yOffset > -0.10, "small kana should be moved down from the old offset")

        let bracketGlyph = VerticalTextTypesetter.glyph(for: "【", alphanumericOrientation: .sideways)
        expect(bracketGlyph.text == "︻", "lenticular brackets should use vertical glyph forms")
        expect(bracketGlyph.rotationDegrees == 0, "vertical bracket glyphs should not be sideways rotated")

        expect(VerticalTextTypesetter.isLineStartProhibited("!"), "half-width exclamation mark should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineStartProhibited("ゃ"), "small kana should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineStartProhibited("」"), "closing brackets should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineEndProhibited("「"), "opening brackets should be line-end prohibited")

        let units = VerticalTextTypesetter
            .layoutUnits(from: "だ!?」", alphanumericOrientation: .sideways)
            .map(\.text)
        expect(units == ["だ", "!?", "」"], "!? should stay paired before a closing bracket")

        guard failures.isEmpty else {
            fputs("Vertical typesetting regression check failed:\n", stderr)
            for failure in failures {
                fputs("- \(failure)\n", stderr)
            }
            exit(1)
        }

        print("Vertical typesetting regression check passed.")
    }
}
