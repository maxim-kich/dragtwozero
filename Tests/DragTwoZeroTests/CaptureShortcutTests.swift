import XCTest
import AppKit
@testable import DragTwoZero

final class CaptureShortcutTests: XCTestCase {
    func testDefaultRequiresOptionAndCommandWithoutAKey() {
        let shortcut = CaptureShortcut.defaultValue
        XCTAssertEqual(shortcut.title, "⌥⌘")
        XCTAssertTrue(shortcut.matches(flags: [.maskAlternate, .maskCommand], keyPressed: false))
        XCTAssertFalse(shortcut.matches(flags: [.maskCommand], keyPressed: false))
        XCTAssertFalse(shortcut.matches(flags: [.maskAlternate], keyPressed: false))
    }
    func testKeyShortcutRequiresBothModifiersAndKey() {
        let shortcut = CaptureShortcut(modifiers: CGEventFlags.maskControl.rawValue, keyCode: 0, keyLabel: "A")
        XCTAssertTrue(shortcut.matches(flags: [.maskControl], keyPressed: true))
        XCTAssertFalse(shortcut.matches(flags: [.maskControl], keyPressed: false))
        XCTAssertFalse(shortcut.matches(flags: [], keyPressed: true))
        XCTAssertEqual(shortcut.title, "⌃A")
    }
    func testFnCanBeUsedAloneOrWithAKey() {
        XCTAssertTrue(CaptureShortcut.modifierMask.contains(.maskSecondaryFn))
        let fn = CaptureShortcut(modifiers: CGEventFlags.maskSecondaryFn.rawValue, keyCode: nil, keyLabel: "")
        XCTAssertEqual(fn.title, "fn")
        XCTAssertTrue(fn.matches(flags: [.maskSecondaryFn], keyPressed: false))
        XCTAssertFalse(fn.matches(flags: [], keyPressed: false))
        let chord = CaptureShortcut(modifiers: CGEventFlags([.maskSecondaryFn, .maskCommand]).rawValue, keyCode: 0, keyLabel: "A")
        XCTAssertEqual(chord.title, "fn⌘A")
        XCTAssertTrue(chord.matches(flags: [.maskSecondaryFn, .maskCommand], keyPressed: true))
        XCTAssertFalse(chord.matches(flags: [.maskCommand], keyPressed: true))
        XCTAssertFalse(chord.matches(flags: [.maskSecondaryFn, .maskCommand], keyPressed: false))
    }
    private var custom: CaptureShortcut {
        CaptureShortcut(modifiers: CGEventFlags([.maskControl, .maskAlternate]).rawValue, keyCode: 40, keyLabel: "K")
    }

