import XCTest
@testable import DragTwoZero

final class OverlayTests: XCTestCase {
    func testOverlayTracksPointerAcrossNegativeAndStackedDisplays() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let screens = [main, left, above]
        for (point, expected) in [(CGPoint(x: 100, y: 100), main),
                                  (CGPoint(x: -1, y: 100), left),
                                  (CGPoint(x: 100, y: 901), above),
                                  (CGPoint(x: 100, y: 100), main)] {
            XCTAssertEqual(overlayScreenFrame(at: point, screens: screens), expected)
        }
        XCTAssertNil(overlayScreenFrame(at: CGPoint(x: -1, y: 1200), screens: screens))
        XCTAssertNil(overlayScreenFrame(at: .zero, screens: []))
    }
    func testHintFlipsLeftAndAboveAtBottomRight() {
        let frame = hintFrame(at: CGPoint(x: 990, y: 790), size: CGSize(width: 280, height: 32), screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertLessThan(frame.maxX, 990)
        XCTAssertLessThan(frame.maxY, 790)
    }
    func testHintUsesLeftMonitorCoordinates() {
        let screen = CGRect(x: -1200, y: -200, width: 1200, height: 900)
        let frame = hintFrame(at: CGPoint(x: -1180, y: -190), size: CGSize(width: 180, height: 32), screen: screen)
        XCTAssertTrue(screen.contains(frame))
    }
}
