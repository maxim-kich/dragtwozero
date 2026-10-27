import XCTest
import AppKit
import ServiceManagement
@testable import DragTwoZero

final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var unregistrations = 0
    var registrationStatus: SMAppService.Status = .enabled
    var failChanges = false
    func register() throws {
        registrations += 1
        if failChanges { throw NSError(domain: "LoginItemTest", code: 1) }
        status = registrationStatus
    }
    func unregister() throws {
        unregistrations += 1
        if failChanges { throw NSError(domain: "LoginItemTest", code: 2) }
        status = .notRegistered
    }
}

final class LaunchAtLoginTests: XCTestCase {
    func testReadingLoginPreferenceNeverEnablesItAndTracksExternalChanges() {
        let service = FakeLoginItemService()
        let current = LaunchAtLoginController(service: service)
        service.status = .enabled
        XCTAssertEqual(current.status, .enabled)
        service.status = .notRegistered
        XCTAssertEqual(current.status, .notRegistered)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
    }

    func testExplicitEnableDisableAndRepeatedRequestsAreIdempotent() throws {
        let service = FakeLoginItemService()
        let current = LaunchAtLoginController(service: service)
        try current.setEnabled(true)
        try current.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(current.status, .enabled)
        try current.setEnabled(false)
        try current.setEnabled(false)
        XCTAssertEqual(service.unregistrations, 1)
        XCTAssertEqual(current.status, .notRegistered)
    }

    func testPendingApprovalIsNotAnEnabledServiceAndCanBeCancelled() throws {
        let service = FakeLoginItemService()
        service.registrationStatus = .requiresApproval
        let controller = LaunchAtLoginController(service: service)
        try controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        try controller.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        try controller.setEnabled(false)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(service.unregistrations, 1)
    }

    func testFirstRegistrationCanRecoverAnInitiallyUnresolvedService() throws {
        let service = FakeLoginItemService()
        service.status = .notFound
        let controller = LaunchAtLoginController(service: service)
        try controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertEqual(service.registrations, 1)
    }

    func testFailureDoesNotInventASavedPreference() {
        let service = FakeLoginItemService()
        service.failChanges = true
        let current = LaunchAtLoginController(service: service)
        XCTAssertThrowsError(try current.setEnabled(true))
        XCTAssertEqual(current.status, .notRegistered)
        service.status = .enabled
        XCTAssertThrowsError(try current.setEnabled(false))
        XCTAssertEqual(current.status, .enabled)
    }

    @MainActor
    func testControlExplainsApprovalAndShowsFailedChangeWithoutLyingAboutState() throws {
        _ = NSApplication.shared
        let service = FakeLoginItemService()
        var settingsOpened = 0
        let view = LaunchAtLoginView(frame: NSRect(x: 0, y: 0, width: 592, height: 64), controller: LaunchAtLoginController(service: service), openSettings: { settingsOpened += 1 })
        let toggle = try XCTUnwrap(view.subviews.compactMap { $0 as? NSSwitch }.first)
        let status = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Launch at login status" })
        let approval = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(settingsOpened, 0)
        XCTAssertEqual(toggle.state, .off)
        service.failChanges = true
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(status.stringValue.contains("Couldn’t change"))
        XCTAssertEqual(settingsOpened, 0, "A failed change without an approval state must not open settings")
        service.failChanges = false
        service.registrationStatus = .requiresApproval
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertFalse(approval.isHidden)
        XCTAssertTrue(status.isHidden)
        XCTAssertTrue(toggle.accessibilityHelp()?.contains("needs approval") == true)
        XCTAssertEqual(settingsOpened, 1, "An explicit enable request opens Login Items when approval is needed")
        service.failChanges = true
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertEqual(toggle.state, .on, "Failed cancellation must retain the OS request")
        XCTAssertTrue(approval.title.contains("Couldn’t change"))
        XCTAssertEqual(settingsOpened, 1, "A disable request must never redirect to approval")
        service.status = .enabled
        view.refresh()
        XCTAssertTrue(approval.isHidden)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(toggle.state, .on)
        service.failChanges = false
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        service.registrationStatus = .enabled
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertEqual(settingsOpened, 1, "Approved registration does not open settings")
    }
}
