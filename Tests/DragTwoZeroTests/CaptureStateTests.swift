import XCTest
@testable import DragTwoZero

final class CaptureStateTests: XCTestCase {
    func testMouseFirstReadySelectionClearsOnShortcutRelease() {
        var state = CaptureState()
        state.modifiers(held: true); state.select(); state.finishSelection(mouseDown: false)
        XCTAssertEqual(state.phase, .ready)
        state.modifiers(held: false)
        XCTAssertEqual(state.phase, .idle)
        state.begin()
        XCTAssertFalse(state.drop(valid: true))
    }

    func testPendingDeliveryObservesReleaseAndAllowsFreshShortcutImmediately() {
        var state = CaptureState()
        state.modifiers(held: true); state.begin()
        XCTAssertTrue(state.drop(valid: true))
        XCTAssertFalse(state.retryDuringDelivery(held: true))
        XCTAssertFalse(state.retryDuringDelivery(held: false))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.retryDuringDelivery(held: true))
        state.modifiers(held: true)
        XCTAssertEqual(state.phase, .armed)
    }

    func testReleaseBeforeMouseUpDoesNotLeaveFailedPasteLocked() {
        var state = CaptureState()
        state.modifiers(held: true); state.begin()
        state.modifiers(held: false)
        XCTAssertTrue(state.drop(valid: true))
        state.modifiers(held: false)
        XCTAssertTrue(state.retryDuringDelivery(held: true))
        state.modifiers(held: true)
        XCTAssertEqual(state.phase, .armed)
    }

    func testDisablingMultiselectKeepsSingleBlockDragAvailable() {
        var state = CaptureState()
        state.modifiers(held: true)
        state.select(enabled: false)
        XCTAssertEqual(state.phase, .armed)
        state.begin()
        XCTAssertEqual(state.phase, .dragging)
    }
    func testEnabledMultiselectStartsSelection() {
        var state = CaptureState()
        state.modifiers(held: true)
        state.select(enabled: true)
        XCTAssertEqual(state.phase, .selecting)
    }
    func testValidDropLocksUntilShortcutReleased() {
        var state = CaptureState()
        state.modifiers(held: true); state.begin()
        XCTAssertTrue(state.drop(valid: true))
        state.modifiers(held: true)
        XCTAssertEqual(state.phase, .locked)
        state.modifiers(held: false); state.modifiers(held: true)
        XCTAssertEqual(state.phase, .armed)
    }
    func testShortcutReleaseDuringDragKeepsMouseCapture() {
        var state = CaptureState()
        state.modifiers(held: true); state.begin(); state.modifiers(held: false)
        XCTAssertEqual(state.phase, .dragging)
        XCTAssertTrue(state.drop(valid: true))
        state.modifiers(held: false)
        XCTAssertEqual(state.phase, .idle)
    }
    func testShortcutReleaseBeforeMouseDownCancelsArming() {
        var state = CaptureState()
        state.modifiers(held: true); state.modifiers(held: false); state.begin()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.drop(valid: true))
    }
    func testEscapeAfterShortcutReleaseStillCancelsDrag() {
        var state = CaptureState()
        state.modifiers(held: true); state.begin(); state.modifiers(held: false)
        state.cancel(); state.modifiers(held: false)
        XCTAssertFalse(state.drop(valid: true))
        state.modifiers(held: true)
        XCTAssertEqual(state.phase, .armed)
    }
    func testEscapeAndOutsideDropCancel() {
        for escape in [true, false] {
            var state = CaptureState()
            state.modifiers(held: true); state.begin()
            if escape { state.cancel() } else { XCTAssertFalse(state.drop(valid: false)) }
            XCTAssertFalse(state.drop(valid: true))
            state.modifiers(held: true)
            XCTAssertEqual(state.phase, .locked)
        }
    }
    func testMouseReleaseWithoutCaptureCannotDeliver() {
        var state = CaptureState()
        state.modifiers(held: true)
        XCTAssertFalse(state.drop(valid: true))
    }
    func testLinkSerializationPreservesDestination() {
        let url = URL(string: "https://example.com/item?id=1")!
        XCTAssertEqual(CapturePayload(title: "Card", url: url).text, "[Card](https://example.com/item?id=1)")
        XCTAssertEqual(CapturePayload(title: "", url: url).text, url.absoluteString)
    }
}
