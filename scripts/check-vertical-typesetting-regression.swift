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
            VerticalTextTypesetter.glyph(for: "12", alphanumericOrientation: .tateChuYoko).rotationDegrees == 0,
            "short half-width digits should stay horizontal for tate-chu-yoko"
        )
        expect(
            VerticalTextTypesetter.glyph(for: "12", alphanumericOrientation: .tateChuYoko).fontScale < 1,
            "tate-chu-yoko digits should fit inside one vertical body cell"
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
        expect((0.40...0.46).contains(commaGlyph.xOffset), "punctuation should move 0.3 body cells to the right")
        expect((-0.51 ... -0.45).contains(commaGlyph.yOffset), "punctuation should move 0.5 body cells upward")

        let smallKanaGlyph = VerticalTextTypesetter.glyph(for: "ュ", alphanumericOrientation: .sideways)
        expect((0.80...0.88).contains(smallKanaGlyph.fontScale), "small kana should stay slightly smaller than body size")
        expect((0.03...0.08).contains(smallKanaGlyph.xOffset), "small kana should not sit too far right")
        expect((-0.04...0.02).contains(smallKanaGlyph.yOffset), "small kana should stay near the natural vertical body center")

        let bracketGlyph = VerticalTextTypesetter.glyph(for: "【", alphanumericOrientation: .sideways)
        expect(bracketGlyph.text == "︻", "lenticular brackets should use vertical glyph forms")
        expect(bracketGlyph.rotationDegrees == 0, "vertical bracket glyphs should not be sideways rotated")
        expect(
            VerticalTextTypesetter.glyph(for: "「", alphanumericOrientation: .sideways).text == "﹁",
            "opening corner bracket should keep the standard vertical bracket direction"
        )
        expect(
            VerticalTextTypesetter.glyph(for: "」", alphanumericOrientation: .sideways).text == "﹂",
            "closing corner bracket should keep the standard vertical bracket direction"
        )
        let openingDoubleQuoteGlyph = VerticalTextTypesetter.glyph(for: "“", alphanumericOrientation: .sideways)
        expect(
            openingDoubleQuoteGlyph.text == "〝",
            "opening double quote should use the standard Japanese double-minute glyph"
        )
        expect(
            openingDoubleQuoteGlyph.rotationDegrees == 90,
            "opening double quote should rotate sideways in vertical PDF"
        )
        let closingDoubleQuoteGlyph = VerticalTextTypesetter.glyph(for: "”", alphanumericOrientation: .sideways)
        expect(
            closingDoubleQuoteGlyph.text == "〟",
            "closing double quote should use the standard Japanese double-minute glyph"
        )
        expect(
            closingDoubleQuoteGlyph.rotationDegrees == 90,
            "closing double quote should rotate sideways in vertical PDF"
        )
        expect(
            VerticalTextTypesetter.glyph(for: "‘", alphanumericOrientation: .sideways).text == "‘",
            "opening single quote should keep its original glyph"
        )
        expect(
            VerticalTextTypesetter.glyph(for: "’", alphanumericOrientation: .sideways).text == "’",
            "closing single quote should keep its original glyph"
        )
        expect(
            VerticalTextTypesetter.cells(from: "\"PDF\"", alphanumericOrientation: .sideways).flatMap { $0 } == ["〝", "PDF", "〟"],
            "ASCII double quotes should become Japanese double-minute marks around PDF text"
        )
        expect(
            VerticalTextTypesetter.cells(from: "＂PDF＂", alphanumericOrientation: .sideways).flatMap { $0 } == ["〝", "PDF", "〟"],
            "full-width double quotes should become Japanese double-minute marks around PDF text"
        )

        expect(VerticalTextTypesetter.isLineStartProhibited("!"), "half-width exclamation mark should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineStartProhibited("ゃ"), "small kana should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineStartProhibited("」"), "closing brackets should be line-start prohibited")
        expect(VerticalTextTypesetter.isLineStartProhibited("”"), "closing double quote should be line-start prohibited")
        expect(!VerticalTextTypesetter.isLineStartProhibited("’"), "single quote should not receive special line-start handling")
        expect(VerticalTextTypesetter.isLineEndProhibited("「"), "opening brackets should be line-end prohibited")
        expect(VerticalTextTypesetter.isLineEndProhibited("“"), "opening double quote should be line-end prohibited")
        expect(!VerticalTextTypesetter.isLineEndProhibited("‘"), "single quote should not receive special line-end handling")

        let units = VerticalTextTypesetter
            .layoutUnits(from: "だ!?」", alphanumericOrientation: .sideways)
            .map(\.text)
        expect(units == ["だ", "!?", "」"], "!? should stay paired before a closing bracket")
        expect(VerticalTextTypesetter.formsNonBreakingPair("!?", "」"), "!? and closing quote should not split")
        expect(!VerticalTextTypesetter.isDashConnector("ー"), "long vowel mark should keep its font glyph instead of the connected dash path")

        let tocPageNumber = VerticalTextTypesetter.horizontalRun("10")
        let tocGlyph = VerticalTextTypesetter.glyph(for: tocPageNumber, alphanumericOrientation: .sideways)
        expect(tocGlyph.text == "10", "TOC page number marker should draw only the page number")
        expect(tocGlyph.rotationDegrees == 0, "TOC page number should be horizontal, not split into vertical digits")
        expect(VerticalTextTypesetter.cellCount(for: tocPageNumber, alphanumericOrientation: .sideways) == 1, "TOC page number should reserve one horizontal cell")

        expect(VerticalTextTypesetter.characterKind(for: "ぁ") == .smallKana, "small kana should have an explicit character kind")
        expect(VerticalTextTypesetter.characterKind(for: "、") == .punctuation, "punctuation should have an explicit character kind")
        expect(VerticalTextTypesetter.characterKind(for: "ー") == .longVowel, "long vowel mark should have an explicit character kind")
        expect(VerticalTextTypesetter.characterKind(for: "……") == .ellipsis, "ellipsis runs should have an explicit character kind")

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
