import XCTest
@testable import DragTwoZero

final class AnimationPreferencesTests: XCTestCase {
    func testSpeedChangesDurationInTheExpectedDirection() {
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: true, speed: 2, reduceMotion: false), 0.2)
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: true, speed: 0.5, reduceMotion: false), 0.8)
    }
    func testDisabledAndReduceMotionFinishWithoutAnimationDelay() {
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: false, speed: 0.5, reduceMotion: false), 0)
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: true, speed: 0.5, reduceMotion: true), 0)
    }
    func testInvalidSpeedCannotProduceInfiniteAnimation() {
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: true, speed: .nan, reduceMotion: false), 0.4)
        XCTAssertEqual(scaledAnimationDuration(0.4, enabled: true, speed: 0, reduceMotion: false), 0.8)
    }
}
