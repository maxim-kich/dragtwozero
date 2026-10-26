import AppKit
import XCTest
@testable import DragTwoZero

final class ExperimentalCaptureTests: XCTestCase {
    func testMultiselectDefaultsOffAndPersistsExplicitChoice() {
        let defaults = UserDefaults.standard, key = "multiselectEnabled"
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.removeObject(forKey: key)
        XCTAssertFalse(CapturePreferences.multiselectEnabled)
        CapturePreferences.multiselectEnabled = true
        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertTrue(CapturePreferences.multiselectEnabled)
        CapturePreferences.multiselectEnabled = false
        XCTAssertFalse(CapturePreferences.multiselectEnabled)
    }

    func testSelectedTextDraggingDefaultsOffAndPersistsExplicitChoice() {
        let defaults = UserDefaults.standard, key = CapturePreferences.selectedTextDraggingKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.removeObject(forKey: key)
        XCTAssertFalse(CapturePreferences.selectedTextDraggingEnabled)
        CapturePreferences.selectedTextDraggingEnabled = true
        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertTrue(CapturePreferences.selectedTextDraggingEnabled)
        CapturePreferences.selectedTextDraggingEnabled = false
        XCTAssertFalse(CapturePreferences.selectedTextDraggingEnabled)
    }

    func testDisabledExperimentNeverReadsSelectionAndUsesNormalBlockCapture() {
        var blockReads = 0
        let lookup = SourceCaptureLookup.resolve(enabled: false, at: CGPoint(x: 20, y: 20), selection: {
            XCTFail("Disabled feature must not perform selection AX probes")
            return .unavailable
        }, block: {
            blockReads += 1
            return CaptureCandidate(payload: .init(title: "Block", markdown: "Whole block"), frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        })
        XCTAssertEqual(blockReads, 1)
        XCTAssertEqual(lookup.candidate?.payload.text, "Whole block")
        XCTAssertTrue(lookup.allowsMarquee)
    }

    func testEnabledExperimentRetainsFailClosedSelectionBehavior() {
        let lookup = SourceCaptureLookup.resolve(enabled: true, at: .zero, selection: { .unavailable }, block: {
            XCTFail("Unreadable selected text must not widen to a block")
            return nil
        })
        XCTAssertNil(lookup.candidate)
        XCTAssertFalse(lookup.allowsMarquee)
    }
}
