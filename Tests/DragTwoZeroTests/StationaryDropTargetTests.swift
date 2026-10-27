import AppKit
import XCTest
@testable import DragTwoZero

final class StationaryDropTargetTests: XCTestCase {
    func testStationaryDragRecoversFromAnInitiallyMissingEditorWithoutAnotherMouseEvent() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "liquidGlassEnabled")
        CapturePreferences.liquidGlassEnabled = false
        defer { defaults.set(previous, forKey: "liquidGlassEnabled") }
        let point = CGPoint(x: 150, y: 150), frame = CGRect(x: 100, y: 100, width: 200, height: 80)
        let element = AXUIElementCreateApplication(getpid())
        let expected = InputTarget(element: element, app: try XCTUnwrap(NSRunningApplication(processIdentifier: getpid())),
            frame: frame, dropPoint: point, insertionRange: .init(location: 0, length: 0), caretFrame: .zero, selectionValue: "")
        let lock = NSLock()
        var calls = 0
        let app = AppDelegate(destinationLookupResolver: { _ in
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return calls == 1 ? nil : expected
        })
        defer { app.cancel(); app.bufferOverlay.close(); app.overlay.close() }
        app.captureEnabled = true
        app.state.modifiers(held: true); app.state.begin()
        app.pointer = point
        app.probe(point) // The only simulated pointer event.
        let deadline = Date().addingTimeInterval(0.8)
        while app.target == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertNotNil(app.target, "A late Chromium hit result must not require a wiggle before dropping")
        lock.lock(); let recoveredCalls = calls; lock.unlock()
        XCTAssertGreaterThanOrEqual(recoveredCalls, 2)
        app.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        lock.lock(); let stoppedCalls = calls; lock.unlock()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        lock.lock(); let finalCalls = calls; lock.unlock()
        XCTAssertEqual(finalCalls, stoppedCalls, "Cancellation must stop stationary destination discovery")
    }
}
