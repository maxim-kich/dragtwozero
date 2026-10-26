import AppKit
import XCTest
@testable import DragTwoZero

final class HapticFeedbackTests: XCTestCase {
    func testDestinationPulsesOnlyOnEntryNotMovement() {
        var events: [NSHapticFeedbackManager.FeedbackPattern] = []
        let feedback = CaptureHaptics(enabled: { true }, perform: { events.append($0) })
        feedback.destination(true)
        for _ in 0..<100 { feedback.destination(true) }
        XCTAssertEqual(events, [.alignment])
        feedback.destination(false)
        feedback.destination(true)
        XCTAssertEqual(events, [.alignment, .alignment])
        feedback.reset()
        feedback.destination(true)
        XCTAssertEqual(events.count, 3)
    }
    func testDisabledFeedbackSuppressesAllEventsAndCanBeReenabled() {
        var enabled = false
        var count = 0
        let feedback = CaptureHaptics(enabled: { enabled }, perform: { _ in count += 1 })
        let frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        feedback.highlight([frame]); feedback.startDrag(); feedback.drop()
        XCTAssertEqual(count, 0)
        enabled = true
        feedback.highlight([frame]); feedback.startDrag(); feedback.drop()
        XCTAssertEqual(count, 3)
    }
    func testSelectionPulsesOnlyForNewBlocksAndCanReenter() {
        var events: [NSHapticFeedbackManager.FeedbackPattern] = []
        let feedback = CaptureHaptics(perform: { events.append($0) })
        let a = CGRect(x: 0, y: 0, width: 100, height: 20)
        let b = a.offsetBy(dx: 0, dy: 40)
        feedback.highlight([a]); feedback.highlight([a])
        feedback.highlight([a, b]); feedback.highlight([b, a])
        XCTAssertEqual(events, [.alignment, .alignment])
        feedback.highlight([a]); feedback.highlight([a, b])
        XCTAssertEqual(events.count, 3)
    }
    func testDragDropAndCancellationDoNotLeaveSelectionFeedbackStale() {
        var events: [NSHapticFeedbackManager.FeedbackPattern] = []
        let feedback = CaptureHaptics(perform: { events.append($0) })
        let frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        feedback.highlight([frame]); feedback.startDrag(); feedback.drop()
        feedback.reset()
        XCTAssertEqual(events, [.alignment, .generic, .generic])
        feedback.highlight([frame])
        XCTAssertEqual(events.last, .alignment)
    }
}
