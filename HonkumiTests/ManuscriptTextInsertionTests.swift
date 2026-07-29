import XCTest
@testable import Honkumi

final class ManuscriptTextInsertionTests: XCTestCase {
    func testInsertionUsesCurrentEditorSnapshotInsteadOfShorterStoredBody() {
        let storedBody = "ホームの向こうから来る電車を見ながら、今度こそ、自分の言葉で何かを選ぼう"
        let currentEditorText = storedBody + "と思った。"
        let insertionPoint = (currentEditorText as NSString).length

        let result = ManuscriptTextInsertion.applying(
            "# ",
            to: currentEditorText,
            replacing: NSRange(location: insertionPoint, length: 0)
        )

        XCTAssertEqual(result.text, currentEditorText + "# ")
        XCTAssertEqual(result.selectedRange, NSRange(location: insertionPoint + 2, length: 0))
    }

    func testInsertionPlacesCursorInsidePairedCharactersAfterReplacingSelection() {
        let body = "私は雨のあとを歩いた。"
        let selection = (body as NSString).range(of: "雨")

        let result = ManuscriptTextInsertion.applying(
            "「」",
            to: body,
            replacing: selection,
            cursorOffsetFromEnd: 1
        )

        XCTAssertEqual(result.text, "私は「」のあとを歩いた。")
        XCTAssertEqual(result.selectedRange, NSRange(location: selection.location + 1, length: 0))
    }

    func testChapterTitleMarkerAtLineEndPrefixesCurrentLine() {
        let body = "雨は上がった。\n駅へ続く道"
        let insertionPoint = (body as NSString).length

        let result = ManuscriptTextInsertion.applyingChapterTitleMarker(
            to: body,
            replacing: NSRange(location: insertionPoint, length: 0)
        )

        XCTAssertEqual(result.text, "雨は上がった。\n# 駅へ続く道")
        XCTAssertEqual(result.selectedRange, NSRange(location: insertionPoint + 2, length: 0))
    }

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
}
