import XCTest
import AppKit
@testable import DragTwoZero

final class PassiveSystemOverlayTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let point = CGPoint(x: 500, y: 400)
    private func window(_ pid: pid_t, _ layer: Int, _ id: CGWindowID, frame: CGRect? = nil) -> HitTestWindow {
        HitTestWindow(pid: pid, layer: layer, frame: frame ?? display, windowID: id)
    }

    func testRunningAppleAgentsAreVerifiedEvenWithoutLaunchDates() throws {
        var checked = 0
        for owner: PassiveSystemOverlayPolicy.Owner in [.notificationCenter, .dock] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: owner.rawValue) {
                XCTAssertTrue(PassiveSystemOverlay.trusted(app, owner: owner))
                let wrong: PassiveSystemOverlayPolicy.Owner = owner == .dock ? .notificationCenter : .dock
                XCTAssertFalse(PassiveSystemOverlay.trusted(app, owner: wrong))
                checked += 1
            }
        }
        if checked == 0 { throw XCTSkip("No live Apple desktop agents in this test session") }
    }

    func testReportedNotificationAndDockStackNeedsBothExactWindowAuthorizations() {
        let notification = window(20, 21, 100), dock = window(21, 20, 101)
        let editor = window(30, 0, 102)
        let stack = [notification, dock, editor]
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10), .blocked)
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [100]), .blocked)
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [101]), .blocked)
        XCTAssertTrue(PassiveSystemOverlayPolicy.allowsPassThrough(underlyingPID: 30, systemHitPID: 30))
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [100, 101]), .application(30))
    }

    func testActualNotificationDockAndForeignControlsRejectPassThrough() {
        for hit: pid_t? in [20, 21, 40, 10, 0, nil] {
            XCTAssertFalse(PassiveSystemOverlayPolicy.allowsPassThrough(underlyingPID: 30, systemHitPID: hit))
        }
        XCTAssertFalse(PassiveSystemOverlayPolicy.allowsPassThrough(underlyingPID: 0, systemHitPID: 0))
    }

    func testPopupStillOccludesAfterSystemSurfacesAreAuthorized() {
        let stack = [window(20, 21, 100), window(21, 20, 101), window(40, 3, 103), window(30, 0, 102)]
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [100, 101]), .blocked)
    }

    func testOtherWindowsFromSameSystemOwnerAreNeverExempted() {
        let notificationPanel = window(20, 21, 104, frame: CGRect(x: 400, y: 300, width: 500, height: 400))
        let stack = [notificationPanel, window(20, 21, 100), window(21, 20, 101), window(30, 0, 102)]
        XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [100, 101]), .blocked)
        XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(notificationPanel, owner: .notificationCenter, displays: [display]))
    }

    func testOwnerAndLayerMustMatchAndCandidateMustHaveWindowIdentity() {
        XCTAssertTrue(PassiveSystemOverlayPolicy.isCandidate(window(20, 21, 100), owner: .notificationCenter, displays: [display]))
        XCTAssertTrue(PassiveSystemOverlayPolicy.isCandidate(window(21, 20, 101), owner: .dock, displays: [display]))
        XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(window(20, 20, 100), owner: .notificationCenter, displays: [display]))
        XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(window(21, 21, 101), owner: .dock, displays: [display]))
        XCTAssertNil(PassiveSystemOverlayPolicy.Owner(rawValue: "com.example.notificationcenterui"))
        XCTAssertNil(PassiveSystemOverlayPolicy.Owner(rawValue: "com.apple.some-other-app"))
        var missing = window(20, 21, 100); missing.windowID = nil
        XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(missing, owner: .notificationCenter, displays: [display]))
        missing = window(20, 21, 100); missing.alpha = 0
        XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(missing, owner: .notificationCenter, displays: [display]))
    }

    func testWindowIdentityDoesNotAuthorizeOtherLayers() {
        for layer in [3, 24, 1499] {
            let stack = [window(20, layer, 100), window(30, 0, 102)]
            XCTAssertEqual(WindowHitPolicy.resolve(stack, at: point, ownPID: 10, passiveSystemWindows: [100]), .blocked)
        }
    }

    func testSecondaryDisplayAndMovedWindowsUseActualGeometry() {
        for other in [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: -1080, width: 1920, height: 1080)] {
            let notification = window(20, 21, 100, frame: other)
            XCTAssertTrue(PassiveSystemOverlayPolicy.isCandidate(notification, owner: .notificationCenter, displays: [display, other]))
            XCTAssertFalse(PassiveSystemOverlayPolicy.isCandidate(notification, owner: .notificationCenter, displays: [display]))
            let editor = window(30, 0, 102, frame: other.insetBy(dx: 100, dy: 100))
            let hit = CGPoint(x: other.midX, y: other.midY)
            XCTAssertEqual(WindowHitPolicy.resolve([notification, editor], at: hit, ownPID: 10, passiveSystemWindows: [100]), .application(30))
            XCTAssertEqual(WindowHitPolicy.resolve([notification, editor], at: point, ownPID: 10, passiveSystemWindows: [100]), .none)
        }
    }

    func testOwnHintAndBufferRemainDistinct() {
        let hint = window(10, CaptureWindowLayers.hint.rawValue, 200)
        let buffer = window(10, CaptureWindowLayers.buffer.rawValue, 201)
        let system = [window(20, 21, 100), window(21, 20, 101)]
        let editor = window(30, 0, 102)
        XCTAssertEqual(WindowHitPolicy.resolve([hint] + system + [editor], at: point, ownPID: 10,
            passiveSystemWindows: [100, 101]), .application(30))
        XCTAssertEqual(WindowHitPolicy.resolve([hint, buffer] + system + [editor], at: point, ownPID: 10,
            passiveSystemWindows: [100, 101]), .blocked)
    }
}
