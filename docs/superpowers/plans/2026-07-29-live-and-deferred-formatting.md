# Live and Deferred Manuscript Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Format only the committed input area while the user types, defer settings-driven whole-manuscript formatting until the settings sheet closes, and keep long manuscripts editable while only the newest full-format result can be applied.

**Architecture:** Add a pure `ManuscriptLiveFormatter` that expands one committed edit into the smallest line/block range required by the existing rules and returns adjusted UTF-16 selection state. Move whole-manuscript work from `SettingsViewModel` into a workspace-owned `ManuscriptFormattingCoordinator` that serializes background requests, rejects stale snapshots, and queues one debounced retry after concurrent edits.

**Tech Stack:** Swift 6, SwiftUI, UIKit (`UITextViewDelegate`), Combine, XCTest, Xcode 26

## Global Constraints

- Minimum deployment target remains iOS 26.2.
- Do not add third-party dependencies or a UI-test target.
- `DocumentStore` remains the persistence source of truth.
- Do not format while `UITextView.markedTextRange` is non-`nil`; Japanese input is formatted only after conversion is committed.
- Keyboard input, deletion, paste, system replacement, and editor-toolbar insertion use the same local formatter.
- A committed input edit must not scan or format the complete manuscript.
- Settings changes persist immediately but do not modify the body until the active-work settings sheet closes.
- Whole-manuscript formatting runs off the MainActor, one synchronous formatter invocation at a time.
- The editor remains enabled while whole-manuscript formatting runs.
- Only the latest work/body/settings/Pro/generation snapshot may be written back.
- Switching works cancels the current work's pending retry and makes its running result ineligible.
- Remove whole-manuscript formatting from `textViewDidEndEditing`; hiding the keyboard alone must not start it.
- The workspace HUD copy is exactly `フォーマット中`.
- Preserve unrelated and currently untracked documents and scripts.
- New Swift files are automatically included by the existing File System Synchronized Groups; do not edit `project.pbxproj`.
- Do not run the all-paper-size or all-font-size sample PDF batches.
- Use RED/GREEN test cycles and commit every independently reviewable task.

---

### Task 1: Implement local-range formatting as a pure service

**Files:**

- Create: `Honkumi/Shared/Services/ManuscriptLiveFormatter.swift`
- Create: `HonkumiTests/ManuscriptLiveFormatterTests.swift`

**Interfaces:**

- Consumes: `ManuscriptFormatter.formatManuscriptText(_:settings:options:)`, a post-edit UTF-16 `changedRange`, and the post-edit `selectedRange`.
- Produces: `ManuscriptLiveFormattingResult(text:selectedRange:replacementRange:replacementText:)`.
- Produces: `ManuscriptLiveFormatter.format(_:changedRange:selectedRange:settings:options:)`.

- [ ] **Step 1: Write failing local-format tests**

Create `HonkumiTests/ManuscriptLiveFormatterTests.swift` with these cases:

```swift
@testable import Honkumi
import XCTest

final class ManuscriptLiveFormatterTests: XCTestCase {
    func testFormatsOnlyTheEditedLine() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true
        let input = "A,B.\n遠い行,."

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 0, length: 4),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "A、B。\n遠い行,.")
        XCTAssertEqual(result.selectedRange, NSRange(location: 4, length: 0))
        XCTAssertLessThan(
            result.replacementRange.length,
            (input as NSString).length
        )
    }

    func testMultiLinePasteFormatsAllPastedLinesButNotRemoteLines() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true
        settings.enableNormalizeBrackets = true
        let input = "遠い行,\nA,B.\n(C,D.)\n別の遠い行,"
        let changedRange = (input as NSString).range(
            of: "A,B.\n(C,D.)"
        )

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: changedRange,
            selectedRange: NSRange(
                location: NSMaxRange(changedRange),
                length: 0
            ),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(
            result.text,
            "遠い行,\nA、B。\n（C、D。）\n別の遠い行,"
        )
    }

    func testRemovingPeriodBeforeClosingBracketKeepsCursorAtCommittedInputBoundary() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableRemovePeriodsBeforeClosingBrackets = true

        let result = ManuscriptLiveFormatter.format(
            "「てすと。」",
            changedRange: NSRange(location: 4, length: 1),
            selectedRange: NSRange(location: 5, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "「てすと」")
        XCTAssertEqual(result.selectedRange, NSRange(location: 4, length: 0))
    }

    func testFormatsTheConnectedBlankLineBlockWithoutTouchingRemoteText() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeBlankLines = true
        settings.maxConsecutiveBlankLines = 1
        let input = "前\n\n\n\n後\n遠い行  "

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 3, length: 1),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "前\n\n後\n遠い行  ")
    }

    func testStructuralContextDoesNotApplyInlineRulesToBoundaryLines() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizeBlankLines = true
        settings.maxConsecutiveBlankLines = 1
        settings.enableTrimLineSpaces = true
        settings.enableNormalizePunctuation = true
        let input = "境界,  \n\n\n編集行"

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 8, length: 1),
            selectedRange: NSRange(location: 9, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, "境界,  \n\n編集行")
    }

    func testFormatsThePageBreakBoundaryBlock() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePageBreakSpacing = true
        let input = "前\n\n\n[[PAGE_BREAK]]\n\n\n後"

        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 4, length: 14),
            selectedRange: NSRange(location: 18, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "前\n\n[[PAGE_BREAK]]\n\n後")
    }

    func testDisabledAutoFormatReturnsTheOriginalValue() {
        let input = "A,B."
        let result = ManuscriptLiveFormatter.format(
            input,
            changedRange: NSRange(location: 1, length: 1),
            selectedRange: NSRange(location: 2, length: 0),
            settings: .default,
            options: FormatOptions(isPremiumUser: true)
        )

        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.selectedRange, NSRange(location: 2, length: 0))
    }

    func testPremiumRuleDoesNotRunForAFreeUser() {
        var settings = FormatSettings.default
        settings.enableAutoFormat = true
        settings.enableNormalizePunctuation = true

        let result = ManuscriptLiveFormatter.format(
            "A,B.",
            changedRange: NSRange(location: 0, length: 4),
            selectedRange: NSRange(location: 4, length: 0),
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        )

        XCTAssertEqual(result.text, "A,B.")
    }

}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptLiveFormatterTests test
```

Expected: compilation fails because `ManuscriptLiveFormatter` and `ManuscriptLiveFormattingResult` do not exist.

- [ ] **Step 3: Add the result type and local formatting entry point**

