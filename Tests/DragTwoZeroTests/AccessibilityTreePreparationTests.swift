import XCTest
import ApplicationServices
@testable import DragTwoZero

final class AccessibilityTreePreparationTests: XCTestCase {
    func testRequestsTreeOnceDuringConcurrentHoverAndDiscoveryThenRechecks() {
        let preparation = AccessibilityTreePreparation()
        var calls = 0
        for time in [0.0, 0.1, 1, 4.9, 5] {
            preparation.prepare(pid: 99999, now: time) { calls += 1; return .success }
        }
        XCTAssertEqual(calls, 2)
    }
    func testUnavailableApplicationCanRecoverWithoutRestartingDrag() {
        let preparation = AccessibilityTreePreparation()
        var calls = 0
        preparation.prepare(pid: 99999, now: 0) { calls += 1; return .cannotComplete }
        preparation.prepare(pid: 99999, now: 0.2) { XCTFail("Back off transient failures"); return .success }
        preparation.prepare(pid: 99999, now: 1) { calls += 1; return .success }
        XCTAssertEqual(calls, 2)
    }
    func testNativeAppsWithoutTheAttributeAreNotRetriedOnEveryHover() {
        let preparation = AccessibilityTreePreparation()
        preparation.prepare(pid: 99999, now: 0) { .attributeUnsupported }
        preparation.prepare(pid: 99999, now: 1) { XCTFail("Unsupported native app"); return .success }
    }
    func testOwnApplicationDoesNotRequestWebTreeActivation() {
        AccessibilityTreePreparation().prepare(pid: getpid()) { XCTFail("Own native UI has no web tree"); return .success }
    }
}
