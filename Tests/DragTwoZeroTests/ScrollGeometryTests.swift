import XCTest
@testable import DragTwoZero

final class ScrollGeometryTests: XCTestCase {
    func testSelectedPayloadSurvivesScrollingOutAndBackIntoView() {
        let viewport = CGRect(x: 0, y: 100, width: 500, height: 400)
        let block = CaptureCandidate(payload: .init(title: "Same item", markdown: "Selected content"), frame: CGRect(x: 20, y: 120, width: 300, height: 40))
        let away = block.repositioned(to: CGRect(x: 20, y: 40, width: 300, height: 40), clippedTo: viewport)
        XCTAssertNil(away.visibleFrame)
        XCTAssertEqual(away.payload.text, "Selected content")
        let returned = away.repositioned(to: block.frame, clippedTo: viewport)
        XCTAssertEqual(returned.visibleFrame, block.frame)
    }
    func testPartiallyVisibleBlockIsClippedToScrollViewport() {
        let block = CaptureCandidate(payload: .init(title: "", markdown: "Text"), frame: CGRect(x: 20, y: 120, width: 300, height: 40))
        let moved = block.repositioned(to: CGRect(x: 20, y: 80, width: 300, height: 40), clippedTo: CGRect(x: 0, y: 100, width: 500, height: 400))
        XCTAssertEqual(moved.visibleFrame, CGRect(x: 20, y: 100, width: 300, height: 20))
    }
    func testScrollingDoesNotPulseSelectionHapticsAgain() {
        var count = 0
        let haptics = CaptureHaptics(perform: { _ in count += 1 })
        let first = CGRect(x: 0, y: 100, width: 100, height: 30)
        let moved = first.offsetBy(dx: 0, dy: -20)
        haptics.highlight([first]); haptics.reposition([moved]); haptics.highlight([moved])
        XCTAssertEqual(count, 1)
    }
}