Create `Honkumi/Shared/Services/ManuscriptLiveFormatter.swift` with this public shape:

```swift
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
                    location: min(
                        max(changedRange.location, 0),
                        nsText.length
                    ),
                    length: 0
                ),
                replacementText: ""
            )
        }

        let safeChangedRange = clampedRange(changedRange, in: nsText)
        let editedLinesRange = nsText.lineRange(
            for: safeChangedRange
        )
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
        let originalEditedLines = nsOriginalSlice.substring(
            with: relativeEditedLinesRange
        )
        let formattedEditedLines =
            ManuscriptFormatter.formatManuscriptText(
                originalEditedLines,
                settings: inlineSettings(from: effectiveSettings),
                options: options
            )
        let inlineFormattedSlice =
            nsOriginalSlice.replacingCharacters(
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

        let formattedText = nsText.replacingCharacters(
            in: localRange,
            with: formattedSlice
        )
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

}
```

- [ ] **Step 4: Implement bounded line/block expansion**

Inside `ManuscriptLiveFormatter`, implement `formattingRange` so ordinary rules use all lines intersecting the committed change, while blank-line and page-break rules expand only through the connected structural block and include one boundary line on each side:

```swift
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
    if let previous = previousLineRange(
        before: editedLinesRange.location,
        in: text
    ), isStructuralLine(text.substring(with: previous)) {
        range = NSUnionRange(range, previous)
        didFindStructuralLine = true
    }
    if let next = nextLineRange(
        after: NSMaxRange(editedLinesRange),
        in: text
    ), isStructuralLine(text.substring(with: next)) {
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

private static func inlineSettings(
    from settings: FormatSettings
) -> FormatSettings {
    var inline = settings
    inline.enableNormalizeBlankLines = false
    inline.enableNormalizePageBreakSpacing = false
    return inline
}

private static func structuralSettings(
    from settings: FormatSettings
) -> FormatSettings {
    var structural = FormatSettings.default
    structural.enableAutoFormat = settings.enableAutoFormat
    structural.enableTrimLineSpaces = false
    structural.enableNormalizeBlankLines =
        settings.enableNormalizeBlankLines
    structural.maxConsecutiveBlankLines =
        settings.maxConsecutiveBlankLines
    structural.enableNormalizePageBreakSpacing =
        settings.enableNormalizePageBreakSpacing
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
```

The two one-line adjacency checks cover inserting or deleting a newline at the edge of a blank-line run without scanning unrelated nonblank lines.

- [ ] **Step 5: Move UTF-16 selection adjustment into the pure service**

Move the existing common-prefix/common-suffix logic from `ManuscriptTextEditor.Coordinator` into private `ManuscriptLiveFormatter` helpers. Map selection endpoints before, inside, and after `localRange` as follows:

```swift
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
```

`adjustedRange` must adjust both the selection start and end, clamp them to the new total UTF-16 length, and preserve a zero-length cursor as zero length. Reuse the exact three-region/common-prefix/common-suffix behavior currently in `ManuscriptTextEditor`.

Implement the remaining helpers as:

```swift
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
    return NSRange(
        location: safeStart,
        length: safeEnd - safeStart
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

private static func commonPrefixLength(
    _ lhs: NSString,
    _ rhs: NSString
) -> Int {
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
            with: NSRange(
                location: lhs.length - length - 1,
                length: 1
            )
          ) == rhs.substring(
            with: NSRange(
                location: rhs.length - length - 1,
                length: 1
            )
          ) {
        length += 1
    }
    return length
}

private static func clampedRange(
    _ range: NSRange,
    in text: NSString
) -> NSRange {
    let location = min(max(range.location, 0), text.length)
    return NSRange(
        location: location,
        length: min(
            max(range.length, 0),
            text.length - location
        )
    )
}
```

- [ ] **Step 6: Run local-format tests and the existing formatter suite**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptLiveFormatterTests \
  -only-testing:HonkumiTests/ManuscriptFormatterTests test
```

Expected: all local-format and existing rule tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add Honkumi/Shared/Services/ManuscriptLiveFormatter.swift \
  HonkumiTests/ManuscriptLiveFormatterTests.swift
git commit -m "Add local manuscript formatting"
```

---

### Task 2: Apply local formatting after committed UITextView edits

**Files:**

- Modify: `Honkumi/Shared/Components/ManuscriptTextEditor.swift`
- Modify: `Honkumi/Shared/Components/ManuscriptTextInsertion.swift`
- Modify: `HonkumiTests/ManuscriptLiveFormatterTests.swift`
- Modify: `HonkumiTests/ManuscriptTextInsertionTests.swift`

**Interfaces:**

- Consumes: Task 1's `ManuscriptLiveFormatter`.
- Produces: `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)` tracking of the post-edit range.
- Preserves: the current content offset unless the adjusted cursor is outside the visible region.

- [ ] **Step 1: Add range-tracking regression tests**

Add these tests to `ManuscriptLiveFormatterTests`:

```swift
func testDeletionRangeFallsBackToTheDeletionPoint() {
    XCTAssertEqual(
        ManuscriptLiveFormatter.postEditChangedRange(
            replacing: NSRange(location: 4, length: 3),
            with: ""
        ),
        NSRange(location: 4, length: 0)
    )
}

func testPasteRangeUsesReplacementUTF16Length() {
    XCTAssertEqual(
        ManuscriptLiveFormatter.postEditChangedRange(
            replacing: NSRange(location: 2, length: 1),
            with: "追記😀"
        ),
        NSRange(location: 2, length: 4)
    )
}
```

Add to `ManuscriptTextInsertionTests`:

```swift
func testInsertionReportsPostEditChangedRangeWithoutDiffingWholeText() {
    let body = "前😀後"
    let selection = NSRange(location: 3, length: 1)

    let result = ManuscriptTextInsertion.applying(
        "追記",
        to: body,
        replacing: selection
    )

    XCTAssertEqual(
        result.changedRange,
        NSRange(location: 3, length: 2)
    )
}

func testChapterMarkerReportsItsActualLineStartInsertionRange() {
    let body = "前の行\n章タイトル"
    let insertionPoint = (body as NSString).length

    let result = ManuscriptTextInsertion.applyingChapterTitleMarker(
        to: body,
        replacing: NSRange(location: insertionPoint, length: 0)
    )

    XCTAssertEqual(
        result.changedRange,
        NSRange(location: 4, length: 2)
    )
}
```

- [ ] **Step 2: Verify RED, then implement post-edit range calculation**

