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
        expect(tateChuYokoCells.contains("12"), "two ASCII digits should stay in one half-width run")
        expect(tateChuYokoCells.contains("123"), "three ASCII digits should stay in one run")
        expect(tateChuYokoCells.contains("TypeScript Next.js"), "English words should stay in one run")
        expect(
            VerticalTextTypesetter.glyph(for: "12", alphanumericOrientation: .tateChuYoko).rotationDegrees == 90,
            "half-width digits should be sideways even when old settings request tate-chu-yoko"
        )
        expect(
            VerticalTextTypesetter.glyph(for: "PDF", alphanumericOrientation: .sideways).fontScale == 1,
            "sideways half-width letters should use the same font size as body text"
        )
        expect(
            VerticalTextTypesetter.cells(from: "PDF", alphanumericOrientation: .sideways).count >= 3,
            "sideways half-width letters should reserve enough cells at body size"
        )
        expect(
            VerticalTextTypesetter.cells(from: "ＡＢＣ１２３", alphanumericOrientation: .sideways).flatMap { $0 } == ["Ａ", "Ｂ", "Ｃ", "１", "２", "３"],
            "full-width alphanumeric characters should remain upright vertical characters"
        )

        let ellipsisCells = VerticalTextTypesetter.cells(from: "……。", alphanumericOrientation: .sideways)
        expect(ellipsisCells.count == 3, "double ellipsis should reserve two cells before punctuation")
        expect(ellipsisCells.first == ["……"], "double ellipsis should be drawn as one tight glyph run")
        expect(ellipsisCells.last == ["。"], "punctuation after ellipsis should keep its own cell")
        expect(VerticalTextTypesetter.formsNonBreakingPair("……", "。"), "ellipsis and punctuation should not split")

        let commaGlyph = VerticalTextTypesetter.glyph(for: "、", alphanumericOrientation: .sideways)
        expect(commaGlyph.xOffset > 0, "punctuation should sit toward the upper-right of the cell")
        expect(commaGlyph.yOffset < 0, "punctuation should sit toward the upper-right of the cell")

        let smallKanaGlyph = VerticalTextTypesetter.glyph(for: "ュ", alphanumericOrientation: .sideways)
        expect((0.70...0.80).contains(smallKanaGlyph.fontScale), "small kana should stay around 70-80 percent of body size")
        expect(smallKanaGlyph.xOffset > 0, "small kana should sit slightly to the right")
        expect(smallKanaGlyph.yOffset < 0, "small kana should sit higher in the cell")

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
        expect(VerticalTextTypesetter.formsNonBreakingPair("!?", "」"), "!? and closing quote should not split")

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