    func testConsumedKeyDownRemainsHeldAcrossMouseEventsUntilObservedKeyUp() throws {
        let shortcut = custom
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: true))
        var keys = CaptureShortcutKeyState()
        XCTAssertTrue(shortcut.isHeld(flags: flags, event: down, type: .keyDown, observedKeyDown: false))
        keys.consumeKeyDown(40)
        // The event-tap down was consumed. A mouse event carries no keyboard
        // transition and must use observed state rather than session keyState.
        XCTAssertTrue(shortcut.isHeld(flags: flags, type: .mouseMoved, observedKeyDown: keys.isPressed(for: shortcut)))
        XCTAssertTrue(shortcut.isHeld(flags: flags, type: .leftMouseDown, observedKeyDown: keys.isPressed(for: shortcut)))
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: false))
        XCTAssertFalse(shortcut.isHeld(flags: flags, event: up, type: .keyUp, observedKeyDown: true))
        XCTAssertTrue(keys.releaseKey(40))
        XCTAssertFalse(shortcut.isHeld(flags: flags, type: .mouseMoved, observedKeyDown: keys.isPressed(for: shortcut)))
    }

    func testObservedKeysRequireCurrentModifiersAndDoNotTransferToNewShortcut() {
        let shortcut = custom
        var keys = CaptureShortcutKeyState()
        keys.consumeKeyDown(40)
        XCTAssertFalse(shortcut.isHeld(flags: [.maskControl], observedKeyDown: keys.isPressed(for: shortcut)))
        let changed = CaptureShortcut(modifiers: shortcut.modifiers, keyCode: 0, keyLabel: "A")
        XCTAssertFalse(keys.isPressed(for: changed))
        // Release bookkeeping is independent of the current shortcut or UI
        // gate, so releasing K during recording/onboarding still clears K.
        XCTAssertTrue(keys.releaseKey(40))
        XCTAssertFalse(keys.isPressed(for: shortcut))
    }

    func testPowerSessionResetCannotConsumeTheNextUnmodifiedCustomKey() {
        var keys = CaptureShortcutKeyState()
        keys.consumeKeyDown(40)
        keys.reset()
        XCTAssertFalse(keys.isPressed(for: custom))
        XCTAssertFalse(keys.releaseKey(40))
        XCTAssertFalse(custom.isHeld(flags: [], observedKeyDown: keys.isPressed(for: custom)))
    }

    func testObservedCustomShortcutStaysLockedUntilReleaseAndReleaseHeldDragSurvives() {
        var keys = CaptureShortcutKeyState()
        let shortcut = custom
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        keys.consumeKeyDown(40)
        var state = CaptureState()
        state.modifiers(held: shortcut.isHeld(flags: flags, observedKeyDown: keys.isPressed(for: shortcut)))
        state.begin()
        XCTAssertTrue(state.drop(valid: true))
        state.modifiers(held: shortcut.isHeld(flags: flags, observedKeyDown: keys.isPressed(for: shortcut)))
        XCTAssertEqual(state.phase, .locked)
        keys.releaseKey(40)
        state.modifiers(held: shortcut.isHeld(flags: flags, observedKeyDown: keys.isPressed(for: shortcut)))
        XCTAssertEqual(state.phase, .idle)
        keys.consumeKeyDown(40)
        state.modifiers(held: true); state.begin()
        keys.releaseKey(40)
        state.modifiers(held: shortcut.isHeld(flags: flags, observedKeyDown: keys.isPressed(for: shortcut)))
        XCTAssertEqual(state.phase, .dragging)
        XCTAssertTrue(state.drop(valid: true))
    }

    func testOnlyAutorepeatOfConsumedCurrentTriggerWithRequiredModifiersIsSwallowed() {
        let shortcut = custom
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        var keys = CaptureShortcutKeyState()
        XCTAssertFalse(keys.consumesAutorepeat(for: shortcut, code: 40, flags: flags, isAutorepeat: true))
        keys.consumeKeyDown(40)
        XCTAssertTrue(keys.consumesAutorepeat(for: shortcut, code: 40, flags: flags, isAutorepeat: true))
        XCTAssertFalse(keys.consumesAutorepeat(for: shortcut, code: 40, flags: flags, isAutorepeat: false))
        XCTAssertFalse(keys.consumesAutorepeat(for: shortcut, code: 0, flags: flags, isAutorepeat: true))
        XCTAssertFalse(keys.consumesAutorepeat(for: shortcut, code: 40, flags: [.maskControl], isAutorepeat: true))
        let changed = CaptureShortcut(modifiers: shortcut.modifiers, keyCode: 0, keyLabel: "A")
        XCTAssertFalse(keys.consumesAutorepeat(for: changed, code: 40, flags: flags, isAutorepeat: true))
        keys.releaseKey(40)
        XCTAssertFalse(keys.consumesAutorepeat(for: shortcut, code: 40, flags: flags, isAutorepeat: true))
    }

    func testShortcutRoundTripsForPersistence() throws {
        let shortcut = CaptureShortcut(modifiers: CGEventFlags([.maskControl, .maskShift]).rawValue, keyCode: 49, keyLabel: "Space")
        XCTAssertEqual(try JSONDecoder().decode(CaptureShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
    }
}