Run the Task 1 focused test command and expect failure because `postEditChangedRange` does not exist. Add:

```swift
static func postEditChangedRange(
    replacing range: NSRange,
    with replacementText: String
) -> NSRange {
    NSRange(
        location: max(range.location, 0),
        length: (replacementText as NSString).length
    )
}
```

Run the focused tests again and expect PASS.

- [ ] **Step 3: Make toolbar insertion return its exact changed range**

Add a property to `ManuscriptTextInsertionResult`:

```swift
let replacedRange: NSRange
let replacementText: String
let changedRange: NSRange
```

In `applying`, return:

```swift
return ManuscriptTextInsertionResult(
    text: updatedText,
    selectedRange: NSRange(
        location: cursorLocation,
        length: 0
    ),
    replacedRange: safeRange,
    replacementText: insertedText,
    changedRange: NSRange(
        location: safeRange.location,
        length: insertedLength
    )
)
```

In the line-start branch of `applyingChapterTitleMarker`, return:

```swift
return ManuscriptTextInsertionResult(
    text: updatedText,
    selectedRange: NSRange(
        location: safeRange.location + 2,
        length: 0
    ),
    replacedRange: NSRange(
        location: lineRange.location,
        length: 0
    ),
    replacementText: "# ",
    changedRange: NSRange(
        location: lineRange.location,
        length: 2
    )
)
```

The other chapter-marker branches delegate to `applying` and receive the correct range automatically. Run `ManuscriptTextInsertionTests` and expect PASS.

- [ ] **Step 4: Capture edits and skip marked-text callbacks**

In `ManuscriptTextEditor.Coordinator`, add:

```swift
private var pendingChangedRange: NSRange?
```

Implement:

```swift
func textView(
    _ textView: UITextView,
    shouldChangeTextIn range: NSRange,
    replacementText text: String
) -> Bool {
    pendingChangedRange = ManuscriptLiveFormatter.postEditChangedRange(
        replacing: range,
        with: text
    )
    return true
}
```

Replace `textViewDidChange` with:

```swift
func textViewDidChange(_ textView: UITextView) {
    guard !isApplyingTextChange else { return }
    guard textView.markedTextRange == nil else { return }

    let fallback = NSRange(
        location: textView.selectedRange.location,
        length: 0
    )
    let changedRange = pendingChangedRange ?? fallback
    pendingChangedRange = nil
    applyLiveFormatAndCommit(changedRange: changedRange, in: textView)
}
```

Keeping `pendingChangedRange` while marked text exists ensures all interim Japanese conversion callbacks leave the body untouched and the first committed callback performs one local format.

- [ ] **Step 5: Apply and commit local results without moving the viewport**

Add this coordinator helper:

```swift
private func applyLiveFormatAndCommit(
    changedRange: NSRange,
    in textView: UITextView
) {
    let originalText = textView.text ?? ""
    let originalSelection = textView.selectedRange
    let originalOffset = textView.contentOffset
    let result = ManuscriptLiveFormatter.format(
        originalText,
        changedRange: changedRange,
        selectedRange: originalSelection,
        settings: parent.formatSettings,
        options: parent.formatOptions
    )

    if result.text != originalText {
        let replacement = NSAttributedString(
            string: result.replacementText,
            attributes: textView.typingAttributes
        )
        isApplyingTextChange = true
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(
            in: result.replacementRange,
            with: replacement
        )
        textView.textStorage.endEditing()
        textView.selectedRange = result.selectedRange
        textView.setContentOffset(originalOffset, animated: false)
        isApplyingTextChange = false
    }

    parent.text = result.text
    parent.selectedRange = result.selectedRange
    if !isSelectionVisible(result.selectedRange, in: textView, verticalMargin: 20) {
        allowingAutomaticSelectionScrolling(in: textView) {
            revealSelectionIfNeeded(result.selectedRange, in: textView, savesOffset: true)
        }
    } else {
        textView.setContentOffset(originalOffset, animated: false)
        saveContentOffset(from: textView)
    }
}
```

Because the helper is nested inside `ManuscriptTextEditor`, it can call the parent's private style method. Keep `isApplyingTextChange` around all programmatic `UITextView` mutations so UIKit does not re-enter the formatter.

- [ ] **Step 6: Route toolbar insertions through the same formatter**

In `applyInsertionResult`, preserve the viewport and use the insertion service's exact changed range:

```swift
let originalOffset = textView.contentOffset
let replacement = NSAttributedString(
    string: result.replacementText,
    attributes: textView.typingAttributes
)

isApplyingTextChange = true
textView.textStorage.beginEditing()
textView.textStorage.replaceCharacters(
    in: result.replacedRange,
    with: replacement
)
textView.textStorage.endEditing()
textView.selectedRange = result.selectedRange
isApplyingTextChange = false
textView.setContentOffset(originalOffset, animated: false)

applyLiveFormatAndCommit(
    changedRange: result.changedRange,
    in: textView
)
```

This covers ordinary toolbar text, chapter-title insertion at line start, and page-break tag insertion with the same local rules.

- [ ] **Step 7: Remove formatting from end editing**

Replace `textViewDidEndEditing` with:

```swift
func textViewDidEndEditing(_ textView: UITextView) {
    parent.isEditing = false
    saveContentOffset(from: textView)
    guard textView.markedTextRange == nil else { return }
    commitTextChange(from: textView)
}
```

Delete `applyFormatIfNeeded`, `adjustedRange`, `adjustedLocation`, `commonPrefixLength`, and `commonSuffixLength` from the coordinator. Their selection responsibility now belongs to `ManuscriptLiveFormatter`.

- [ ] **Step 8: Synchronize an eligible full-format result while the editor is focused**

In `updateUIView`, keep the existing early return while `markedTextRange` exists, then replace the `!textView.isFirstResponder`-only synchronization with:

```swift
if textView.text != text {
    context.coordinator.applyExternalText(text, to: textView)
}
```

Add this coordinator method:

```swift
func applyExternalText(
    _ text: String,
    to textView: UITextView
) {
    guard textView.markedTextRange == nil,
          textView.text != text else { return }

    let preservedOffset = textView.contentOffset
    let preservedSelection = textView.selectedRange
    let safeSelection = parent.clampedRange(
        preservedSelection,
        in: text
    )

    pendingChangedRange = nil
    isApplyingTextChange = true
    textView.text = text
    needsFullStyleRefresh = true
    parent.applyEditorStyle(to: textView, coordinator: self)
    textView.selectedRange = safeSelection
    textView.setContentOffset(
        clampedContentOffset(preservedOffset, in: textView),
        animated: false
    )
    isApplyingTextChange = false

    parent.selectedRange = safeSelection
    saveContentOffset(from: textView)
}
```

