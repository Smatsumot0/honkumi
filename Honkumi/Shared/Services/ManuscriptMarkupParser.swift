import Foundation

enum ManuscriptMarkupParser {
    static let pageBreakTag = "[[PAGE_BREAK]]"
    static let tableOfContentsTag = "[[toc]]"
    static let chapterTagPrefix = "[[CHAPTER:"
    static let chapterTagSuffix = "]]"

    static func chapterTag(for title: String) -> String {
        "\(chapterTagPrefix) \(title.trimmingCharacters(in: .whitespacesAndNewlines))\(chapterTagSuffix)"
    }

    static func parse(_ body: String) -> ParsedManuscript {
        var segments: [ParsedManuscriptSegment] = []
        var currentText = ""
        var currentChapterTitle: String?
        var startsAfterPageBreak = false
        var didUseTableOfContentsTag = false

        for rawLine in body.components(separatedBy: .newlines) {
            var remainingLine = rawLine

            while let range = remainingLine.range(of: pageBreakTag) {
                currentText.append(String(remainingLine[..<range.lowerBound]))
                appendSegment(
                    text: currentText,
                    chapterTitle: currentChapterTitle,
                    startsAfterPageBreak: startsAfterPageBreak,
                    to: &segments
                )
                currentText = ""
                startsAfterPageBreak = true
                remainingLine = String(remainingLine[range.upperBound...])
            }

            if remainingLine.trimmingCharacters(in: .whitespacesAndNewlines) == tableOfContentsTag {
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendSegment(
                        text: currentText,
                        chapterTitle: currentChapterTitle,
                        startsAfterPageBreak: startsAfterPageBreak,
                        to: &segments
                    )
                    startsAfterPageBreak = false
                }

                currentText = ""
                if !didUseTableOfContentsTag {
                    segments.append(ParsedManuscriptSegment(
                        text: "",
                        chapterTitle: nil,
                        startsAfterPageBreak: startsAfterPageBreak,
                        isTableOfContentsPlaceholder: true
                    ))
                    didUseTableOfContentsTag = true
                    startsAfterPageBreak = false
                }
                continue
            }

            if let chapterTitle = chapterTitle(from: remainingLine) {
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendSegment(
                        text: currentText,
                        chapterTitle: currentChapterTitle,
                        startsAfterPageBreak: startsAfterPageBreak,
                        to: &segments
                    )
                    startsAfterPageBreak = false
                }
                currentText = ""
                currentChapterTitle = chapterTitle
                continue
            }

            if !remainingLine.isEmpty {
                currentText.append(remainingLine)
            }
            currentText.append("\n")
        }

        appendSegment(
            text: currentText,
            chapterTitle: currentChapterTitle,
            startsAfterPageBreak: startsAfterPageBreak,
            to: &segments
        )

        return ParsedManuscript(
            segments: segments.isEmpty ? [
                ParsedManuscriptSegment(text: "", chapterTitle: nil, startsAfterPageBreak: false)
            ] : segments
        )
    }

    static func printBody(from body: String) -> String {
        parse(body)
            .segments
            .map(\.text)
            .joined(separator: "\n")
    }

    static func characterCountBody(from body: String) -> String {
        var countedLines: [String] = []

        for rawLine in body.components(separatedBy: .newlines) {
            let lineWithoutPageBreaks = rawLine.replacingOccurrences(of: pageBreakTag, with: "")

            if lineWithoutPageBreaks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            if lineWithoutPageBreaks.trimmingCharacters(in: .whitespacesAndNewlines) == tableOfContentsTag {
                continue
            }

            if let chapterTitle = chapterTitle(from: lineWithoutPageBreaks) {
                countedLines.append(chapterTitle)
            } else {
                countedLines.append(lineWithoutPageBreaks)
            }
        }

        return countedLines.joined()
    }

    private static func chapterTitle(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLine.hasPrefix(chapterTagPrefix), trimmedLine.hasSuffix(chapterTagSuffix) {
            let start = trimmedLine.index(trimmedLine.startIndex, offsetBy: chapterTagPrefix.count)
            let end = trimmedLine.index(trimmedLine.endIndex, offsetBy: -chapterTagSuffix.count)
            let title = trimmedLine[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }

        guard trimmedLine.hasPrefix("# ") else { return nil }
        let title = trimmedLine.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func appendSegment(
        text: String,
        chapterTitle: String?,
        startsAfterPageBreak: Bool,
        to segments: inout [ParsedManuscriptSegment]
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty || startsAfterPageBreak || segments.isEmpty {
            segments.append(ParsedManuscriptSegment(
                text: trimmedText,
                chapterTitle: chapterTitle,
                startsAfterPageBreak: startsAfterPageBreak,
                isTableOfContentsPlaceholder: false
            ))
        }
    }
}

struct ParsedManuscript: Equatable {
    let segments: [ParsedManuscriptSegment]
}

struct ParsedManuscriptSegment: Equatable {
    let text: String
    let chapterTitle: String?
    let startsAfterPageBreak: Bool
    let isTableOfContentsPlaceholder: Bool

    init(
        text: String,
        chapterTitle: String?,
        startsAfterPageBreak: Bool,
        isTableOfContentsPlaceholder: Bool = false
    ) {
        self.text = text
        self.chapterTitle = chapterTitle
        self.startsAfterPageBreak = startsAfterPageBreak
        self.isTableOfContentsPlaceholder = isTableOfContentsPlaceholder
    }
}
