import AppKit
import XCTest
@testable import DragTwoZero

final class EditorParagraphReceiptTests: XCTestCase {
    typealias Text = EditorParagraphReceipt.Text
    typealias Boundary = EditorParagraphReceipt.Boundary

    func testRenderedMarkdownRequiresExactAttributeBackedTextAndAnUnstyledBeforeState() {
        let before = EditorParagraphReceipt.Before(state: .init(location: 3, length: 0, value: "QA end"), plainBeforeMarkup: true)
        XCTAssertTrue(before.confirms("**bold**", text: "QA boldend", markup: "QA **bold**end"))
        for markup: String? in [nil, "QA boldend", "QA *bold*end", "QA **bold**end extra"] {
            XCTAssertFalse(before.confirms("**bold**", text: "QA boldend", markup: markup))
        }
        let styledBefore = EditorParagraphReceipt.Before(state: before.state, plainBeforeMarkup: false)
        XCTAssertFalse(styledBefore.confirms("**bold**", text: "QA boldend", markup: "QA **bold**end"))
        XCTAssertTrue(styledBefore.confirms("plain", text: "QA plainend", markup: nil))
    }

    func testRoundedBlankLineBoundsRemainParagraphsButInlineGroupsDoNot() {
        // Measured T3 first line, second line, blank line and final line.
        let frames = [CGRect(x: 427, y: 745, width: 702, height: 23),
                      CGRect(x: 427, y: 768, width: 702, height: 23),
                      CGRect(x: 427, y: 791, width: 702, height: 23),
                      CGRect(x: 427, y: 813, width: 702, height: 23)]
        for pair in zip(frames, frames.dropFirst()) { XCTAssertTrue(EditorParagraphReceipt.follows(pair.1, pair.0)) }
        XCTAssertFalse(EditorParagraphReceipt.follows(frames[0].offsetBy(dx: 100, dy: 0), frames[0]))
        XCTAssertFalse(EditorParagraphReceipt.follows(frames[0].offsetBy(dx: 0, dy: 10), frames[0]))
        XCTAssertFalse(EditorParagraphReceipt.follows(CGRect(x: 10, y: 0, width: 10, height: 0.5),
                                                     CGRect(x: 0, y: 0, width: 10, height: 0.5)))
    }

    func testEmptyLayoutParagraphIsNotARealNewline() throws {
        let blank = Text(body: "", marker: "\n")
        let caret = Boundary(paragraph: 0, prefix: "", suffix: "\n")
        let before = try XCTUnwrap(EditorParagraphReceipt.insertionState([blank], start: caret, end: caret))
        XCTAssertEqual(before.value, "")
        XCTAssertTrue(before.confirmsInsertion(of: "QA é 🐈", observed: "QA é 🐈"))
        let twoLines = try XCTUnwrap(EditorParagraphReceipt.insertionState([blank, blank], start: caret, end: caret))
        XCTAssertEqual(twoLines.value, "\n")
        XCTAssertFalse(twoLines.confirmsInsertion(of: "QA", observed: "QA"))
        XCTAssertTrue(twoLines.confirmsInsertion(of: "QA", observed: "QA\n"))
    }

    func testActualMarkerParagraphFixesLegacyIndexThatOmitsLineSeparators() throws {
        let blocks = [Text(body: "FIRST", marker: "FIRST"), Text(body: "LAST", marker: "LAST")]
        let caret = Boundary(paragraph: 1, prefix: "", suffix: "LAST")
        let before = try XCTUnwrap(EditorParagraphReceipt.insertionState(blocks, start: caret, end: caret))
        XCTAssertEqual(before.location, 6)
        XCTAssertEqual(before.value, "FIRST\nLAST")
        XCTAssertTrue(before.confirmsInsertion(of: "QA", observed: "FIRST\nQALAST"))
        XCTAssertFalse(before.confirmsInsertion(of: "QA", observed: "FIRSTQA\nLAST"))
    }

    func testBlankLinesSpacesAndUnicodeRemainExact() throws {
        let blocks = [Text(body: "FIRST", marker: "FIRST"), Text(body: "", marker: "\n"), Text(body: "LAST", marker: "LAST")]
        let caret = Boundary(paragraph: 1, prefix: "", suffix: "\n")
        let before = try XCTUnwrap(EditorParagraphReceipt.insertionState(blocks, start: caret, end: caret))
        let payload = "Two  spaces\n\n🐈 é"
        XCTAssertTrue(before.confirmsInsertion(of: payload, observed: "FIRST\n"+payload+"\nLAST"))
        for after in ["FIRST"+payload+"LAST", "FIRST\nTwo spaces\n\n🐈 é\nLAST", "FIRST\nTwo  spaces\n🐈 é\nLAST",
                      "FIRST\nTwo  spaces\n\n🐈 é\nLAST", "FIRST\n"+payload+"\nLAST extra", before.value] {
            XCTAssertFalse(before.confirmsInsertion(of: payload, observed: after))
        }
    }

    func testExplicitSelectionAcrossParagraphsAndListPrefix() throws {
        let blocks = [Text(body: "AB", marker: "AB"), Text(body: "CD", marker: "CD", prefix: "• ")]
        let first = Boundary(paragraph: 0, prefix: "A", suffix: "B")
        let last = Boundary(paragraph: 1, prefix: "C", suffix: "D")
        let before = try XCTUnwrap(EditorParagraphReceipt.insertionState(blocks, start: first, end: last))
        XCTAssertEqual(before.replacingSelection(with: "QA"), "AQAD")
        let insideItem = try XCTUnwrap(EditorParagraphReceipt.insertionState(blocks, start: last, end: last))
        XCTAssertTrue(insideItem.confirmsInsertion(of: "QA", observed: "AB\n• CQAD"))
        XCTAssertFalse(insideItem.confirmsInsertion(of: "QA", observed: "AB\nCQAD"))
    }