This path runs once for an eligible full-format result. It does not run during Japanese marked text; that edit commits first, invalidates the old result, and the coordinator retries the latest body.

- [ ] **Step 9: Run editor-related tests and Debug build**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptLiveFormatterTests \
  -only-testing:HonkumiTests/ManuscriptTextInsertionTests \
  -only-testing:HonkumiTests/ManuscriptTextEditorNavigationTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: all focused tests pass and Debug builds.

- [ ] **Step 10: Commit Task 2**

```bash
git add Honkumi/Shared/Components/ManuscriptTextEditor.swift \
  Honkumi/Shared/Components/ManuscriptTextInsertion.swift \
  HonkumiTests/ManuscriptTextInsertionTests.swift \
  HonkumiTests/ManuscriptLiveFormatterTests.swift
git commit -m "Format committed editor input locally"
```

---

### Task 3: Define settings-dismissal formatting policy

**Files:**

- Create: `Honkumi/Shared/Services/ManuscriptFullFormattingTrigger.swift`
- Create: `HonkumiTests/ManuscriptFullFormattingTriggerTests.swift`
- Modify: `Honkumi/Features/Settings/SettingsViewModel.swift`
- Modify: `Honkumi/Features/Settings/SettingsView.swift`
- Modify: `HonkumiTests/SettingsFormatApplicationTests.swift`

**Interfaces:**

- Produces: `ManuscriptFormatSessionSnapshot(documentID:formatSettings:formatOptions:)`.
- Produces: `ManuscriptFullFormattingTrigger.shouldFormatAfterSettingsDismissal(initial:current:)`.
- Produces: `ManuscriptFullFormattingTrigger.shouldFormatAfterProUnlock(settings:)`.
- Removes: `SettingsViewModel`'s background format task and in-sheet progress state.

- [ ] **Step 1: Write the complete trigger matrix as failing tests**

Create `HonkumiTests/ManuscriptFullFormattingTriggerTests.swift`:

```swift
@testable import Honkumi
import XCTest

final class ManuscriptFullFormattingTriggerTests: XCTestCase {
    func testEnablingAutoFormatRequestsOneFullFormat() {
        var current = baseSnapshot
        current.formatSettings.enableAutoFormat = true
        XCTAssertTrue(trigger(initial: baseSnapshot, current: current))
    }

    func testEnablingAnActiveRuleRequestsFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        var current = initial
        current.formatSettings.enableNormalizePunctuation = true
        XCTAssertTrue(trigger(initial: initial, current: current))
    }

    func testChangingEnabledBlankLineLimitRequestsFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        initial.formatSettings.enableNormalizeBlankLines = true
        var current = initial
        current.formatSettings.maxConsecutiveBlankLines = 3
        XCTAssertTrue(trigger(initial: initial, current: current))
    }

    func testOnlyDisablingRulesDoesNotRequestFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableAutoFormat = true
        initial.formatSettings.enableNormalizePunctuation = true
        var current = initial
        current.formatSettings.enableNormalizePunctuation = false
        XCTAssertFalse(trigger(initial: initial, current: current))
    }

    func testClosingWithAutoFormatOffDoesNotRequestFullFormat() {
        var initial = baseSnapshot
        initial.formatSettings.enableNormalizePunctuation = false
        var current = initial
        current.formatSettings.enableNormalizePunctuation = true
        XCTAssertFalse(trigger(initial: initial, current: current))
    }

    func testUnchangedSettingsDoNotRequestFullFormat() {
        XCTAssertFalse(trigger(initial: baseSnapshot, current: baseSnapshot))
    }

    func testPaidUnlockRequestsFormattingOnlyWhenAnEnabledPremiumRuleExists() {
        var current = baseSnapshot
        current.formatSettings.enableAutoFormat = true
        current.formatSettings.enableNormalizePunctuation = true
        current.formatOptions = FormatOptions(isPremiumUser: true)
        XCTAssertTrue(trigger(initial: baseSnapshotWith(current, premium: false), current: current))

        current.formatSettings.enableNormalizePunctuation = false
        XCTAssertFalse(ManuscriptFullFormattingTrigger.shouldFormatAfterProUnlock(
            settings: current.formatSettings
        ))
    }

    private var baseSnapshot: ManuscriptFormatSessionSnapshot {
        ManuscriptFormatSessionSnapshot(
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            formatSettings: .default,
            formatOptions: FormatOptions(isPremiumUser: false)
        )
    }

    private func baseSnapshotWith(
        _ snapshot: ManuscriptFormatSessionSnapshot,
        premium: Bool
    ) -> ManuscriptFormatSessionSnapshot {
        ManuscriptFormatSessionSnapshot(
            documentID: snapshot.documentID,
            formatSettings: snapshot.formatSettings,
            formatOptions: FormatOptions(isPremiumUser: premium)
        )
    }

    private func trigger(
        initial: ManuscriptFormatSessionSnapshot,
        current: ManuscriptFormatSessionSnapshot
    ) -> Bool {
        ManuscriptFullFormattingTrigger.shouldFormatAfterSettingsDismissal(
            initial: initial,
            current: current
        )
    }
}
```

- [ ] **Step 2: Verify RED and implement the policy**

Run the new test class and expect undefined-type failures. Create `ManuscriptFullFormattingTrigger.swift` with:

```swift
import Foundation

nonisolated struct ManuscriptFormatSessionSnapshot: Equatable {
    let documentID: UUID
    var formatSettings: FormatSettings
    var formatOptions: FormatOptions
}

nonisolated enum ManuscriptFullFormattingTrigger {
    static func shouldFormatAfterSettingsDismissal(
        initial: ManuscriptFormatSessionSnapshot,
        current: ManuscriptFormatSessionSnapshot
    ) -> Bool {
        guard initial.documentID == current.documentID else { return false }
        let settings = current.formatSettings.validated
        guard settings.enableAutoFormat else { return false }
        if !initial.formatSettings.enableAutoFormat { return true }

        let enabledRuleWasAdded = ManuscriptFormatter.rules.contains {
            !initial.formatSettings[keyPath: $0.id] &&
                settings[keyPath: $0.id] &&
                (!$0.premium || current.formatOptions.isPremiumUser)
        }
        if enabledRuleWasAdded { return true }

        if initial.formatSettings.maxConsecutiveBlankLines != settings.maxConsecutiveBlankLines,
           settings.enableNormalizeBlankLines {
            return true
        }

        return !initial.formatOptions.isPremiumUser &&
            current.formatOptions.isPremiumUser &&
            shouldFormatAfterProUnlock(settings: settings)
    }

    static func shouldFormatAfterProUnlock(settings: FormatSettings) -> Bool {
        let settings = settings.validated
        guard settings.enableAutoFormat else { return false }
        return ManuscriptFormatter.premiumRules.contains {
            settings[keyPath: $0.id]
        }
    }
}
```

