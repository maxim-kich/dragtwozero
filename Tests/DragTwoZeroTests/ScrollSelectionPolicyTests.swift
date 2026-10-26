import XCTest
@testable import DragTwoZero

final class ScrollSelectionPolicyTests: XCTestCase {
    func testLeadingBetweenSelectedLinesPreservesScrollButCannotStartDrag() {
        let lines = [CGRect(x: 50, y: 10, width: 100, height: 18), CGRect(x: 10, y: 34, width: 80, height: 18)]
        var selected = CaptureCandidate(payload: .init(title: "Selected text", markdown: "passage"), frame: lines[0].union(lines[1]))
        selected.selectedTextRange = CFRange(location: 0, length: 7)
        selected.textFrames = lines
        let leading = CGPoint(x: 70, y: 31)
        XCTAssertFalse(selected.containsVisiblePoint(leading))
        XCTAssertTrue(scrollPreservesSelection(at: leading, frames: selected.scrollProtectionFrames))
        XCTAssertFalse(scrollPreservesSelection(at: CGPoint(x: 160, y: 31), frames: selected.scrollProtectionFrames))
    }

    func testLargeGapsBetweenPassagesAreNotProtected() {
        let lines = [CGRect(x: 10, y: 10, width: 100, height: 18), CGRect(x: 10, y: 100, width: 100, height: 18)]
        XCTAssertFalse(scrollPreservesSelection(at: CGPoint(x: 50, y: 60), frames: textSelectionScrollFrames(lines)))
    }

    func testScrollInsideBlockPreservesSelectionButGapCancels() {
        let frames = [CGRect(x: 10, y: 10, width: 100, height: 20),
                      CGRect(x: 10, y: 60, width: 100, height: 20)]
        XCTAssertTrue(scrollPreservesSelection(at: CGPoint(x: 50, y: 15), frames: frames))
        XCTAssertTrue(scrollPreservesSelection(at: CGPoint(x: 50, y: 65), frames: frames))
        XCTAssertFalse(scrollPreservesSelection(at: CGPoint(x: 50, y: 45), frames: frames))
        XCTAssertFalse(scrollPreservesSelection(at: CGPoint(x: 150, y: 15), frames: frames))
        XCTAssertFalse(scrollPreservesSelection(at: .zero, frames: []))
    }
}
