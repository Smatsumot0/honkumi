import Foundation

nonisolated struct ManuscriptLiveFormattingResult: Equatable {
    let text: String
    let selectedRange: NSRange
    let replacementRange: NSRange
    let replacementText: String
}

nonisolated enum ManuscriptLiveFormatter {
    static func format(
        _ text: String,
        changedRange: NSRange,
        selectedRange: NSRange,
        settings: FormatSettings,
        options: FormatOptions
    ) -> ManuscriptLiveFormattingResult {
        let effectiveSettings = settings.validated
        let nsText = text as NSString
        let safeSelection = clampedRange(selectedRange, in: nsText)
        guard effectiveSettings.enableAutoFormat, nsText.length > 0 else {
            return ManuscriptLiveFormattingResult(
                text: text,
                selectedRange: safeSelection,
                replacementRange: NSRange(
                    location: min(max(changedRange.location, 0), nsText.length),
                    length: 0
                ),
                replacementText: ""
            )
        }

        let safeChangedRange = clampedRange(changedRange, in: nsText)
        let editedLinesRange = nsText.lineRange(for: safeChangedRange)
        let localRange = formattingRange(
            in: nsText,
            editedLinesRange: editedLinesRange,
            settings: effectiveSettings
        )
        let originalSlice = nsText.substring(with: localRange)
        let relativeEditedLinesRange = NSRange(
            location: editedLinesRange.location - localRange.location,
            length: editedLinesRange.length
        )
        let nsOriginalSlice = originalSlice as NSString
        let originalEditedLines = nsOriginalSlice.substring(with: relativeEditedLinesRange)
        let formattedEditedLines = ManuscriptFormatter.formatManuscriptText(
            originalEditedLines,
            settings: inlineSettings(from: effectiveSettings),
            options: options
        )
        let inlineFormattedSlice = nsOriginalSlice.replacingCharacters(
            in: relativeEditedLinesRange,
            with: formattedEditedLines
        )
        let formattedSlice = ManuscriptFormatter.formatManuscriptText(
            inlineFormattedSlice,
            settings: structuralSettings(from: effectiveSettings),
            options: options
        )

        guard formattedSlice != originalSlice else {
            return ManuscriptLiveFormattingResult(
                text: text,
                selectedRange: safeSelection,
                replacementRange: localRange,
                replacementText: originalSlice
            )
        }

        let formattedText = nsText.replacingCharacters(in: localRange, with: formattedSlice)
        return ManuscriptLiveFormattingResult(
            text: formattedText,
            selectedRange: adjustedRange(
                safeSelection,
                replacing: localRange,
                originalSlice: originalSlice,
                formattedSlice: formattedSlice,
                formattedTextLength: (formattedText as NSString).length
            ),
            replacementRange: localRange,
            replacementText: formattedSlice
        )
    }

    private static func formattingRange(
        in text: NSString,
        editedLinesRange: NSRange,
        settings: FormatSettings
    ) -> NSRange {
        var range = editedLinesRange
        let needsStructuralContext =
            settings.enableNormalizeBlankLines ||
            settings.enableNormalizePageBreakSpacing
        guard needsStructuralContext else { return range }

        var didFindStructuralLine = isStructuralLine(text.substring(with: range))
        if let previous = previousLineRange(before: editedLinesRange.location, in: text),
           isStructuralLine(text.substring(with: previous)) {
            range = NSUnionRange(range, previous)
            didFindStructuralLine = true
        }
        if let next = nextLineRange(after: NSMaxRange(editedLinesRange), in: text),
           isStructuralLine(text.substring(with: next)) {
            range = NSUnionRange(range, next)
            didFindStructuralLine = true
        }

        while let previous = previousLineRange(before: range.location, in: text),
              isStructuralLine(text.substring(with: previous)) {
            range = NSUnionRange(range, previous)
            didFindStructuralLine = true
        }
        while let next = nextLineRange(after: NSMaxRange(range), in: text),
              isStructuralLine(text.substring(with: next)) {
            range = NSUnionRange(range, next)
            didFindStructuralLine = true
        }

        guard didFindStructuralLine else { return range }
        if let previous = previousLineRange(before: range.location, in: text) {
            range = NSUnionRange(range, previous)
        }
        if let next = nextLineRange(after: NSMaxRange(range), in: text) {
            range = NSUnionRange(range, next)
        }
        return range
    }

    private static func inlineSettings(from settings: FormatSettings) -> FormatSettings {
        var inline = settings
        inline.enableNormalizeBlankLines = false
        inline.enableNormalizePageBreakSpacing = false
        return inline
    }

    private static func structuralSettings(from settings: FormatSettings) -> FormatSettings {
        var structural = FormatSettings.default
        structural.enableAutoFormat = settings.enableAutoFormat
        structural.enableTrimLineSpaces = false
        structural.enableNormalizeBlankLines = settings.enableNormalizeBlankLines
        structural.maxConsecutiveBlankLines = settings.maxConsecutiveBlankLines
        structural.enableNormalizePageBreakSpacing = settings.enableNormalizePageBreakSpacing
        structural.enableNormalizeConsecutiveExclamationQuestion = false
        return structural
    }

    private static func isStructuralLine(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == ManuscriptMarkupParser.pageBreakTag
    }

    private static func previousLineRange(before location: Int, in text: NSString) -> NSRange? {
        guard location > 0 else { return nil }
        return text.lineRange(for: NSRange(location: location - 1, length: 0))
    }

    private static func nextLineRange(after location: Int, in text: NSString) -> NSRange? {
        guard location < text.length else { return nil }
        return text.lineRange(for: NSRange(location: location, length: 0))
    }

    private static func adjustedRange(
        _ range: NSRange,
        replacing replacementRange: NSRange,
        originalSlice: String,
        formattedSlice: String,
        formattedTextLength: Int
    ) -> NSRange {
        let start = adjustedLocation(
            range.location,
            replacing: replacementRange,
            originalSlice: originalSlice,
            formattedSlice: formattedSlice
        )
        let end = adjustedLocation(
            NSMaxRange(range),
            replacing: replacementRange,
            originalSlice: originalSlice,
            formattedSlice: formattedSlice
        )
        let safeStart = min(max(start, 0), formattedTextLength)
        let safeEnd = min(max(end, safeStart), formattedTextLength)
        return NSRange(location: safeStart, length: safeEnd - safeStart)
    }

    private static func adjustedLocation(
        _ location: Int,
        replacing range: NSRange,
        originalSlice: String,
        formattedSlice: String
    ) -> Int {
        if location <= range.location { return location }
        if location >= NSMaxRange(range) {
            return location + (formattedSlice as NSString).length - range.length
        }

        let relativeLocation = location - range.location
        return range.location + adjustedLocation(
            relativeLocation,
            from: originalSlice as NSString,
            to: formattedSlice as NSString
        )
    }

    private static func adjustedLocation(
        _ location: Int,
        from original: NSString,
        to formatted: NSString
    ) -> Int {
        let safeLocation = min(max(location, 0), original.length)
        let prefix = commonPrefixLength(original, formatted)
        let suffix = commonSuffixLength(
            original,
            formatted,
            commonPrefixLength: prefix
        )
        let originalChangedEnd = original.length - suffix
        let formattedChangedEnd = formatted.length - suffix
        if safeLocation <= prefix { return safeLocation }
        if safeLocation >= originalChangedEnd {
            return safeLocation + formattedChangedEnd - originalChangedEnd
        }
        return formattedChangedEnd
    }

    private static func commonPrefixLength(_ lhs: NSString, _ rhs: NSString) -> Int {
        let limit = min(lhs.length, rhs.length)
        var index = 0
        while index < limit,
              lhs.substring(with: NSRange(location: index, length: 1)) ==
                rhs.substring(with: NSRange(location: index, length: 1)) {
            index += 1
        }
        return index
    }

    private static func commonSuffixLength(
        _ lhs: NSString,
        _ rhs: NSString,
        commonPrefixLength: Int
    ) -> Int {
        var length = 0
        while lhs.length - length > commonPrefixLength,
              rhs.length - length > commonPrefixLength,
              lhs.substring(
                with: NSRange(location: lhs.length - length - 1, length: 1)
              ) == rhs.substring(
                with: NSRange(location: rhs.length - length - 1, length: 1)
              ) {
            length += 1
        }
        return length
    }

    private static func clampedRange(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        return NSRange(
            location: location,
            length: min(max(range.length, 0), text.length - location)
        )
    }
}
