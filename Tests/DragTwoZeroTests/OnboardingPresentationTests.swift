import XCTest
@testable import DragTwoZero

final class OnboardingPresentationTests: XCTestCase {
    func testVideoPausesWhenCoveredHiddenClosedOrMotionReduced() {
        XCTAssertTrue(onboardingVideoShouldPlay(active: true, visible: true, miniaturized: false, hidden: false, reduceMotion: false))
        XCTAssertFalse(onboardingVideoShouldPlay(active: true, visible: false, miniaturized: false, hidden: false, reduceMotion: false))
        XCTAssertFalse(onboardingVideoShouldPlay(active: true, visible: true, miniaturized: true, hidden: false, reduceMotion: false))
        XCTAssertFalse(onboardingVideoShouldPlay(active: true, visible: true, miniaturized: false, hidden: true, reduceMotion: false))
        XCTAssertFalse(onboardingVideoShouldPlay(active: true, visible: true, miniaturized: false, hidden: false, reduceMotion: true))
        XCTAssertFalse(onboardingVideoShouldPlay(active: false, visible: true, miniaturized: false, hidden: false, reduceMotion: false))
    }
    func testCompactWelcomeFitsAndCentersEntireStack() {
        for height in [CGFloat(384), 416, 500, 559] {
            let layout = CompactOnboardingComposition(height: height, finalPage: false)
            XCTAssertGreaterThanOrEqual(layout.detailY, 0)
            XCTAssertLessThanOrEqual(layout.iconY + 64, height)
            XCTAssertEqual((layout.detailY + layout.iconY + 64) / 2, height / 2, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(layout.headingY, layout.detailY + 72)
            XCTAssertGreaterThanOrEqual(layout.iconY, layout.headingY + 54)
        }
    }
    func testCompactFinalFitsBelowMenuCueWithoutClippingSettingsCard() {
        for height in [CGFloat(384), 416, 500, 559] {
            let layout = CompactOnboardingComposition(height: height, finalPage: true)
            XCTAssertGreaterThanOrEqual(layout.bodyY, 0)
            XCTAssertLessThanOrEqual(layout.headingY + 54, height - 82)
            XCTAssertGreaterThanOrEqual(layout.detailY, layout.bodyY + 110)
            XCTAssertGreaterThanOrEqual(layout.headingY, layout.detailY + 72)
        }
    }
}