    func testUnreadableIncompleteForeignOrSplitUnicodeBoundariesReject() {
        let good = Text(body: "A🐈B", marker: "A🐈B")
        let caret = Boundary(paragraph: 0, prefix: "A", suffix: "🐈B")
        for boundary in [Boundary(paragraph: 1, prefix: "", suffix: ""),
                         .init(paragraph: -1, prefix: "", suffix: ""),
                         .init(paragraph: 0, prefix: "A", suffix: "B"),
                         .init(paragraph: 0, prefix: "A🐈", suffix: "extraB")] {
            XCTAssertNil(EditorParagraphReceipt.insertionState([good], start: boundary, end: caret))
        }
        XCTAssertNil(EditorParagraphReceipt.insertionState([], start: caret, end: caret))
        XCTAssertNil(EditorParagraphReceipt.insertionState([.init(body: "A", marker: "omitted A")], start: caret, end: caret))
        let attachment = Text(body: "\u{FFFC}", marker: "\u{FFFC}")
        let attachmentCaret = Boundary(paragraph: 0, prefix: "", suffix: "\u{FFFC}")
        XCTAssertNil(EditorParagraphReceipt.insertionState([attachment], start: attachmentCaret, end: attachmentCaret))
        let reversed = Boundary(paragraph: 0, prefix: "A🐈B", suffix: "")
        XCTAssertNil(EditorParagraphReceipt.insertionState([good], start: reversed, end: caret))
    }

    private func marker(_ byte: UInt8) -> AXTextMarker {
        let bytes = [byte, 0, 1, 2]
        return bytes.withUnsafeBytes { AXTextMarkerCreate(kCFAllocatorDefault, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), $0.count) }
    }
    private func range(_ byte: UInt8) -> AXTextMarkerRange {
        AXTextMarkerRangeCreate(kCFAllocatorDefault, marker(byte), marker(byte+1))
    }
    func testOriginalMarkerSelectionIsPreservedAndCannotBeReauthorizedByAnEqualLegacyIndex() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100), point = CGPoint(x: 10, y: 10)
        let element = AXUIElementCreateApplication(100)
        var original = InputTarget(element: element, app: .current, frame: frame, dropPoint: point,
            insertionRange: .init(location: 0, length: 0), caretFrame: .zero,
            context: .init(window: element, document: nil, documentURL: nil), selectionValue: "A\nB", selectionMarkers: range(1))
        var changed = original
        changed.selectionMarkers = range(3)
        XCTAssertFalse(original.matchesAuthorizedTarget(changed, at: point))
        changed.selectionMarkers = nil
        XCTAssertFalse(original.matchesAuthorizedTarget(changed, at: point))
        changed.selectionMarkers = range(3)
        let preserved = changed.preservingSelection(from: original)
        XCTAssertTrue(SelectedTextMarkers.sameRange(preserved.selectionMarkers, original.selectionMarkers))
        XCTAssertTrue(original.matchesAuthorizedTarget(preserved, at: point))
        original.selectionMarkers = nil; changed.selectionMarkers = nil
        XCTAssertTrue(original.matchesAuthorizedTarget(changed, at: point), "Non-marker native editors retain their exact legacy guards")
    }
    func testChangedOwnerRangeTextOrLayoutCannotBeAStableReceipt() {
        let node = AXUIElementCreateApplication(100)
        let text = Text(body: "é", marker: "é")
        let frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        func snapshot(owner: AXUIElement = AXUIElementCreateApplication(100), text: Text = Text(body: "é", marker: "é"),
                      value: String = "é", markerText: String = "é", frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 20),
                      range: AXTextMarkerRange? = nil, paragraphRange: AXTextMarkerRange? = nil) -> EditorParagraphReceipt.Snapshot {
            .init(value: value, range: range ?? self.range(1), markerText: markerText,
                  paragraphs: [.init(element: owner, range: paragraphRange ?? self.range(5), text: text, frame: frame)])
        }
        let first = snapshot(owner: node, text: text, frame: frame)
        XCTAssertTrue(EditorParagraphReceipt.same(first, snapshot()))
        for second in [snapshot(owner: AXUIElementCreateApplication(101)), snapshot(value: "é"),
                       snapshot(markerText: "é"), snapshot(text: .init(body: "é", marker: "é")),
                       snapshot(frame: frame.offsetBy(dx: 1, dy: 0)), snapshot(range: range(2)), snapshot(paragraphRange: range(6))] {
            XCTAssertFalse(EditorParagraphReceipt.same(first, second))
        }
        let plain = snapshot(text: .init(body: "é", marker: "é", markup: "é"))
        let styled = snapshot(text: .init(body: "é", marker: "é", markup: "**é**"))
        XCTAssertTrue(EditorParagraphReceipt.same(plain, styled), "Optional font metadata cannot invalidate complete plain text")
        XCTAssertNil(EditorParagraphReceipt.stableMarkup(plain, styled))
        XCTAssertEqual(EditorParagraphReceipt.stableMarkup(plain, plain), "é")
    }
}
