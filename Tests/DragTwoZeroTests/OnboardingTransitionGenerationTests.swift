import XCTest
@testable import DragTwoZero

final class OnboardingTransitionGenerationTests: XCTestCase {
    func testClosedPageCannotCompleteIntoReopenedOnboarding() {
        var generation = OnboardingTransitionGeneration()
        let closedPage = generation.begin()
        generation.invalidate()
        XCTAssertFalse(generation.accepts(closedPage))
        let reopenedPage = generation.begin()
        XCTAssertFalse(generation.accepts(closedPage))
        XCTAssertTrue(generation.accepts(reopenedPage))
    }
    func testNewTransitionRejectsEarlierCompletion() {
        var generation = OnboardingTransitionGeneration()
        let previous = generation.begin()
        let current = generation.begin()
        XCTAssertFalse(generation.accepts(previous))
        XCTAssertTrue(generation.accepts(current))
    }
}
