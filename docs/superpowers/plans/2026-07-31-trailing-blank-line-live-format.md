# Trailing Blank Line Live Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve one permitted blank line at the end of the manuscript while automatic blank-line formatting is active.

**Architecture:** Keep blank-line semantics in the shared `ManuscriptFormatter` so local live formatting and whole-manuscript formatting remain consistent. Treat the final empty split component created by a trailing newline as the active editing line, while continuing to count and limit every completed blank line before it.

**Tech Stack:** Swift, Foundation, XCTest, XcodeBuild

## Global Constraints

- With a blank-line limit of 1, `本文\n\n` remains unchanged and `本文\n\n\n` becomes `本文\n\n`.
- With a blank-line limit of 0, `本文\n` remains unchanged so the cursor can stay on the next editing line.
- Blank lines in the middle of the manuscript keep their existing limit behavior.
- Automatic formatting disabled behavior, page-break spacing, settings UI, persistence, and PDF-specific trailing-line policy do not change.
- Do not modify or stage unrelated existing worktree changes.

---

### Task 1: Preserve the trailing editing line during blank-line normalization

**Files:**
- Modify: `HonkumiTests/ManuscriptFormatterTests.swift:4-76`
- Modify: `HonkumiTests/ManuscriptLiveFormatterTests.swift:60-97`
- Modify: `Honkumi/Shared/Services/ManuscriptFormatter.swift:175-193`

**Interfaces:**
- Consumes: `ManuscriptFormatter.formatManuscriptText(_:settings:options:)` and `ManuscriptLiveFormatter.format(_:changedRange:selectedRange:settings:options:)`.
- Produces: unchanged formatter interfaces with corrected end-of-manuscript blank-line behavior.

- [x] **Step 1: Add failing shared-formatter regression tests**

Add these tests to `ManuscriptFormatterTests`:

```swift
func testBlankLineLimitPreservesTrailingEditingLineAfterAllowedBlankLine() {
    var settings = FormatSettings.default
    settings.enableAutoFormat = true
    settings.enableNormalizeBlankLines = true
    settings.maxConsecutiveBlankLines = 1

    XCTAssertEqual(
        ManuscriptFormatter.formatManuscriptText(
            "本文\n\n",
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        ),
        "本文\n\n"
    )
}

func testBlankLineLimitRemovesOverflowBeforeTrailingEditingLine() {
    var settings = FormatSettings.default
    settings.enableAutoFormat = true
    settings.enableNormalizeBlankLines = true
    settings.maxConsecutiveBlankLines = 1

    XCTAssertEqual(
        ManuscriptFormatter.formatManuscriptText(
            "本文\n\n\n",
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        ),
        "本文\n\n"
    )
}

func testZeroBlankLineLimitPreservesTrailingEditingLine() {
    var settings = FormatSettings.default
    settings.enableAutoFormat = true
    settings.enableNormalizeBlankLines = true
    settings.maxConsecutiveBlankLines = 0

    XCTAssertEqual(
        ManuscriptFormatter.formatManuscriptText(
            "本文\n",
            settings: settings,
            options: FormatOptions(isPremiumUser: false)
        ),
        "本文\n"
    )
}
```

The first test catches the current bug. The overflow and zero-limit tests prevent a fix that disables the upper bound or removes the active editing line.

- [x] **Step 2: Add the failing live-formatter regression test**

Add this test beside the existing blank-line block test in `ManuscriptLiveFormatterTests`:

```swift
func testTrailingBlankLineAtLimitKeepsSecondNewlineAndCursorAtEnd() {
    var settings = FormatSettings.default
    settings.enableAutoFormat = true
    settings.enableNormalizeBlankLines = true
    settings.maxConsecutiveBlankLines = 1

    let result = ManuscriptLiveFormatter.format(
        "本文\n\n",
        changedRange: NSRange(location: 3, length: 1),
        selectedRange: NSRange(location: 4, length: 0),
        settings: settings,
        options: FormatOptions(isPremiumUser: false)
    )

    XCTAssertEqual(result.text, "本文\n\n")
    XCTAssertEqual(result.selectedRange, NSRange(location: 4, length: 0))
}
```

This exercises the real post-edit formatter path with literal UTF-16 ranges for the second newline and the caret.

- [x] **Step 3: Run the focused tests and verify RED**

Run:

```bash
xcodebuild \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/ManuscriptFormatterTests \
  -only-testing:HonkumiTests/ManuscriptLiveFormatterTests test
```

Expected: `testBlankLineLimitPreservesTrailingEditingLineAfterAllowedBlankLine` and `testTrailingBlankLineAtLimitKeepsSecondNewlineAndCursorAtEnd` fail because `本文\n\n` is currently reduced to `本文\n`; the cursor assertion also reports location 3 instead of 4. Existing tests remain green.

- [x] **Step 4: Implement the minimal shared formatter fix**

Replace the loop setup in `normalizeBlankLines(_:maxConsecutiveBlankLines:)` with the following structure:

```swift
let lines = text
    .split(separator: "\n", omittingEmptySubsequences: false)
    .map(String.init)

for (index, line) in lines.enumerated() {
    let isTrailingEditingLine = text.hasSuffix("\n") && index == lines.count - 1
    if isTrailingEditingLine {
        normalizedLines.append(line)
    } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
        blankLineCount += 1
        if blankLineCount <= maxBlankLines {
            normalizedLines.append(line)
        }
    } else {
        blankLineCount = 0
        normalizedLines.append(line)
    }
}
```

Do not add a live-formatter-only condition. The final component is kept without incrementing `blankLineCount`; completed blank lines before it remain limited normally.

- [x] **Step 5: Run the focused tests and verify GREEN**

Run the same focused `xcodebuild` command from Step 3.

Expected: all `ManuscriptFormatterTests` and `ManuscriptLiveFormatterTests` pass with no failures.

- [x] **Step 6: Run the complete regression suite**

Run:

```bash
xcodebuild \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: the entire `HonkumiTests` suite passes. If an unrelated pre-existing failure appears, record its exact test name and confirm the focused formatter suite still passes.

- [x] **Step 7: Inspect the scoped diff and commit the fix**

Run:

```bash
git diff --check -- \
  Honkumi/Shared/Services/ManuscriptFormatter.swift \
  HonkumiTests/ManuscriptFormatterTests.swift \
  HonkumiTests/ManuscriptLiveFormatterTests.swift
git diff -- \
  Honkumi/Shared/Services/ManuscriptFormatter.swift \
  HonkumiTests/ManuscriptFormatterTests.swift \
  HonkumiTests/ManuscriptLiveFormatterTests.swift
git add \
  Honkumi/Shared/Services/ManuscriptFormatter.swift \
  HonkumiTests/ManuscriptFormatterTests.swift \
  HonkumiTests/ManuscriptLiveFormatterTests.swift \
  docs/superpowers/plans/2026-07-31-trailing-blank-line-live-format.md
git commit -m "Fix trailing blank line live formatting"
```

Expected: only the shared formatter, the two formatter test files, and this implementation plan are included in the commit.
