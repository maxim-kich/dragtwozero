import AppKit
import XCTest
@testable import DragTwoZero

final class SourceCaptureResolutionTests: XCTestCase {
    func testLineGapRetainsScrollContextAfterHoverCandidateClears() {
        var selected = block(selected: true)
        selected.textFrames = [CGRect(x: 10, y: 10, width: 100, height: 18), CGRect(x: 10, y: 34, width: 100, height: 18)]
        let gap = CGPoint(x: 50, y: 31)
        let lookup = SourceCaptureLookup.resolve(.selected(selected), at: gap) { selected }
        XCTAssertNil(lookup.candidate)
        XCTAssertNotNil(lookup.selectionForScroll)
        XCTAssertTrue(scrollPreservesSelection(at: gap, frames: lookup.selectionForScroll?.scrollProtectionFrames ?? []))
    }

    private let point = CGPoint(x: 20, y: 20)
    private func block(selected: Bool = false, text: String = "selected") -> CaptureCandidate {
        var result = CaptureCandidate(payload: .init(title: text, markdown: text), frame: CGRect(x: 10, y: 10, width: 100, height: 30))
        result.anchor = AXUIElementCreateApplication(101)
        result.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: nil)
        if selected { result.selectedTextRange = CFRange(location: 3, length: 8) }
        return result
    }

    func testUnavailableSelectionNeverFallsBackToParagraphOrMarquee() {
        let lookup = SourceCaptureLookup.resolve(.unavailable, at: point) {
            XCTFail("A failed selection read must not capture more text")
            return self.block()
        }
        XCTAssertNil(lookup.candidate)
        XCTAssertFalse(lookup.allowsMarquee)
    }

    func testNoSelectionRetainsNormalBlockAndMarqueeBehavior() {
        var calls = 0
        let lookup = SourceCaptureLookup.resolve(.none, at: point) {
            calls += 1
            return self.block(text: "entire paragraph")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(lookup.candidate?.payload.text, "entire paragraph")
        XCTAssertTrue(lookup.allowsMarquee)
    }

    func testHoverOutsideExistingSelectionAllowsExplicitMarqueeWithoutParagraphFallback() {
        let lookup = SourceCaptureLookup.resolve(.selected(block(selected: true)), at: .zero) {
            return self.block()
        }
        XCTAssertNil(lookup.candidate)
        XCTAssertTrue(lookup.allowsMarquee)
        XCTAssertNotNil(lookup.selectionForScroll)
    }

    func testSelectedTextIsOneSourceWithoutCallingBlockPicker() {
        let lookup = SourceCaptureLookup.resolve(.selected(block(selected: true)), at: point) {
            XCTFail("Selection must win without consulting block adapters")
            return nil
        }
        XCTAssertEqual(lookup.candidate?.payload.text, "selected")
        // Mouse-down prioritizes this candidate; marquee remains available
        // if the pointer moves into empty space before the next hover probe.
        XCTAssertTrue(lookup.allowsMarquee)
    }

    func testSelectionValidationCannotBecomeParagraphOnReadFailure() {
        XCTAssertNil(SourceCaptureLookup.validate(block(selected: true), selection: { nil }, block: {
            XCTFail("Mouse-down cannot switch capture modes")
            return self.block()
        }))
    }

    func testBlockValidationCannotSwitchToNewlySelectedText() {
        let fresh = SourceCaptureLookup.validate(block(), selection: {
            XCTFail("Original block validation must stay on its block adapter")
            return self.block(selected: true)
        }, block: { self.block() })
        XCTAssertNotNil(fresh)
        XCTAssertNil(fresh?.selectedTextRange)
    }

    func testRepeatedHoverDoesNotRepeatSelectionDiscovery() {
        let session = SelectionCaptureSession(), owner = AXUIElementCreateApplication(101)
        var reads = 0
        for _ in 0..<100 {
            _ = session.resolve(owner) { reads += 1; return .selected(self.block(selected: true)) }
        }
        XCTAssertEqual(reads, 1)
    }

    func testTransientUnavailableSelectionIsRetriedRatherThanCachedForTheGesture() {
        let session = SelectionCaptureSession(), owner = AXUIElementCreateApplication(101)
        _ = session.resolve(owner) { .unavailable }
        var retried = false
        let result = session.resolve(owner) { retried = true; return .selected(self.block(selected: true)) }
        XCTAssertTrue(retried)
        if case .selected = result {} else { XCTFail("The recovered native selection must be available") }
    }

    func testNoSelectionIsAlsoCachedAndNewGestureReadsAgain() {
        let owner = AXUIElementCreateApplication(101)
        var reads = 0
        let first = SelectionCaptureSession()
        for _ in 0..<100 { _ = first.resolve(owner) { reads += 1; return .none } }
        XCTAssertEqual(reads, 1)
        _ = SelectionCaptureSession().resolve(owner) { reads += 1; return .selected(self.block(selected: true)) }
        XCTAssertEqual(reads, 2)
    }

    func testFreshAcceptanceStillRejectsChangedContentAfterCachedHover() {
        let old = block(selected: true), changed = block(selected: true, text: "changed!")
        let session = SelectionCaptureSession()
        _ = session.resolve(old.anchor!) { .selected(old) }
        let fresh = SourceCaptureLookup.validate(old, selection: { changed }, block: { nil })
        XCTAssertFalse(old.matchesCurrentSource(fresh!, at: point))
    }

    func testOtherParagraphStillUsesNormalBlockHoverWithNativeSelectionPresent() {
        let native = block(selected: true)
        var other = block(text: "Other paragraph")
        other = CaptureCandidate(payload: other.payload, frame: CGRect(x: 10, y: 100, width: 100, height: 30))
        let lookup = SourceCaptureLookup.resolve(.selected(native), at: CGPoint(x: 20, y: 110)) { other }
        XCTAssertEqual(lookup.candidate?.payload.text, "Other paragraph")
        XCTAssertNil(lookup.candidate?.selectedTextRange)
        XCTAssertNotNil(lookup.selectionForScroll)
    }

    func testUnselectedTextInSameParagraphCapturesWholeBlock() {
        let native = block(selected: true)
        // Move outside the selected glyphs while remaining inside its paragraph.
        // The fixture's selected geometry must be narrower than its block frame.
        var selected = native
        selected.textFrames = [CGRect(x: 10, y: 10, width: 30, height: 18)]
        let actual = SourceCaptureLookup.resolve(.selected(selected), at: CGPoint(x: 105, y: 30)) { self.block(text: "Whole paragraph") }
        XCTAssertEqual(actual.candidate?.payload.text, "Whole paragraph")
        XCTAssertNil(actual.candidate?.selectedTextRange)
        XCTAssertTrue(actual.allowsMarquee)
    }

}
