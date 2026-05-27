import Foundation

struct FormatRule: Identifiable, Equatable {
    let id: WritableKeyPath<FormatSettings, Bool>
    let label: String
    let description: String
    let premium: Bool
}

enum ManuscriptFormatter {
    static let freeRules: [FormatRule] = [
        FormatRule(
            id: \.enableIndent,
            label: "段落先頭の字下げ",
            description: "段落先頭に全角スペースを入れます。空行や、すでに字下げ済みの行は変更しません。",
            premium: false
        ),
        FormatRule(
            id: \.enableNormalizeBlankLines,
            label: "連続空行の整理",
            description: "連続した空行を指定した行数までに制限します。",
            premium: false
        ),
        FormatRule(
            id: \.enableTrimLineSpaces,
            label: "半角スペースの整理",
            description: "各行の行頭・行末にある不要な半角スペースだけを削除します。",
            premium: false
        ),
        FormatRule(
            id: \.enableNormalizePageBreakSpacing,
            label: "改ページタグの整理",
            description: "\(ManuscriptMarkupParser.pageBreakTag) の前後に多すぎる空行がある場合だけ整えます。",
            premium: false
        )
    ]

    static let premiumRules: [FormatRule] = [
        FormatRule(
            id: \.enableNormalizeEllipsis,
            label: "三点リーダーの整形",
            description: "…、・・・、... を小説向けの …… に整えます。",
            premium: true
        ),
        FormatRule(
            id: \.enableNormalizeDash,
            label: "ダッシュの整形",
            description: "— や ー の連続を ―― に整えます。",
            premium: true
        ),
        FormatRule(
            id: \.enableSpaceAfterExclamationQuestion,
            label: "感嘆符・疑問符後のスペース補正",
            description: "！ や ？ の後に全角スペースを入れます。直後が閉じ括弧の場合は変更しません。",
            premium: true
        ),
        FormatRule(
            id: \.enableNormalizePunctuation,
            label: "句読点の統一",
            description: "半角の , と . を 、 と 。 に変換します。",
            premium: true
        ),
        FormatRule(
            id: \.enableNormalizeBrackets,
            label: "括弧の統一",
            description: "半角括弧 () を全角括弧 （） に変換します。",
            premium: true
        )
    ]

    static var rules: [FormatRule] {
        freeRules + premiumRules
    }

    static func formatManuscriptText(
        _ text: String,
        settings: FormatSettings,
        options: FormatOptions
    ) -> String {
        let effectiveSettings = settings.validated
        var formatted = text

        if effectiveSettings.enableTrimLineSpaces {
            formatted = trimLineSpaces(formatted)
        }

        if effectiveSettings.enableIndent {
            formatted = indentParagraphs(
                formatted,
                skipsOpeningQuote: effectiveSettings.skipIndentBeforeOpeningQuote
            )
        }

        if effectiveSettings.enableNormalizeBlankLines {
            formatted = normalizeBlankLines(
                formatted,
                maxConsecutiveBlankLines: effectiveSettings.maxConsecutiveBlankLines
            )
        }

        if effectiveSettings.enableNormalizePageBreakSpacing {
            formatted = normalizePageBreakSpacing(formatted)
        }

        guard options.isPremiumUser else {
            return formatted
        }

        if effectiveSettings.enableNormalizeEllipsis {
            formatted = normalizeEllipsis(formatted)
        }

        if effectiveSettings.enableNormalizeDash {
            formatted = normalizeDash(formatted)
        }

        if effectiveSettings.enableSpaceAfterExclamationQuestion {
            formatted = normalizeSpaceAfterExclamationQuestion(formatted)
        }

        if effectiveSettings.enableNormalizePunctuation {
            formatted = normalizePunctuation(formatted)
        }

        if effectiveSettings.enableNormalizeBrackets {
            formatted = normalizeBrackets(formatted)
        }

        return formatted
    }

    private static func trimLineSpaces(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " "))
            }
            .joined(separator: "\n")
    }

    private static func indentParagraphs(_ text: String, skipsOpeningQuote: Bool) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let line = String(line)
                guard !line.isEmpty else { return line }
                guard !line.hasPrefix("　") else { return line }
                guard !line.isMarkupOnlyLine else { return line }
                if skipsOpeningQuote, line.hasPrefix("「") || line.hasPrefix("『") {
                    return line
                }
                return "　" + line
            }
            .joined(separator: "\n")
    }

    private static func normalizeBlankLines(_ text: String, maxConsecutiveBlankLines: Int) -> String {
        let maxBlankLines = max(maxConsecutiveBlankLines, 0)
        var blankLineCount = 0
        var normalizedLines: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankLineCount += 1
                if blankLineCount <= maxBlankLines {
                    normalizedLines.append(line)
                }
            } else {
                blankLineCount = 0
                normalizedLines.append(line)
            }
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func normalizePageBreakSpacing(_ text: String) -> String {
        let pageBreakTag = ManuscriptMarkupParser.pageBreakTag
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var normalizedLines: [String] = []

        for line in lines {
            let isPageBreak = line.trimmingCharacters(in: .whitespaces) == pageBreakTag
            if isPageBreak {
                while normalizedLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    normalizedLines.removeLast()
                }
                if !normalizedLines.isEmpty {
                    normalizedLines.append("")
                }
                normalizedLines.append(pageBreakTag)
                normalizedLines.append("")
                continue
            }

            if normalizedLines.last == "",
               normalizedLines.dropLast().last == pageBreakTag,
               line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            normalizedLines.append(line)
        }

        while normalizedLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true,
              normalizedLines.dropLast().last == pageBreakTag {
            normalizedLines.removeLast()
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func normalizeEllipsis(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(\.{3}|・{3}|…+)"#, with: "……", options: .regularExpression)
    }

    private static func normalizeDash(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[—ー―]{2,}"#, with: "――", options: .regularExpression)
    }

    private static func normalizeSpaceAfterExclamationQuestion(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"([！？])(?=[^！？」』）\]\n　\s])"#,
            with: "$1　",
            options: .regularExpression
        )
    }

    private static func normalizePunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: ",", with: "、")
            .replacingOccurrences(of: ".", with: "。")
    }

    private static func normalizeBrackets(_ text: String) -> String {
        text
            .replacingOccurrences(of: "(", with: "（")
            .replacingOccurrences(of: ")", with: "）")
    }
}

extension String {
    fileprivate var isMarkupOnlyLine: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed == ManuscriptMarkupParser.pageBreakTag
            || trimmed == ManuscriptMarkupParser.tableOfContentsTag
            || (trimmed.hasPrefix(ManuscriptMarkupParser.chapterTagPrefix)
                && trimmed.hasSuffix(ManuscriptMarkupParser.chapterTagSuffix))
            || trimmed.hasPrefix("# ")
    }
}
