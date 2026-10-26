import XCTest
@testable import DragTwoZero

/// Window policy only: no app/window creation, events, capture or haptics.
final class ScreenCaptureOverlayTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private var overlay: HitTestWindow {
        candidate()
    }
    private func candidate(layer: Int? = nil, frame: CGRect? = nil, id: CGWindowID? = 100) -> HitTestWindow {
        HitTestWindow(pid: 20, layer: layer ?? Int(CGWindowLevelForKey(.mainMenuWindow)), frame: frame ?? display, windowID: id)
    }
    private var editor: HitTestWindow { HitTestWindow(pid: 30, layer: 0, frame: display, windowID: 200) }
    private let point = CGPoint(x: 500, y: 400)

    func testOnlyFullDisplayMainMenuLayerWindowsQualifyForEvidenceChecks() {
        XCTAssertTrue(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(overlay, displays: [display]))
        var window = candidate(frame: CGRect(x: 0, y: 0, width: 1470, height: 80))
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: [display]), "Capture toolbar stays interactive")
        window = candidate(layer: 1499)
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: [display]))
        window = candidate(id: nil)
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: [display]))
        window = candidate(frame: display.offsetBy(dx: 20, dy: 0))
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: [display]))
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(overlay, displays: []))
    }

    func testPassiveVerifiedOwnerNeedsMatchingSystemHitAndNoCaptureControls() {
        func allowed(trusted: Bool = true, active: Bool = false, count: Int? = 0, hit: pid_t? = 30) -> Bool {
            ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: trusted, ownerActive: active,
                accessibleWindowCount: count, underlyingPID: 30, globalHitPID: hit, ownPID: 10, ownOverlayAtPoint: false)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(trusted: false), "An owner name is not identity proof")
        XCTAssertFalse(allowed(active: true))
        XCTAssertFalse(allowed(count: 1), "Visible Screenshot controls must block")
        XCTAssertFalse(allowed(count: nil), "An unavailable AX read must fail closed")
        XCTAssertFalse(allowed(hit: nil))
        XCTAssertFalse(allowed(hit: 20), "Screenshot receiving the hit must block")
        XCTAssertFalse(allowed(hit: 40), "A different app receiving the hit must block")
    }

    func testOwnNoninteractiveHintMayReceiveSystemHitOnlyWhenPresentAtPoint() {
        for present in [false, true] {
            XCTAssertEqual(ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: true, ownerActive: false,
                accessibleWindowCount: 0, underlyingPID: 30, globalHitPID: 10, ownPID: 10, ownOverlayAtPoint: present), present)
        }
    }

    func testUnverifiedOverlayStillBlocksAndAuthorizationIsPerWindow() {
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, editor], at: point, ownPID: 10), .blocked)
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .application(30))
        let toolbar = candidate(frame: CGRect(x: 400, y: 350, width: 300, height: 100), id: 101)
        XCTAssertEqual(WindowHitPolicy.resolve([toolbar, overlay, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .blocked, "A verified passive window must not exempt its owner's toolbar")
    }

    func testOwnSettingsIsTheSourceAndNeverExposesTheEditorBehindIt() {
        let settings = HitTestWindow(pid: 10, layer: 0, frame: display)
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, settings, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .application(10))
        let popup = HitTestWindow(pid: 40, layer: 3, frame: display)
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, popup, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .blocked)
    }

    func testWrongLayerCannotBeExemptedEvenWithMatchingWindowID() {
        let window = candidate(layer: 1499)
        XCTAssertEqual(WindowHitPolicy.resolve([window, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .blocked)
    }
}
