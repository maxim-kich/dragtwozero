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
        func allowed(trusted: Bool = true, active: Bool = false, hidden: Bool = true, hit: pid_t? = 30) -> Bool {
            ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: trusted, ownerActive: active,
                captureControlsHidden: hidden, underlyingPID: 30, globalHitPID: hit, ownPID: 10, ownOverlayAtPoint: false)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(trusted: false), "An owner name is not identity proof")
        XCTAssertFalse(allowed(active: true))
        XCTAssertFalse(allowed(hidden: false), "Visible or unverified Screenshot controls must block")
        XCTAssertFalse(allowed(hit: nil))
        XCTAssertFalse(allowed(hit: 20), "Screenshot receiving the hit must block")
        XCTAssertFalse(allowed(hit: 40), "A different app receiving the hit must block")
    }

    private var recordingHelper: HitTestWindow {
        HitTestWindow(pid: 21, layer: 1499, frame: display, windowID: 101)
    }

    func testNativeRecordingHelperNeedsItsExactExecutableIdentity() {
        let owner = ScreenCaptureOverlayPolicy.Owner.recordingHelper
        XCTAssertTrue(owner.matches(bundleIdentifier: nil, bundlePath: "/usr/sbin/screencapture",
                                    executablePath: "/usr/sbin/screencapture"))
        XCTAssertFalse(owner.matches(bundleIdentifier: nil, bundlePath: "/tmp/screencapture",
                                     executablePath: "/tmp/screencapture"))
        XCTAssertFalse(owner.matches(bundleIdentifier: "com.apple.screencapture", bundlePath: "/usr/sbin/screencapture",
                                     executablePath: "/tmp/screencapture"))
        XCTAssertFalse(owner.matches(bundleIdentifier: "another.app", bundlePath: "/usr/sbin/screencapture",
                                     executablePath: "/usr/sbin/screencapture"))
        XCTAssertFalse(owner.matches(bundleIdentifier: nil, bundlePath: nil, executablePath: "/usr/sbin/screencapture"))
    }

    func testHelperSurfaceNeedsItsOwnLayerAndFullDisplayGeometry() {
        XCTAssertTrue(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(recordingHelper, displays: [display], owner: .recordingHelper))
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(overlay, displays: [display], owner: .recordingHelper))
        XCTAssertFalse(ScreenCaptureOverlayPolicy.isFullDisplayOverlay(candidate(layer: 1499,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)), displays: [display], owner: .recordingHelper))
    }

    func testNativeRecordingSurfacesNeedVerifiedScreenshotAndHelperOwners() {
        let stack = [recordingHelper, overlay, editor]
        XCTAssertEqual(ScreenCaptureOverlayPolicy.surfaceIDs(in: stack, at: point,
            verifiedOwners: [20: .screenshot, 21: .recordingHelper], displays: [display]), [100, 101])
        XCTAssertEqual(ScreenCaptureOverlayPolicy.surfaceIDs(in: stack, at: point,
            verifiedOwners: [21: .recordingHelper], displays: [display]), [], "A standalone recorder remains blocked")
        XCTAssertEqual(ScreenCaptureOverlayPolicy.surfaceIDs(in: [recordingHelper, editor], at: point,
            verifiedOwners: [20: .screenshot, 21: .recordingHelper], displays: [display]), [], "A trusted process is not a matching Screenshot surface")
        XCTAssertEqual(ScreenCaptureOverlayPolicy.surfaceIDs(in: stack, at: point,
            verifiedOwners: [20: .screenshot], displays: [display]), [100], "An unverified helper is not exempted")
        XCTAssertEqual(ScreenCaptureOverlayPolicy.surfaceIDs(in: stack, at: point,
            verifiedOwners: [20: .recordingHelper, 21: .screenshot], displays: [display]), [], "Owner and layer must agree")
    }

    func testSelectedPortionHiddenControlsNeedEvidenceThroughBothRecordingSurfaces() {
        let toolbar = CGRect(x: 735, y: 840, width: 800, height: 50)
        let stack = [recordingHelper, overlay, editor]
        for ids: Set<CGWindowID> in [[100], [101], []] {
            XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
                windows: stack, overlayIDs: ids, displays: [display], ownPID: 10,
                nativeDragActive: false, systemHitPID: { _ in 30 }))
        }
        for hit: pid_t? in [20, 21, 40, nil] {
            XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
                windows: stack, overlayIDs: [100, 101], displays: [display], ownPID: 10,
                nativeDragActive: false, systemHitPID: { _ in hit }))
        }
        XCTAssertTrue(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
            windows: stack, overlayIDs: [100, 101], displays: [display], ownPID: 10,
            nativeDragActive: false, systemHitPID: { _ in 30 }))
    }

    func testHelperNeverExemptsOtherWindowsOrVisibleControls() {
        XCTAssertEqual(WindowHitPolicy.resolve([recordingHelper, overlay, editor], at: point, ownPID: 10), .blocked)
        XCTAssertEqual(WindowHitPolicy.resolve([recordingHelper, overlay, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100, 101]), .application(30))
        var foreign = recordingHelper
        foreign.windowID = 102
        XCTAssertEqual(WindowHitPolicy.resolve([foreign, recordingHelper, overlay, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100, 101]), .blocked)
        let toolbar = candidate(frame: CGRect(x: 400, y: 350, width: 300, height: 100), id: 103)
        XCTAssertEqual(WindowHitPolicy.resolve([toolbar, recordingHelper, overlay, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100, 101]), .blocked)
    }

    func testRetainedHiddenRecordingToolbarDoesNotBlockTheUnderlyingSource() {
        // Native macOS recording retained this AX window, but its only on-screen
        // Screenshot window was the full-display layer-24 surface.
        let toolbar = CGRect(x: 735, y: 840, width: 800, height: 50)
        var probes: [CGPoint] = []
        XCTAssertTrue(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
            windows: [overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
            nativeDragActive: false, systemHitPID: { probes.append($0); return 30 }))
        XCTAssertEqual(probes, [CGPoint(x: 1102.5, y: 865)], "Probe the visible part, not an off-display center")
    }

    func testVisibleToolbarStillBlocksWhenPaintedInsideTheFullDisplaySurface() {
        let toolbar = CGRect(x: 735, y: 840, width: 800, height: 50)
        for hit: pid_t? in [20, 40, 10, 0, nil] {
            XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
                windows: [overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
                nativeDragActive: false, systemHitPID: { _ in hit }),
                "A retained control must freshly hit the same underlying app, including when Drag's hint is present")
        }
    }

    func testSeparateVisibleToolbarAndForeignDialogsAreNeverSkipped() {
        let frame = CGRect(x: 735, y: 840, width: 735, height: 50)
        for blocker in [candidate(frame: frame, id: 101), HitTestWindow(pid: 40, layer: 3, frame: frame)] {
            XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [frame],
                windows: [blocker, overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
                nativeDragActive: false, systemHitPID: { _ in XCTFail("An occluded window must not be probed"); return 30 }))
        }
    }

    func testEveryRetainedWindowNeedsFreshEvidence() {
        let frames = [CGRect(x: 100, y: 100, width: 200, height: 50), CGRect(x: 500, y: 500, width: 200, height: 50)]
        XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: frames,
            windows: [overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
            nativeDragActive: false, systemHitPID: { $0.x < 400 ? 30 : 20 }))
    }

    func testUnavailableOffDisplayAndUnboundedControlEvidenceFailsClosed() {
        let invalid: [[CGRect]?] = [nil, [.null], [.infinite], [.zero],
            [CGRect(x: 2000, y: 100, width: 200, height: 50)],
            Array(repeating: CGRect(x: 100, y: 100, width: 200, height: 50), count: 9)]
        for frames in invalid {
            XCTAssertFalse(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: frames,
                windows: [overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
                nativeDragActive: false, systemHitPID: { _ in XCTFail("Unknown control geometry must not be probed"); return 30 }))
        }
        XCTAssertTrue(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [],
            windows: [overlay, editor], overlayIDs: [100], displays: [display], ownPID: 10,
            nativeDragActive: false, systemHitPID: { _ in XCTFail("No retained controls need no extra hits"); return nil }))
    }

    func testHiddenToolbarOnASecondaryDisplayUsesThatDisplaysUnderlyingWindow() {
        let other = display.offsetBy(dx: -1470, dy: -956)
        let toolbar = CGRect(x: other.minX + 735, y: other.minY + 840, width: 800, height: 50)
        let recording = candidate(frame: other), source = HitTestWindow(pid: 30, layer: 0, frame: other)
        XCTAssertTrue(ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: [toolbar],
            windows: [recording, source], overlayIDs: [100], displays: [display, other], ownPID: 10,
            nativeDragActive: false, systemHitPID: { point in XCTAssertTrue(other.contains(point)); return 30 }))
    }

    func testOwnNoninteractiveHintMayReceiveSystemHitOnlyWhenPresentAtPoint() {
        for present in [false, true] {
            XCTAssertEqual(ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: true, ownerActive: false,
                captureControlsHidden: true, underlyingPID: 30, globalHitPID: 10, ownPID: 10, ownOverlayAtPoint: present), present)
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
        let window = candidate(layer: 25)
        XCTAssertEqual(WindowHitPolicy.resolve([window, editor], at: point, ownPID: 10,
            passiveScreenCaptureWindows: [100]), .blocked)
    }
}