Run `ManuscriptFullFormattingTriggerTests` again and expect PASS.

- [ ] **Step 3: Remove immediate formatting from SettingsViewModel**

Delete these members from `SettingsViewModel`:

```swift
typealias FormatOperation
@Published private(set) var isApplyingFormat
private let formatOperation
private var formatTask
private var formatGeneration
```

Remove `formatOperation` from the initializer, remove `formatTask?.cancel()` from `deinit`, and remove `scheduleFormatApplication`, `invalidateFormatApplication`, `defaultFormatOperation`, and `shouldApplyEnabledPremiumFormatting`.

Keep the subscription-status publisher, but reduce its sink to:

```swift
.sink { [weak self] status in
    self?.subscriptionStatus = status
}
```

Make `updateFormatSettings` persistence-only:

```swift
func updateFormatSettings(_ changes: (inout FormatSettings) -> Void) {
    var updated = settings
    changes(&updated.formatSettings)
    settings = updated
}
```

- [ ] **Step 4: Replace old immediate-format tests with deferral tests**

In `SettingsFormatApplicationTests`, remove the controlled formatter and replace the old assertions with:

```swift
func testChangingFormatSettingsDoesNotModifyBodyInsideSettings() {
    var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
    document.settings.formatSettings.enableAutoFormat = true
    let store = makeStore(document: document, subscriptionStatus: .paid)
    let viewModel = SettingsViewModel(documentStore: store)

    viewModel.updateFormatRule(\.enableNormalizePunctuation, isEnabled: true)

    XCTAssertEqual(store.document.body, "A,B.")
    XCTAssertTrue(store.document.settings.formatSettings.enableNormalizePunctuation)
}

func testProUnlockPublishesStatusWithoutFormattingInsideSettings() async throws {
    var document = ManuscriptDocument(title: "Formatting", body: "A,B.")
    document.settings.formatSettings.enableAutoFormat = true
    document.settings.formatSettings.enableNormalizePunctuation = true
    let store = makeStore(document: document, subscriptionStatus: .free)
    let viewModel = SettingsViewModel(documentStore: store)

    store.setProUnlocked(true)

    try await waitUntil { viewModel.subscriptionStatus == .paid }
    XCTAssertEqual(store.document.body, "A,B.")
}
```

- [ ] **Step 5: Remove the in-sheet progress row**

Delete this block from `SettingsView.formatSettingsForm`:

```swift
if viewModel.isApplyingFormat {
    HStack(spacing: 10) {
        ProgressView()
        Text("本文にフォーマットを適用中…")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 6: Run trigger and settings regressions**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptFullFormattingTriggerTests \
  -only-testing:HonkumiTests/SettingsFormatApplicationTests \
  -only-testing:HonkumiTests/SettingsPrintSnapshotTests test
```

Expected: all selected tests pass and no settings test waits for body formatting.

- [ ] **Step 7: Commit Task 3**

```bash
git add Honkumi/Shared/Services/ManuscriptFullFormattingTrigger.swift \
  Honkumi/Features/Settings/SettingsViewModel.swift \
  Honkumi/Features/Settings/SettingsView.swift \
  HonkumiTests/ManuscriptFullFormattingTriggerTests.swift \
  HonkumiTests/SettingsFormatApplicationTests.swift
git commit -m "Defer settings-driven manuscript formatting"
```

---

### Task 4: Serialize whole-manuscript formatting in a coordinator

**Files:**

- Create: `Honkumi/Shared/Services/ManuscriptFormattingCoordinator.swift`
- Create: `HonkumiTests/ManuscriptFormattingCoordinatorTests.swift`

**Interfaces:**

- Consumes: Task 3's trigger policy and `DocumentStore`.
- Produces: `@MainActor ManuscriptFormattingCoordinator`.
- Produces: `requestFormatting()`, `settingsDidDismiss(initial:)`, `proDidUnlockOutsideSettings()`, and published `isFormatting`.
- Constructor injection: `formatOperation` and `editDebounce` for deterministic tests.

- [ ] **Step 1: Write failing serialization and stale-result tests**

Create `HonkumiTests/ManuscriptFormattingCoordinatorTests.swift` with the following tests; the complete `ControlledFormatter` and store helpers are defined later in this step:

```swift
@MainActor
func testRequestShowsProgressAndAppliesLatestEligibleResult() async throws {
    let store = makeStore(body: "A,B.", premium: true)
    let formatter = ControlledFormatter()
    let coordinator = ManuscriptFormattingCoordinator(
        documentStore: store,
        editDebounce: .zero,
        formatOperation: { text, _, _ in await formatter.format(text) }
    )

    coordinator.requestFormatting()
    try await waitUntil { await formatter.requestCount == 1 }
    XCTAssertTrue(coordinator.isFormatting)

    await formatter.resolveRequest(at: 0, with: "A、B。")
    try await waitUntil { store.document.body == "A、B。" }
    XCTAssertFalse(coordinator.isFormatting)
}

@MainActor
func testEditingDuringFormattingQueuesOnlyTheLatestBodyAfterTheRunningCall() async throws {
    let store = makeStore(body: "old", premium: true)
    let formatter = ControlledFormatter()
    let coordinator = ManuscriptFormattingCoordinator(
        documentStore: store,
        editDebounce: .zero,
        formatOperation: { text, _, _ in await formatter.format(text) }
    )

    coordinator.requestFormatting()
    try await waitUntil { await formatter.requestCount == 1 }
    store.updateBody("newest")
    try await Task.sleep(for: .milliseconds(20))
    let countBeforeCompletingFirst = await formatter.requestCount
    XCTAssertEqual(countBeforeCompletingFirst, 1)

    await formatter.resolveRequest(at: 0, with: "stale")
    try await waitUntil { await formatter.requestCount == 2 }
    let secondRequestText = await formatter.requestText(at: 1)
    XCTAssertEqual(secondRequestText, "newest")

    await formatter.resolveRequest(at: 1, with: "latest")
    try await waitUntil { store.document.body == "latest" }
    XCTAssertFalse(coordinator.isFormatting)
}

@MainActor
func testWorkSwitchRejectsRunningResultAndClearsProgress() async throws {
    let first = configuredDocument(title: "First", body: "first")
    let second = configuredDocument(title: "Second", body: "second")
    let store = makeStore(works: [first, second], activeID: first.id, premium: true)
    let formatter = ControlledFormatter()
    let coordinator = ManuscriptFormattingCoordinator(
        documentStore: store,
        editDebounce: .zero,
        formatOperation: { text, _, _ in await formatter.format(text) }
    )

    coordinator.requestFormatting()
    try await waitUntil { await formatter.requestCount == 1 }
    store.selectWork(id: second.id)
    XCTAssertFalse(coordinator.isFormatting)

    await formatter.resolveRequest(at: 0, with: "stale")
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(store.document.id, second.id)
    XCTAssertEqual(store.document.body, "second")
}
```

