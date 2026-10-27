import AppKit
import XCTest
@testable import DragTwoZero

final class SettingsNavigationTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    func testEverySettingsPageContainsItsControlsAndAboutStillOpensAbout() throws {
        _ = NSApplication.shared
        let service = FakeLoginItemService()
        let controller = SettingsWindowController(onStructureChange: {}, onAppearanceChange: {},
            isActive: { true }, onActivationChange: { _ in },
            launchAtLogin: LaunchAtLoginController(service: service), isAccessibilityGranted: { true })
        defer { controller.close() }
        controller.alignPageContentWithSidebar()
        let root = try XCTUnwrap(controller.window?.contentView)
        let navigation = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTableView }.first)
        let expected = [
            ["Activate", "Launch at login", "Trigger Shortcut", "Haptic feedback"],
            ["Preserve content structure", "Overwrite clipboard"],
            ["Buffer", "Position of buffer"],
            ["Liquid Glass", "Color mode", "Animations", "Hide app icon from Dock"],
            ["Multi-select", "Drag selected text"],
            ["Export Debug Log"]
        ]
        XCTAssertEqual(navigation.numberOfRows, expected.count)
        for (index, controls) in expected.enumerated() {
            navigation.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            controller.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
            let visible = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first { !$0.isHidden })
            let page = try XCTUnwrap(visible.documentView), views = descendants(page)
            let names = views.compactMap { $0.accessibilityLabel() }
            for name in controls { XCTAssertTrue(names.contains(name), "Missing \(name) on page \(index)") }
            if index == 2 {
                let cards = page.subviews.compactMap { $0 as? NSBox }
                XCTAssertEqual(cards.count, 2, "Buffer enable and position must be separate rows")
            }
            if index == 3 {
                let text = views.compactMap { ($0 as? NSTextField)?.stringValue }
                XCTAssertFalse(text.contains("Selection"))
                XCTAssertFalse(text.contains("Motion"))
                let dock = try XCTUnwrap(views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "Hide app icon from Dock" })
                let animations = try XCTUnwrap(views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "Animations" })
                XCTAssertGreaterThan(dock.convert(dock.bounds, to: page).midY, animations.convert(animations.bounds, to: page).midY, "Dock preference is last in the flipped document")
            }
            if let directory = ProcessInfo.processInfo.environment["DRAGTWOZERO_UI_REVIEW_DIR"] {
                let bitmap = try XCTUnwrap(page.bitmapImageRepForCachingDisplay(in: page.bounds))
                page.cacheDisplay(in: page.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-\(index).png"))
            }
        }
        controller.presentAbout()
        XCTAssertEqual(navigation.selectedRow, 5)
        XCTAssertEqual(service.registrations, 0, "Browsing settings must not enable login items")
    }

    @MainActor
    func testAccessibilityReplacesItsButtonWithARightAlignedGreenStatusAndReversesOnRevocation() throws {
        _ = NSApplication.shared
        var granted = false
        let controller = SettingsWindowController(onStructureChange: {}, onAppearanceChange: {},
            isActive: { true }, onActivationChange: { _ in }, isAccessibilityGranted: { granted })
        defer { controller.close() }
        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let button = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Manage Accessibility permission" })
        let status = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Accessibility permission status" })
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(status.isHidden)
        granted = true
        controller.perform(NSSelectorFromString("refreshAccessibility"))
        XCTAssertTrue(button.isHidden)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(status.stringValue, "Allowed")
        XCTAssertEqual(status.textColor, .systemGreen)
        XCTAssertEqual(status.alignment, .right)
        let trailingSpace = try XCTUnwrap(status.superview).bounds.maxX - status.frame.maxX
        XCTAssertGreaterThanOrEqual(trailingSpace, 12)
        XCTAssertLessThanOrEqual(trailingSpace, 20, "Allowed belongs at the trailing edge of the row")
        XCTAssertEqual(status.frame.midY, button.frame.midY, accuracy: 0.5)
        granted = false
        controller.perform(NSSelectorFromString("refreshAccessibility"))
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(status.isHidden)
    }

    @MainActor
    func testOnboardingOffersOptionalLoginAfterAccessibilityAndKeepsAllLaterSteps() throws {
        _ = NSApplication.shared
        let service = FakeLoginItemService()
        let controller = OnboardingWindowController(onIncompleteClose: {},
            launchAtLogin: LaunchAtLoginController(service: service), isAccessibilityGranted: { true },
            readNotificationAuthorization: { $0(.notDetermined) })
        defer { controller.close() }
        controller.present()
        let root = try XCTUnwrap(controller.window?.contentView)
        let next = try XCTUnwrap(descendants(root).compactMap { $0 as? NSButton }.first { $0.title == "Continue" })
        let headings = ["Welcome to Drag 2.0", "Enable Accessibility", "Ready when you log in", "Choose your shortcut", "Give your drag a place to rest", "Hear about updates", "You’re all set"]
        for (index, title) in headings.enumerated() {
            XCTAssertTrue(descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }.contains(title))
            XCTAssertTrue(descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }.contains("\(index + 1) of 7"))
            if index == 2 {
                XCTAssertTrue(next.isEnabled, "Login item is optional")
                XCTAssertEqual(service.status, .notRegistered)
                if let directory = ProcessInfo.processInfo.environment["DRAGTWOZERO_UI_REVIEW_DIR"] {
                    let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                    root.cacheDisplay(in: root.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("onboarding-login.png"))
                }
            }
            if index < headings.count - 1 {
                next.sendAction(next.action, to: next.target)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
            }
        }
        XCTAssertEqual(service.registrations, 0, "Continue without opting in must never register the app")
    }
}
