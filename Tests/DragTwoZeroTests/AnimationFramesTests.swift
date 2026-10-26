import XCTest
@testable import DragTwoZero

/// Clock lifetime checks without windows, input events or haptics.
final class AnimationFramesTests: XCTestCase {
    func testCompletionStopsFurtherFrames() {
        var count = 0
        let clock = AnimationFrames(screen: nil) { count += 1; return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(count, 1)
        withExtendedLifetime(clock) {}
    }

    func testCancellingOrReleasingClockStopsCallbacks() {
        var count = 0
        var clock: AnimationFrames? = AnimationFrames(screen: nil) { count += 1; return true }
        clock?.invalidate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(count, 0)
        clock = AnimationFrames(screen: nil) { count += 1; return true }
        clock = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(count, 0)
    }
}