Add these two stale-snapshot tests to the same class:

```swift
@MainActor
func testSettingsMismatchPreventsWriteback() async throws {
    let store = makeStore(body: "original", premium: true)
    let formatter = ControlledFormatter()
    let coordinator = ManuscriptFormattingCoordinator(
        documentStore: store,
        editDebounce: .zero,
        formatOperation: { text, _, _ in await formatter.format(text) }
    )

    coordinator.requestFormatting()
    try await waitUntil { await formatter.requestCount == 1 }
    var changedSettings = store.document.settings
    changedSettings.formatSettings.enableNormalizeBrackets.toggle()
    store.updateSettings(changedSettings)

    await formatter.resolveRequest(at: 0, with: "stale settings")
    try await waitUntil { !coordinator.isFormatting }
    XCTAssertEqual(store.document.body, "original")
}

@MainActor
func testProMismatchPreventsWriteback() async throws {
    let store = makeStore(body: "original", premium: true)
    let formatter = ControlledFormatter()
    let coordinator = ManuscriptFormattingCoordinator(
        documentStore: store,
        editDebounce: .zero,
        formatOperation: { text, _, _ in await formatter.format(text) }
    )

    coordinator.requestFormatting()
    try await waitUntil { await formatter.requestCount == 1 }
    store.setProUnlocked(false)

    await formatter.resolveRequest(at: 0, with: "stale paid result")
    try await waitUntil { !coordinator.isFormatting }
    XCTAssertEqual(store.document.body, "original")
}
```

At the bottom of the test file, define the harness rather than referring to another test file:

```swift
private actor ControlledFormatter {
    private struct Request {
        let text: String
        let continuation: CheckedContinuation<String, Never>
    }
    private var requests: [Request] = []

    var requestCount: Int { requests.count }

    func requestText(at index: Int) -> String {
        requests[index].text
    }

    func format(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            requests.append(
                Request(text: text, continuation: continuation)
            )
        }
    }

    func resolveRequest(at index: Int, with result: String) {
        requests[index].continuation.resume(returning: result)
    }
}
```

Use these explicit test helpers inside the test class:

```swift
private func makeStore(
    body: String,
    premium: Bool
) -> DocumentStore {
    let document = configuredDocument(title: "Work", body: body)
    return makeStore(
        works: [document],
        activeID: document.id,
        premium: premium
    )
}

private func makeStore(
    works: [ManuscriptDocument],
    activeID: UUID,
    premium: Bool
) -> DocumentStore {
    DocumentStore(
        appData: AppData(
            version: AppData.currentVersion,
            categories: [.uncategorized],
            works: works,
            userDefaultSettings: .default,
            activeWorkId: activeID,
            subscriptionStatus: premium ? .paid : .free
        )
    )
}

private func configuredDocument(
    title: String,
    body: String
) -> ManuscriptDocument {
    var document = ManuscriptDocument(title: title, body: body)
    document.settings.formatSettings.enableAutoFormat = true
    return document
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping () async -> Bool
) async throws {
    let deadline = ContinuousClock().now.advanced(by: timeout)
    while !(await condition()) {
        guard ContinuousClock().now < deadline else {
            XCTFail("Timed out waiting for formatting condition")
            throw WaitError.timedOut
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private enum WaitError: Error {
    case timedOut
}
```

- [ ] **Step 2: Run the coordinator tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptFormattingCoordinatorTests test
```

Expected: compilation fails because `ManuscriptFormattingCoordinator` does not exist.

- [ ] **Step 3: Add the coordinator request model and injected operation**

Create `ManuscriptFormattingCoordinator.swift` with:

```swift
import Combine
import Foundation

@MainActor
final class ManuscriptFormattingCoordinator: ObservableObject {
    typealias FormatOperation = @Sendable (
        _ text: String,
        _ settings: FormatSettings,
        _ options: FormatOptions
    ) async -> String

    @Published private(set) var isFormatting = false

    private struct Request {
        let generation: Int
        let documentID: UUID
        let body: String
        let settings: FormatSettings
        let options: FormatOptions
    }

    private let documentStore: DocumentStore
    private let editDebounce: Duration
    private let formatOperation: FormatOperation
    private var cancellables = Set<AnyCancellable>()
    private var observedDocument: ManuscriptDocument
    private var generation = 0
    private var pendingRequest: Request?
    private var runningTask: Task<Void, Never>?
    private var editDebounceTask: Task<Void, Never>?
    private var isApplyingResult = false

    init(
        documentStore: DocumentStore,
        editDebounce: Duration = .milliseconds(250),
        formatOperation: @escaping FormatOperation =
            ManuscriptFormattingCoordinator.defaultFormatOperation
    ) {
        self.documentStore = documentStore
        self.editDebounce = editDebounce
        self.formatOperation = formatOperation
        self.observedDocument = documentStore.document

        documentStore.$document
            .dropFirst()
            .sink { [weak self] document in
                self?.documentDidChange(document)
            }
            .store(in: &cancellables)
    }

    deinit {
        runningTask?.cancel()
        editDebounceTask?.cancel()
    }
}
```

The default operation must use `Task.detached(priority: .userInitiated)` and call the existing full `ManuscriptFormatter`.

- [ ] **Step 4: Implement newest-only serial request execution**

Implement `requestFormatting` and the serial runner:

```swift
func requestFormatting() {
    let document = documentStore.document
    let settings = document.settings.validated.formatSettings
    guard settings.enableAutoFormat else {
        cancelPendingRequests()
        return
    }

    generation += 1
    pendingRequest = Request(
        generation: generation,
        documentID: document.id,
        body: document.body,
        settings: settings,
        options: FormatOptions(
            isPremiumUser: documentStore.subscriptionStatus == .paid
        )
    )
    isFormatting = true
    startNextRequestIfPossible()
}

