import AppKit
import XCTest
@testable import DragTwoZero

final class GestureStartRoutingTests: XCTestCase {
    func testPressPointChoosesNativeSelectionWholeBlockOrEmptySpaceDespiteStaleHover() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = ["captureShortcut", "multiselectEnabled", "animationsEnabled", CapturePreferences.bufferEnabledKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        CaptureShortcut.current = .defaultValue; CapturePreferences.multiselectEnabled = true
        CapturePreferences.animationsEnabled = false; CapturePreferences.bufferEnabled = false
        var block = CaptureCandidate(payload: .init(title: "Whole block", markdown: "Whole block"), frame: .init(x: 100, y: 100, width: 250, height: 50))
        block.anchor = AXUIElementCreateApplication(101)
        block.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: nil)
        var selected = CaptureCandidate(payload: .init(title: "Selected text", markdown: "Native passage"), frame: .init(x: 120, y: 100, width: 80, height: 20))
        selected.anchor = block.anchor; selected.context = block.context
        selected.selectedTextRange = CFRange(location: 3, length: 14)
        selected.textFrames = [selected.frame]
        for (point, expected) in [(CGPoint(x: 140, y: 110), "Native passage"),
                                  (CGPoint(x: 300, y: 110), "Whole block"),
                                  (CGPoint(x: 90, y: 90), "marquee")] {
            let delegate = AppDelegate(sourceLookupResolver: { point, _ in
                SourceCaptureLookup.resolve(.selected(selected), at: point) { block }
            })
            delegate.captureEnabled = true; delegate.state.modifiers(held: true)
            // Deliberately stale/wrong hover mode. A press must not inherit it.
            delegate.candidate = expected == "Native passage" ? block : selected
            delegate.allowsMarquee = false
            delegate.selectionCache = []; delegate.selectionDiscoveryComplete = true
            delegate.selectionWindowFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
            let event = CGEvent(source: nil)!; event.type = .leftMouseDown; event.location = point
            event.flags = [.maskAlternate, .maskCommand]
            XCTAssertTrue(delegate.handle(.leftMouseDown, event))
            let deadline = Date().addingTimeInterval(1)
            while (delegate.state.phase == .resolving || delegate.validatingSource) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            if expected == "marquee" {
                XCTAssertEqual(delegate.state.phase, .selecting); XCTAssertNil(delegate.captured)
            } else {
                XCTAssertEqual(delegate.state.phase, .dragging)
                XCTAssertEqual(delegate.captured?.payload.text, expected)
                XCTAssertEqual(delegate.captured?.selectedTextRange != nil, expected == "Native passage")
            }
            delegate.cancel(); delegate.bufferOverlay.close(); delegate.overlay.close()
        }
    }
}
