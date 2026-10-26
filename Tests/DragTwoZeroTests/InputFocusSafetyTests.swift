import AppKit
import XCTest
@testable import DragTwoZero

/// No windows are ordered onscreen and no event tap or posted input is used.
@MainActor
final class InputFocusSafetyTests: XCTestCase {
    private final class WindowState: NSWindow {
        var simulatedVisible = false
        var simulatedKey = false
        override var isVisible: Bool { simulatedVisible }
        override var isKeyWindow: Bool { simulatedKey }
    }

    func testCapturePanelCannotTakeKeyboardFocus() {
        _ = NSApplication.shared
        let panel = CapturePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        panel.close()
    }

    func testSystemDisabledTapStaysPausedAndPassesThroughSubsequentInput() throws {
        _ = NSApplication.shared
        for reason: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let app = AppDelegate()
            app.captureEnabled = true
            let event = try XCTUnwrap(CGEvent(source: nil))
            XCTAssertFalse(app.handle(reason, event))
            XCTAssertTrue(app.inputMonitoringSuspended)
            event.flags = CGEventFlags(rawValue: CaptureShortcut.current.modifiers)
            for type: CGEventType in [.flagsChanged, .keyDown, .leftMouseDown, .leftMouseUp] {
                XCTAssertFalse(app.handle(type, event))
            }
            XCTAssertTrue(app.captureEnabled, "An interruption must not change the saved preference")
            XCTAssertEqual(app.state.phase, .idle)
            XCTAssertNil(app.tap, "Handling the interruption must never start a replacement event tap")
        }
    }

    func testListenerInterruptionReleasesActiveGestureAndPreservesBuffer() throws {
        _ = NSApplication.shared
        let app = AppDelegate()
        app.captureEnabled = true
        app.state.modifiers(held: true); app.state.begin()
        app.swallowedMouseDown = true
        app.buffer.store(.init(title: "Fixture", markdown: "Fixture"), symbol: "text.alignleft")
        let id = app.buffer.item?.id
        let work = CaptureCommitToken()
        app.sourceValidationToken = work
        let event = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertFalse(app.handle(.tapDisabledByTimeout, event))
        let drained = expectation(description: "Interruption cleanup")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertFalse(work.isValid)
        XCTAssertFalse(app.swallowedMouseDown)
        XCTAssertEqual(app.buffer.item?.id, id)
        XCTAssertEqual(app.state.phase, .idle)
        XCTAssertFalse(app.handle(.leftMouseUp, event))
        XCTAssertTrue(app.inputMonitoringSuspended)
        app.bufferOverlay.close(); app.overlay.close()
    }

    func testOnboardingBlocksGlobalCaptureWhileSystemSettingsHasFocus() throws {
        _ = NSApplication.shared
        let app = AppDelegate()
        let onboarding = OnboardingWindowController(onIncompleteClose: {})
        let window = WindowState(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.simulatedVisible = true
        window.simulatedKey = false
        onboarding.window = window
        app.onboardingWindow = onboarding
        try assertAppControlsPassThrough(app)
        app.onboardingWindow = nil
    }

    func testSettingsAllowsCaptureOutsideShortcutRecording() throws {
        _ = NSApplication.shared
        let app = AppDelegate()
        let settings = SettingsWindowController(onStructureChange: {}, onAppearanceChange: {}, isActive: { true }, onActivationChange: { _ in })
        let window = WindowState(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.simulatedKey = true
        settings.window = window
        app.settingsWindow = settings
        let savedBuffer = CapturePreferences.bufferEnabled
        CapturePreferences.bufferEnabled = false
        defer { CapturePreferences.bufferEnabled = savedBuffer; app.cancel(); app.overlay.close(); app.bufferOverlay.close() }
        app.captureEnabled = true
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.flags = CGEventFlags(rawValue: CaptureShortcut.current.modifiers)
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(CaptureShortcut.current.keyCode ?? 0))
        _ = app.handle(CaptureShortcut.current.keyCode == nil ? .flagsChanged : .keyDown, event)
        XCTAssertEqual(app.state.phase, .armed)
        app.settingsWindow = nil
    }

    private func assertAppControlsPassThrough(_ app: AppDelegate) throws {
        app.captureEnabled = true
        let shortcut = CaptureShortcut.current
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.flags = CGEventFlags(rawValue: shortcut.modifiers)
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(shortcut.keyCode ?? 0))
        for type: CGEventType in [.flagsChanged, .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyUp] {
            XCTAssertFalse(app.handle(type, event), "App UI must receive \(type)")
            XCTAssertEqual(app.state.phase, .idle)
            XCTAssertFalse(app.swallowedMouseDown)
        }
        XCTAssertNil(app.tap)
    }

    func testOpeningAppUICancelsStaleGestureWithoutClearingBuffer() {
        _ = NSApplication.shared
        let bufferEnabled = UserDefaults.standard.object(forKey: CapturePreferences.bufferEnabledKey)
        CapturePreferences.bufferEnabled = false
        defer { UserDefaults.standard.set(bufferEnabled, forKey: CapturePreferences.bufferEnabledKey) }
        let app = AppDelegate()
        app.state.modifiers(held: true)
        app.state.begin()
        app.swallowedMouseDown = true
        app.bufferNativePress = true
        app.shortcutKeyState.consumeKeyDown(40)
        let work = CaptureCommitToken()
        app.sourceValidationToken = work
        app.buffer.store(.init(title: "Fixture", markdown: "Fixture"), symbol: "text.alignleft")
        let id = app.buffer.item?.id
        let generation = app.generation
        app.suspendCaptureForAppUI()
        XCTAssertEqual(app.state.phase, .idle)
        XCTAssertFalse(app.swallowedMouseDown)
        XCTAssertFalse(app.bufferNativePress)
        XCTAssertFalse(app.shortcutKeyState.releaseKey(40))
        XCTAssertFalse(work.isValid)
        XCTAssertGreaterThan(app.generation, generation)
        XCTAssertEqual(app.buffer.item?.id, id)
        app.bufferOverlay.dismiss()
        app.overlay.close()
    }
}