private func startNextRequestIfPossible() {
    guard runningTask == nil, let request = pendingRequest else { return }
    pendingRequest = nil
    let operation = formatOperation
    runningTask = Task { [weak self] in
        let body = await operation(request.body, request.settings, request.options)
        self?.complete(request, formattedBody: body)
    }
}
```

`complete` must check all five snapshot fields before applying:

```swift
let current = documentStore.document
let currentOptions = FormatOptions(
    isPremiumUser: documentStore.subscriptionStatus == .paid
)
let canApply =
    request.generation == generation &&
    current.id == request.documentID &&
    current.body == request.body &&
    current.settings.validated.formatSettings == request.settings &&
    currentOptions == request.options
```

Implement completion and state refresh as:

```swift
private func complete(
    _ request: Request,
    formattedBody: String
) {
    let current = documentStore.document
    let currentOptions = FormatOptions(
        isPremiumUser: documentStore.subscriptionStatus == .paid
    )
    let canApply =
        request.generation == generation &&
        current.id == request.documentID &&
        current.body == request.body &&
        current.settings.validated.formatSettings == request.settings &&
        currentOptions == request.options

    if canApply, formattedBody != request.body {
        isApplyingResult = true
        documentStore.updateBody(formattedBody)
        isApplyingResult = false
    }

    runningTask = nil
    startNextRequestIfPossible()
    refreshFormattingState()
}

private func refreshFormattingState() {
    isFormatting =
        runningTask != nil ||
        pendingRequest != nil ||
        editDebounceTask != nil
}

private func cancelPendingRequests() {
    generation += 1
    pendingRequest = nil
    editDebounceTask?.cancel()
    editDebounceTask = nil
    isFormatting = false
}

