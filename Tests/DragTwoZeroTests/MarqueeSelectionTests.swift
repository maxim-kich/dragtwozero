import XCTest
@testable import DragTwoZero

final class MarqueeSelectionTests: XCTestCase {
    private func block(_ text: String, _ rect: CGRect) -> CaptureCandidate {
        CaptureCandidate(payload: .init(title: text, markdown: text), frame: rect)
    }
    func testPartialOverlapAndExactEdgeContactSelectWholeBlock() {
        let item = block("whole paragraph", CGRect(x: 100, y: 100, width: 200, height: 80))
        for rect in [CGRect(x: 90, y: 110, width: 11, height: 1),
                     CGRect(x: 90, y: 110, width: 10, height: 1)] {
            XCTAssertEqual(selectedBlocks([item], in: rect).first?.payload.text, "whole paragraph")
        }
        XCTAssertTrue(selectedBlocks([item], in: CGRect(x: 90, y: 110, width: 9, height: 1)).isEmpty)
    }
    func testReverseDragAndShrinkingRemoveBlocks() {
        let first = block("one", CGRect(x: 10, y: 10, width: 80, height: 20))
        let second = block("two", CGRect(x: 10, y: 50, width: 80, height: 20))
        let large = selectionRect(from: CGPoint(x: 100, y: 80), to: .zero)
        XCTAssertEqual(selectedBlocks([first, second], in: large).count, 2)
        XCTAssertEqual(selectedBlocks([first, second], in: CGRect(x: 0, y: 0, width: 100, height: 35)).map { $0.payload.text }, ["one"])
    }
    func testNestedLinkIsNotDuplicatedAndBlocksKeepReadingOrder() {
        let paragraph = block("Hello [link](https://example.com)", CGRect(x: 10, y: 10, width: 200, height: 40))
        let link = block("[link](https://example.com)", CGRect(x: 70, y: 20, width: 30, height: 10))
        let next = block("Next paragraph", CGRect(x: 10, y: 80, width: 200, height: 40))
        let selected = selectedBlocks([next, link, paragraph, paragraph], in: CGRect(x: 0, y: 0, width: 300, height: 150))
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(combinedSelection(selected)?.payload.text, "Hello [link](https://example.com)\n\nNext paragraph")
        XCTAssertEqual(combinedSelection(selected)?.frame, CGRect(x: 10, y: 10, width: 200, height: 110))
    }
    func testShortcutReleaseWaitsForSelectionThenStartsHeldMouseDrag() {
        var state = CaptureState()
        state.modifiers(held: true); state.select()
        state.modifiers(held: false)
        XCTAssertEqual(state.phase, .selecting)
        XCTAssertFalse(state.drop(valid: true))
        state.finishSelection(mouseDown: true)
        XCTAssertEqual(state.phase, .dragging)
        XCTAssertTrue(state.drop(valid: true))
    }
    func testMouseFirstReleaseLeavesBlockReadyToGrab() {
        var state = CaptureState()
        state.modifiers(held: true); state.select(); state.finishSelection(mouseDown: false)
        state.modifiers(held: true)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.drop(valid: true))
        state.begin()
        XCTAssertTrue(state.drop(valid: true))
    }
    func testCancelSelectionCannotBecomeDrag() {
        var state = CaptureState()
        state.modifiers(held: true); state.select(); state.cancel()
        state.finishSelection(mouseDown: true)
        XCTAssertEqual(state.phase, .locked)
        XCTAssertNil(combinedSelection([]))
    }
}
