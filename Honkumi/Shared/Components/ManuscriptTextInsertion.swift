import Foundation

nonisolated struct ManuscriptTextInsertionResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

nonisolated enum ManuscriptTextInsertion {
    static func applying(
        _ insertedText: String,
        to currentText: String,
        replacing selectedRange: NSRange,
        cursorOffsetFromEnd: Int = 0
    ) -> ManuscriptTextInsertionResult {
        let nsText = currentText as NSString
        let safeRange = clampedRange(selectedRange, in: nsText)
        let updatedText = nsText.replacingCharacters(in: safeRange, with: insertedText)
        let insertedLength = (insertedText as NSString).length
        let cursorLocation = safeRange.location + max(insertedLength - cursorOffsetFromEnd, 0)

        return ManuscriptTextInsertionResult(
            text: updatedText,
            selectedRange: NSRange(location: cursorLocation, length: 0)
        )
    }

    static func applyingChapterTitleMarker(
        to currentText: String,
        replacing selectedRange: NSRange
    ) -> ManuscriptTextInsertionResult {
        let nsText = currentText as NSString
        let safeRange = clampedRange(selectedRange, in: nsText)
        guard safeRange.length == 0 else {
            return applying("# ", to: currentText, replacing: safeRange)
        }

        let lineRange = nsText.lineRange(for: NSRange(location: safeRange.location, length: 0))
        let lineEnd = lineContentEnd(in: nsText, lineRange: lineRange)
        guard safeRange.location == lineEnd else {
            return applying("# ", to: currentText, replacing: safeRange)
        }

        let updatedText = nsText.replacingCharacters(
            in: NSRange(location: lineRange.location, length: 0),
            with: "# "
        )
        return ManuscriptTextInsertionResult(
            text: updatedText,
            selectedRange: NSRange(location: safeRange.location + 2, length: 0)
        )
    }

    private static func clampedRange(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        let remainingLength = text.length - location
        let length = min(max(range.length, 0), remainingLength)
        return NSRange(location: location, length: length)
    }

    private static func lineContentEnd(in text: NSString, lineRange: NSRange) -> Int {
        var location = lineRange.location + lineRange.length
        while location > lineRange.location {
            let previousCharacter = text.substring(with: NSRange(location: location - 1, length: 1))
            guard previousCharacter == "\n" || previousCharacter == "\r" else { break }
            location -= 1
        }
        return location
    }
}