nonisolated static func defaultFormatOperation(
    text: String,
    settings: FormatSettings,
    options: FormatOptions
) async -> String {
    await Task.detached(priority: .userInitiated) {
        ManuscriptFormatter.formatManuscriptText(
            text,
            settings: settings,
            options: options
        )
    }.value
}
```

- [ ] **Step 5: Invalidate and debounce edits without overlapping format calls**

In `documentDidChange`:

```swift
private func documentDidChange(_ document: ManuscriptDocument) {
    defer { observedDocument = document }

    guard document.id == observedDocument.id else {
        generation += 1
        pendingRequest = nil
        editDebounceTask?.cancel()
        editDebounceTask = nil
        isFormatting = false
        return
    }

    guard !isApplyingResult,
          isFormatting,
          document.body != observedDocument.body else {
        return
    }

    generation += 1
    pendingRequest = nil
    editDebounceTask?.cancel()
    editDebounceTask = Task { [weak self] in
        guard let self else { return }
        do {
            try await Task.sleep(for: editDebounce)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        self.editDebounceTask = nil
        self.requestFormatting()
    }
}
```

Do not clear `runningTask` when work or body changes: its detached synchronous formatter may still be executing. Its generation becomes stale, and a new pending request can start only after `complete` releases the running slot.

- [ ] **Step 6: Add settings and Pro entry points**

Implement:

```swift
func settingsDidDismiss(initial: ManuscriptFormatSessionSnapshot) {
    let document = documentStore.document
    let current = ManuscriptFormatSessionSnapshot(
        documentID: document.id,
        formatSettings: document.settings.formatSettings,
        formatOptions: FormatOptions(
            isPremiumUser: documentStore.subscriptionStatus == .paid
        )
    )
    guard ManuscriptFullFormattingTrigger.shouldFormatAfterSettingsDismissal(
        initial: initial,
        current: current
    ) else { return }
    requestFormatting()
}

func proDidUnlockOutsideSettings() {
    guard ManuscriptFullFormattingTrigger.shouldFormatAfterProUnlock(
        settings: documentStore.document.settings.formatSettings
    ) else { return }
    requestFormatting()
}
```

- [ ] **Step 7: Run all coordinator tests**

Run the Step 2 command again.

Expected: all serialization, stale-result, work-switch, settings-mismatch, and Pro-mismatch tests pass.

- [ ] **Step 8: Commit Task 4**

```bash
git add Honkumi/Shared/Services/ManuscriptFormattingCoordinator.swift \
  HonkumiTests/ManuscriptFormattingCoordinatorTests.swift
git commit -m "Coordinate deferred manuscript formatting"
```

---

### Task 5: Trigger formatting when settings closes and show workspace progress

**Files:**

- Modify: `Honkumi/ContentView.swift`
- Create: `HonkumiTests/ContentFormattingSessionTests.swift`

**Interfaces:**

- Consumes: Task 4's coordinator.
- Produces: one active-work format-session snapshot captured when the settings sheet opens.
- Produces: a centered nonblocking HUD in `WorkspaceView`.

- [ ] **Step 1: Add session-capture tests around the pure snapshot**

Create `HonkumiTests/ContentFormattingSessionTests.swift`:

```swift
@testable import Honkumi
import XCTest

final class ContentFormattingSessionTests: XCTestCase {
    func testSnapshotCapturesWorkSettingsAndEntitlementAtOpenTime() {
        var document = ManuscriptDocument(title: "Work", body: "本文")
        document.settings.formatSettings.enableAutoFormat = true
        let snapshot = ManuscriptFormatSessionSnapshot(
            documentID: document.id,
            formatSettings: document.settings.formatSettings,
            formatOptions: FormatOptions(isPremiumUser: false)
        )

        document.settings.formatSettings.enableNormalizePunctuation = true

        XCTAssertFalse(snapshot.formatSettings.enableNormalizePunctuation)
        XCTAssertFalse(snapshot.formatOptions.isPremiumUser)
    }
}
```

Run it and expect PASS after Task 3. This is a regression guard before view integration.

- [ ] **Step 2: Own one coordinator for the ContentView lifetime**

Add:

```swift
@StateObject private var manuscriptFormattingCoordinator: ManuscriptFormattingCoordinator
@State private var activeFormatSettingsSession: ManuscriptFormatSessionSnapshot?
```

Replace the synthesized initializer with:

```swift
init(
    documentStore: DocumentStore,
    proStore: HonkumiProStore,
    pdfExportAdService: PDFExportAdService
) {
    _documentStore = ObservedObject(wrappedValue: documentStore)
    _proStore = ObservedObject(wrappedValue: proStore)
    self.pdfExportAdService = pdfExportAdService
    _manuscriptFormattingCoordinator = StateObject(
        wrappedValue: ManuscriptFormattingCoordinator(documentStore: documentStore)
    )
}
```

Pass the coordinator into `WorkspaceView`.

- [ ] **Step 3: Capture and close active-work settings sessions**

Add a `ContentView` change handler:

```swift
.onChange(of: presentedSettingsScope?.id) { oldScopeID, newScopeID in
    if newScopeID == SettingsViewModel.Scope.activeWork.id {
        let document = documentStore.document
        activeFormatSettingsSession = ManuscriptFormatSessionSnapshot(
            documentID: document.id,
            formatSettings: document.settings.formatSettings,
            formatOptions: FormatOptions(
                isPremiumUser: documentStore.subscriptionStatus == .paid
            )
        )
    }

    if oldScopeID == SettingsViewModel.Scope.activeWork.id,
       newScopeID == nil,
       let session = activeFormatSettingsSession {
        activeFormatSettingsSession = nil
        manuscriptFormattingCoordinator.settingsDidDismiss(initial: session)
    }
}
```

The format request therefore starts only after the sheet's item becomes `nil`, when the workspace is visible again.

- [ ] **Step 4: Route Pro unlocks according to settings visibility**

Add one entitlement synchronization method:

```swift
private func synchronizeProEntitlement(
    _ entitlementState: ProEntitlementState
) {
    let previousStatus = documentStore.subscriptionStatus
    documentStore.setProUnlocked(
        entitlementState.isProUnlocked
    )
    pdfExportAdService.updateEntitlementState(entitlementState)

    if previousStatus == .free,
       documentStore.subscriptionStatus == .paid,
       presentedSettingsScope?.id !=
        SettingsViewModel.Scope.activeWork.id {
        manuscriptFormattingCoordinator
            .proDidUnlockOutsideSettings()
    }
}
```

Call it from both existing lifecycle routes:

```swift
.task {
    proStore.start()
    synchronizeProEntitlement(proStore.entitlementState)
    await proStore.refreshPurchasedStatus()
    synchronizeProEntitlement(proStore.entitlementState)
    if !ProcessInfo.processInfo.isRunningXCTest {
        Task(priority: .utility) {
            await pdfExportAdService.prepareForAppLaunch()
        }
    }
}
.onChange(of: proStore.entitlementState) {
    _, entitlementState in
    synchronizeProEntitlement(entitlementState)
    if !ProcessInfo.processInfo.isRunningXCTest {
        Task(priority: .utility) {
            await pdfExportAdService.preloadAdIfEligible()
        }
    }
}
```

Delete the duplicated direct `setProUnlocked` and `updateEntitlementState` calls from those two routes. Whichever route first changes the store from free to paid requests formatting; the other sees `previousStatus == .paid` and cannot duplicate it. This also covers restored paid entitlement while the library is visible. If purchase finishes inside active-work settings, the open-time snapshot records the free state and the dismissal trigger handles it once.

- [ ] **Step 5: Show a nonblocking centered workspace HUD**

Add the coordinator property to `WorkspaceView`:

```swift
@ObservedObject var manuscriptFormattingCoordinator: ManuscriptFormattingCoordinator
```

Attach this overlay to the outer workspace `VStack`:

```swift
.overlay {
    if manuscriptFormattingCoordinator.isFormatting {
        VStack(spacing: 10) {
            ProgressView()
            Text("フォーマット中")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("フォーマット中")
    }
}
```

Do not disable `EditorView`, section tabs, or toolbar buttons.

- [ ] **Step 6: Run formatting integration tests and build**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptLiveFormatterTests \
  -only-testing:HonkumiTests/ManuscriptFullFormattingTriggerTests \
  -only-testing:HonkumiTests/ManuscriptFormattingCoordinatorTests \
  -only-testing:HonkumiTests/SettingsFormatApplicationTests \
  -only-testing:HonkumiTests/ContentFormattingSessionTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: focused tests pass and Debug builds with no `SettingsViewModel.isApplyingFormat` reference.

- [ ] **Step 7: Commit Task 5**

```bash
git add Honkumi/ContentView.swift \
  HonkumiTests/ContentFormattingSessionTests.swift
git commit -m "Run deferred formatting after settings closes"
```

---

### Task 6: Verify IME, performance boundaries, and all build configurations

**Files:**

- No source changes expected.
- Modify only files from Tasks 1–5 if a reproducible regression is found.

**Interfaces:**

- Verifies the approved user-visible behavior and release build matrix.

- [ ] **Step 1: Run the complete XCTest suite**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build Debug, Staging, and Release**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all three builds succeed.

- [ ] **Step 3: Manually verify committed Japanese input and toolbar routes**

On the booted iPhone 17 Pro simulator:

1. Open a work containing at least 50,000 characters.
2. Enable auto-format plus punctuation, brackets, ellipsis, dash, exclamation/question spacing, and closing-bracket period removal.
3. Type `「てすと。」` with the Japanese keyboard and verify no replacement occurs while the candidate/marked text is active.
4. Commit the candidate and verify the line becomes `「てすと」` with the cursor kept immediately before `」`.
5. Paste `A,B...` into a different line and verify only that line becomes `A、B……`.
6. Insert the page-break tag from the editor toolbar and verify only its adjacent blank-line block is normalized.
7. Scroll far from the edited line, edit locally, and verify remote text and the visible scroll position remain unchanged.

- [ ] **Step 4: Manually verify deferred full formatting**

1. Open active-work settings on the 50,000-character work.
2. Change several formatting settings and verify the settings UI remains responsive and the body is unchanged while the sheet is open.
3. Close settings and verify the workspace shows centered `フォーマット中`.
4. Type while the HUD is visible; verify typing remains responsive, the old result is not applied, and one latest retry completes.
5. Reopen settings, only turn a rule off, close, and verify the HUD does not appear.
6. Reopen settings, turn auto-format off, close, and verify the body is unchanged.
7. Start formatting, return to the library, open another work, and verify the first work's result never overwrites the second.

- [ ] **Step 5: Record final evidence**

Save the focused-test command, complete-suite result, three build results, and manual-check outcomes in the implementation handoff. Do not generate the all-paper-size or all-font-size PDF sample batches.
