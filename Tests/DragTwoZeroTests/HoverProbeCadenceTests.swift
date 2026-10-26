import XCTest
@testable import DragTwoZero

final class HoverProbeCadenceTests: XCTestCase {
    func testHighRatePointerMotionHasBoundedAccessibilityWork() {
        var cadence = HoverProbeCadence()
        let probes = (0..<1000).filter { cadence.shouldProbe(at: Double($0) / 1000, sameBlock: false) }
        XCTAssertLessThanOrEqual(probes.count, 30)
        XCTAssertGreaterThanOrEqual(probes.count, 28)
    }
    func testSameParagraphAvoidsRepeatedTreeWalksButRefreshes() {
        var cadence = HoverProbeCadence()
        let probes = (0..<1000).filter { cadence.shouldProbe(at: Double($0) / 1000, sameBlock: true) }
        XCTAssertLessThanOrEqual(probes.count, 9)
        XCTAssertGreaterThanOrEqual(probes.count, 8)
    }
    func testLeavingParagraphAndStartingDragDoNotInheritSlowCadence() {
        var cadence = HoverProbeCadence()
        XCTAssertTrue(cadence.shouldProbe(at: 0, sameBlock: true))
        XCTAssertFalse(cadence.shouldProbe(at: 0.04, sameBlock: true))
        XCTAssertTrue(cadence.shouldProbe(at: 0.04, sameBlock: false))
        cadence.reset()
        XCTAssertTrue(cadence.shouldProbe(at: 0.041, sameBlock: false))
    }
}
