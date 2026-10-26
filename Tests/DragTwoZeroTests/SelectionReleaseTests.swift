import XCTest
@testable import DragTwoZero

/// Pure release decisions: no application, windows, input events or haptics.
final class SelectionReleaseTests: XCTestCase {
    private var highlighted: [CaptureCandidate] {
        [CaptureCandidate(payload: .init(title: "First", markdown: "First"),
                          frame: CGRect(x: 100, y: 100, width: 200, height: 40)),
         CaptureCandidate(payload: .init(title: "Second", markdown: "Second"),
                          frame: CGRect(x: 100, y: 180, width: 200, height: 40))]
    }

    func testShortcutReleaseStartsWithExactlyHighlightedMembersDespiteIncompleteScan() {
        var state = CaptureState()
        state.modifiers(held: true); state.select()
        guard case let .captured(capture) = SelectionReleaseResolution.resolve(highlighted, discoveryComplete: false) else {
            return XCTFail("Visible selection must not wait for the background scan")
        }
        state.finishSelection(mouseDown: true)
        XCTAssertEqual(state.phase, .dragging)
        XCTAssertEqual(capture.payload.text, "First\n\nSecond")
        XCTAssertEqual(capture.payload.title, "2 elements")
    }

    func testMouseReleasePreservesGroupForRegrabDespiteIncompleteScan() {
        var state = CaptureState()
        state.modifiers(held: true); state.select()
        guard case let .captured(capture) = SelectionReleaseResolution.resolve(highlighted, discoveryComplete: false) else {
            return XCTFail("Mouse-first release must preserve the visible group")
        }
        state.finishSelection(mouseDown: false)
        XCTAssertEqual(state.phase, .ready)
        state.begin()
        XCTAssertEqual(state.phase, .dragging)
        XCTAssertEqual(capture.payload.text, "First\n\nSecond")
    }

    func testSingleHighlightedMemberRetainsItsSourceIdentity() {
        var member = highlighted[0]
        member.anchor = AXUIElementCreateApplication(101)
        member.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: nil)
        guard case let .captured(capture) = SelectionReleaseResolution.resolve([member], discoveryComplete: false) else {
            return XCTFail("A highlighted single block is a valid selection")
        }
        XCTAssertTrue(member.matchesRetainedSource(capture))
    }

    func testLaterDiscoveryCannotAppendUnhighlightedContentToFrozenPayload() {
        var members = highlighted
        guard case let .captured(capture) = SelectionReleaseResolution.resolve(members, discoveryComplete: false) else {
            return XCTFail("Selection must freeze at release")
        }
        members.append(.init(payload: .init(title: "Unseen", markdown: "Unseen"), frame: .zero))
        XCTAssertEqual(capture.payload.text, "First\n\nSecond")
        XCTAssertEqual(members.count, 3)
    }

    func testCompletedDiscoveryKeepsTheSameVisiblePayload() {
        guard case let .captured(capture) = SelectionReleaseResolution.resolve(highlighted, discoveryComplete: true) else {
            return XCTFail("Completed discovery must still capture")
        }
        XCTAssertEqual(capture.payload.text, "First\n\nSecond")
    }

    func testNoHighlightsMayFinishPendingDiscoveryButCompletedEmptySelectionCancels() {
        guard case .finishDiscovery = SelectionReleaseResolution.resolve([], discoveryComplete: false) else {
            return XCTFail("An unfinished empty scan may resolve the frozen marquee")
        }
        guard case .cancel = SelectionReleaseResolution.resolve([], discoveryComplete: true) else {
            return XCTFail("An empty selection must not drag")
        }
    }
}
