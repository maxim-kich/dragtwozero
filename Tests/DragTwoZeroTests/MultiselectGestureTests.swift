import AppKit
import XCTest
@testable import DragTwoZero

/// Exercise the production event handler with synthetic blocks. Source reads
/// are injected so these tests never inspect another app or deliver content.
final class MultiselectGestureTests: XCTestCase {
    private let held: CGEventFlags = [.maskAlternate, .maskCommand]
    private let firstPoint = CGPoint(x: 140, y: 120)
    private let endPoint = CGPoint(x: 320, y: 220)

    private func withSelection(resolver: @escaping ([CaptureCandidate], [SourceAdapter]) -> [CaptureCandidate]? = { blocks, _ in blocks },
                               sourceResolver: ((CGPoint, SelectionCaptureSession) -> SourceCaptureLookup)? = nil,
                               finalResolver: ((CGPoint, CGRect, AXUIElement?, SelectionScanControl) -> MarqueeDiscovery)? = nil,
                               _ body: (AppDelegate) throws -> Void) rethrows {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "captureShortcut")
        let savedMultiselect = defaults.object(forKey: "multiselectEnabled")
        let savedAnimations = defaults.object(forKey: "animationsEnabled")
        defer {
            defaults.set(saved, forKey: "captureShortcut")
            defaults.set(savedMultiselect, forKey: "multiselectEnabled")
            defaults.set(savedAnimations, forKey: "animationsEnabled")
        }
        CaptureShortcut.current = .defaultValue
        CapturePreferences.multiselectEnabled = true
        CapturePreferences.animationsEnabled = false
        let delegate = AppDelegate(selectionSourceResolver: { blocks, adapters, _ in resolver(blocks, adapters) },
                                   sourceLookupResolver: sourceResolver, finalSelectionResolver: finalResolver)
        delegate.captureEnabled = true
        delegate.state.modifiers(held: true)
        delegate.state.select()
        delegate.selectionStart = CGPoint(x: 90, y: 90)
        delegate.selectionEnd = endPoint
        delegate.pointer = endPoint
        delegate.selectionMouseDown = true
        delegate.swallowedMouseDown = true
        delegate.selectionBlocks = [block("First", y: 100), block("Second", y: 180)]
        delegate.selectionCache = delegate.selectionBlocks
        delegate.selectionDiscoveryComplete = true
        defer { delegate.cancel(); delegate.overlay.close() }
        try body(delegate)
    }

    private func block(_ text: String, y: CGFloat) -> CaptureCandidate {
        var value = CaptureCandidate(payload: .init(title: text, markdown: text),
                                     frame: CGRect(x: 100, y: y, width: 200, height: 40))
        value.anchor = AXUIElementCreateApplication(101)
        value.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: "https://example.test/fixture")
        return value
    }

    private func event(_ type: CGEventType, at point: CGPoint? = nil, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(source: nil)!
        event.type = type
        event.location = point ?? endPoint
        event.flags = flags
        return event
    }

    func testMarqueeContinuesWhileHeldWithBufferEnabledAndDisabled() {
        let saved = CapturePreferences.bufferEnabled
        defer { CapturePreferences.bufferEnabled = saved }
        for enabled in [false, true] {
            CapturePreferences.bufferEnabled = enabled
            withSelection { delegate in
                delegate.bufferOverlay.beginCapture(at: endPoint)
                XCTAssertTrue(delegate.handle(.leftMouseDragged, event(.leftMouseDragged, flags: held)))
                XCTAssertEqual(delegate.state.phase, .selecting)
                XCTAssertFalse(delegate.inputMonitoringSuspended)
                XCTAssertEqual(delegate.bufferOverlay.targetFrame != nil, enabled)
                XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held)))
                XCTAssertEqual(delegate.state.phase, .ready)
                XCTAssertEqual(delegate.selectionBlocks.count, 2)
                delegate.bufferOverlay.close()
            }
        }
    }

    func testShortcutReleaseStartsDragWithCompleteDiscovery() {
        withSelection { delegate in
            let scan = delegate.selectionScan
            XCTAssertFalse(delegate.handle(.flagsChanged, event(.flagsChanged)))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.validatingSource)
            XCTAssertTrue(scan.isCancelled)
            XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
        }
    }

    func testMouseReleaseFreezesHighlightsAndNextClickStartsWholeSelection() {
        withSelection { delegate in
            let scan = delegate.selectionScan
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held)))
            XCTAssertEqual(delegate.state.phase, .ready)
            XCTAssertFalse(delegate.swallowedMouseDown)
            XCTAssertTrue(scan.isCancelled)
            XCTAssertFalse(delegate.handle(.mouseMoved, event(.mouseMoved, at: .zero, flags: held)))
            XCTAssertEqual(delegate.state.phase, .ready)
            XCTAssertEqual(delegate.selectionBlocks.map(\.payload.text), ["First", "Second"])
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held)))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.validatingSource)
            XCTAssertTrue(delegate.swallowedMouseDown)
            XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
        }
    }

    func testNextClickCanStartDragWhileShortcutIsStillHeld() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held)))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
        }
    }

    func testClickingReadyHintOutsideHighlightedSectionsDragsTheWholeSelection() throws {
        try withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let hint = try XCTUnwrap(delegate.overlay.dragHintFrame)
            let point = CGPoint(x: hint.midX, y: hint.midY)
            XCTAssertFalse(delegate.selectionBlocks.contains { $0.visibleFrame?.contains(point) == true })
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: point, flags: held)))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.validatingSource, "Hint presses must use the same fresh source validation as highlighted sections")
            XCTAssertTrue(delegate.swallowedMouseDown)
            XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
        }
    }

    func testClickBesideReadyHintStillPassesThroughAndClearsSelection() throws {
        try withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let hint = try XCTUnwrap(delegate.overlay.dragHintFrame)
            let point = CGPoint(x: hint.maxX + 1, y: hint.midY)
            XCTAssertFalse(delegate.selectionBlocks.contains { $0.visibleFrame?.contains(point) == true })
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: point, flags: held)))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testReleasingShortcutStillClearsReadyHintBeforeItCanBeClicked() throws {
        try withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let hint = try XCTUnwrap(delegate.overlay.dragHintFrame)
            _ = delegate.handle(.flagsChanged, event(.flagsChanged))
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: CGPoint(x: hint.midX, y: hint.midY))))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testClickBetweenSelectedBlocksPassesThroughAndClearsSelection() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let gap = CGPoint(x: 140, y: 160)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: gap, flags: held)))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testPointerEventRecoversShortcutReleaseWhenFlagsEventWasMissed() {
        withSelection { delegate in
            XCTAssertTrue(delegate.handle(.leftMouseDragged, event(.leftMouseDragged)))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.selectionScan.isCancelled)
        }
    }

    func testCustomKeyReleaseStartsDragWhileItsModifiersStayHeld() {
        withSelection { delegate in
            CaptureShortcut.current = CaptureShortcut(modifiers: CGEventFlags.maskControl.rawValue, keyCode: 40, keyLabel: "K")
            delegate.shortcutKeyState.consumeKeyDown(40)
            let release = event(.keyUp, flags: [.maskControl])
            release.setIntegerValueField(.keyboardEventKeycode, value: 40)
            XCTAssertTrue(delegate.handle(.keyUp, release))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertFalse(delegate.shortcutKeyState.isPressed(for: CaptureShortcut.current))
        }
    }

    func testQuickRegrabReleasePreservesSelectionOnlyWhileShortcutHeld() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            _ = delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held))
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held)))
            XCTAssertEqual(delegate.state.phase, .ready)
            XCTAssertFalse(delegate.validatingSource)
            XCTAssertFalse(delegate.swallowedMouseDown)
            _ = delegate.handle(.flagsChanged, event(.flagsChanged))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testEmptyMouseReleaseCancelsAndDoesNotConsumeNextClick() {
        withSelection { delegate in
            delegate.selectionBlocks = []
            delegate.selectionCache = []
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp)))
            XCTAssertNotEqual(delegate.state.phase, .selecting)
            XCTAssertFalse(delegate.swallowedMouseDown)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: .zero)))
        }
    }

    func testLateFailedValidationCannotCancelNextSelectionDrag() {
        let firstRead = DispatchSemaphore(value: 0)
        let secondRead = DispatchSemaphore(value: 0)
        let firstStarted = expectation(description: "first source read started")
        let oldResultDrained = expectation(description: "old result drained")
        var reads = 0
        withSelection(resolver: { _, _ in
            reads += 1
            if reads == 1 {
                firstStarted.fulfill()
                _ = firstRead.wait(timeout: .now() + 2)
            } else {
                DispatchQueue.main.async { oldResultDrained.fulfill() }
                _ = secondRead.wait(timeout: .now() + 2)
            }
            return nil
        }) { delegate in
            defer { firstRead.signal(); secondRead.signal() }
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            _ = delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held))
            wait(for: [firstStarted], timeout: 1)
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertEqual(delegate.state.phase, .ready)
            _ = delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held))
            firstRead.signal()
            wait(for: [oldResultDrained], timeout: 1)
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.validatingSource)
            XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
        }
    }

    func testEscapeClearsReadySelectionAndDoesNotConsumeOutsideClick() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let escape = event(.keyDown, flags: held)
            escape.setIntegerValueField(.keyboardEventKeycode, value: 53)
            XCTAssertTrue(delegate.handle(.keyDown, escape))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held)))
        }
    }

    func testEmptyShortcutReleaseConsumesPairedMouseUpOnly() {
        withSelection { delegate in
            delegate.selectionBlocks = []
            delegate.selectionCache = []
            _ = delegate.handle(.flagsChanged, event(.flagsChanged))
            XCTAssertNotEqual(delegate.state.phase, .selecting)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp)))
            XCTAssertFalse(delegate.swallowedMouseDown)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: .zero)))
        }
    }

    func testNativeTextSelectionDoesNotBlockExplicitMarqueeOrChangeItsPayload() {
        // Cover both a completed hover outside the selection and mouse-down
        // arriving before the hover probe catches up with the pointer.
        for hoverInsideSelection in [false, true] {
            var native = block("Existing native selection", y: 100)
            native.selectedTextRange = CFRange(location: 0, length: 25)
            withSelection(sourceResolver: { point, _ in
                SourceCaptureLookup.resolve(.selected(native), at: point) { nil }
            }) { delegate in
                let start = CGPoint(x: 90, y: 90)
                let lookup = SourceCaptureLookup.resolve(.selected(native), at: hoverInsideSelection ? firstPoint : start) {
                    return nil
                }
                delegate.state = CaptureState()
                delegate.state.modifiers(held: true)
                delegate.candidate = lookup.candidate
                delegate.allowsMarquee = lookup.allowsMarquee
                delegate.scrollSelection = lookup.selectionForScroll
                delegate.swallowedMouseDown = false
                delegate.selectionWindowFrame = CGRect(x: 0, y: 0, width: 600, height: 400)

                XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: start, flags: held)))
                let deadline = Date().addingTimeInterval(1)
                while delegate.state.phase == .resolving && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                XCTAssertEqual(delegate.state.phase, .selecting)
                XCTAssertTrue(delegate.handle(.leftMouseDragged, event(.leftMouseDragged, flags: held)))
                XCTAssertEqual(delegate.selectionBlocks.map(\.payload.text), ["First", "Second"])
                XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held)))
                XCTAssertEqual(delegate.state.phase, .ready)
                XCTAssertEqual(delegate.captured?.payload.text, "First\n\nSecond")
                XCTAssertNil(delegate.captured?.selectedTextRange)
            }
        }
    }

    func testMouseFirstThenShortcutReleaseClearsSelection() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertEqual(delegate.state.phase, .ready)
            _ = delegate.handle(.flagsChanged, event(.flagsChanged))
            XCTAssertEqual(delegate.state.phase, .idle)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint)))
        }
    }

    func testCustomTriggerKeyReleaseClearsReadySelectionWithModifiersHeld() {
        withSelection { delegate in
            CaptureShortcut.current = CaptureShortcut(modifiers: CGEventFlags.maskControl.rawValue, keyCode: 40, keyLabel: "K")
            delegate.shortcutKeyState.consumeKeyDown(40)
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: [.maskControl]))
            XCTAssertEqual(delegate.state.phase, .ready)
            let release = event(.keyUp, flags: [.maskControl])
            release.setIntegerValueField(.keyboardEventKeycode, value: 40)
            XCTAssertTrue(delegate.handle(.keyUp, release))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testPointerObservesMissedShortcutReleaseInReadyState() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            _ = delegate.handle(.mouseMoved, event(.mouseMoved))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertNil(delegate.captured)
        }
    }

    func testMouseReleaseWithBothInputsUpClearsImmediately() {
        withSelection { delegate in
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp)))
            XCTAssertEqual(delegate.state.phase, .idle)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
        }
    }

    func testPassiveSelectionDoesNotKeepKeyboardFocus() throws {
        try withSelection { delegate in
            delegate.overlay.beginCapture()
            delegate.updateSelection()
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let panel = try XCTUnwrap(NSApp.windows.first {
                $0.isVisible && String(describing: type(of: $0)).contains("CapturePanel")
            })
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertFalse(NSApp.keyWindow === panel)
        }
    }

    func testSwitchingAppsClearsHighlightsAndPassesClickThrough() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            delegate.sourceApplicationDidChange()
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint)))
        }
    }

    func testAppSwitchKeyClearsReadySelectionBeforeClick() {
        withSelection { delegate in
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let tab = event(.keyDown, flags: held)
            tab.setIntegerValueField(.keyboardEventKeycode, value: 48)
            XCTAssertFalse(delegate.handle(.keyDown, tab))
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint)))
        }
    }

    func testFastPressIsConsumedWhileSourceResolvesAndRecoversMarquee() {
        let started = expectation(description: "source resolving")
        let release = DispatchSemaphore(value: 0)
        withSelection(sourceResolver: { _, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return SourceCaptureLookup(candidate: nil, allowsMarquee: true)
        }) { delegate in
            defer { release.signal() }
            delegate.state = CaptureState(); delegate.state.modifiers(held: true)
            delegate.candidate = nil; delegate.allowsMarquee = false
            delegate.swallowedMouseDown = false
            let start = CGPoint(x: 90, y: 90)
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, at: start, flags: held)))
            XCTAssertEqual(delegate.state.phase, .resolving)
            wait(for: [started], timeout: 1)
            XCTAssertTrue(delegate.handle(.leftMouseDragged, event(.leftMouseDragged, flags: held)))
            // Complete background discovery before the pending source returns.
            delegate.selectionWindowFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
            delegate.selectionCache = [block("First", y: 100), block("Second", y: 180)]
            delegate.selectionDiscoveryComplete = true
            release.signal()
            let selected = expectation(for: NSPredicate { _, _ in delegate.state.phase == .selecting }, evaluatedWith: nil)
            wait(for: [selected], timeout: 2.5)
            XCTAssertEqual(delegate.selectionBlocks.map(\.payload.text), ["First", "Second"])
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertEqual(delegate.state.phase, .ready)
        }
    }

    func testFastPressUnreadableSourceNeverFallsBackToMarquee() {
        withSelection(sourceResolver: { _, _ in SourceCaptureLookup(candidate: nil, allowsMarquee: false) }) { delegate in
            delegate.state = CaptureState(); delegate.state.modifiers(held: true)
            delegate.candidate = nil; delegate.allowsMarquee = false
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, flags: held)))
            let cancelled = expectation(for: NSPredicate { _, _ in delegate.state.phase != .resolving }, evaluatedWith: nil)
            wait(for: [cancelled], timeout: 2.5)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held)))
        }
    }

    func testPartialDiscoveryCommitsOnlyHighlightedMembersImmediately() {
        let first = block("First", y: 100)
        withSelection(finalResolver: { _, _, _, _ in
            XCTFail("Releasing highlighted members must not restart discovery")
            return MarqueeDiscovery(blocks: [], isComplete: false)
        }) { delegate in
            delegate.selectionDiscoveryComplete = false
            delegate.selectionCache = [first]; delegate.selectionBlocks = [first]
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertEqual(delegate.state.phase, .ready)
            XCTAssertFalse(delegate.selectionFinalizing)
            XCTAssertTrue(delegate.selectionScan.isCancelled)
            XCTAssertEqual(delegate.captured?.payload.text, "First")
        }
    }

    func testIncompleteFinalDiscoveryWithoutHighlightsRejectsPartialPayload() {
        let first = block("First", y: 100)
        withSelection(finalResolver: { _, _, _, _ in MarqueeDiscovery(blocks: [first], isComplete: false) }) { delegate in
            delegate.selectionDiscoveryComplete = false
            delegate.selectionBlocks = []; delegate.selectionCache = []
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            let cancelled = expectation(for: NSPredicate { _, _ in delegate.state.phase != .selecting }, evaluatedWith: nil)
            wait(for: [cancelled], timeout: 2.5)
            XCTAssertNil(delegate.captured)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
        }
    }

    func testShortcutReleaseWhileFinalDiscoveryPendingCannotRestoreHighlights() {
        let started = expectation(description: "final scan started")
        let released = DispatchSemaphore(value: 0)
        let full = [block("First", y: 100), block("Second", y: 180)]
        withSelection(finalResolver: { _, _, _, _ in
            started.fulfill()
            _ = released.wait(timeout: .now() + 2)
            return MarqueeDiscovery(blocks: full, isComplete: true)
        }) { delegate in
            defer { released.signal() }
            delegate.selectionDiscoveryComplete = false
            delegate.selectionBlocks = []; delegate.selectionCache = []
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            wait(for: [started], timeout: 1)
            _ = delegate.handle(.flagsChanged, event(.flagsChanged))
            released.signal()
            XCTAssertEqual(delegate.state.phase, .idle)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
        }
    }

    func testNewSingleDragClearsPreviousMultiselectMembersBeforeValidation() {
        let began = expectation(description: "single source validation started")
        let finish = DispatchSemaphore(value: 0)
        let single = block("New single block", y: 100)
        var firstRead = true
        withSelection(sourceResolver: { _, _ in
            if firstRead {
                firstRead = false; began.fulfill()
                _ = finish.wait(timeout: .now() + 2)
            }
            return SourceCaptureLookup(candidate: single, allowsMarquee: true)
        }) { delegate in
            defer { finish.signal() }
            delegate.state = CaptureState(); delegate.state.modifiers(held: true)
            delegate.candidate = single
            delegate.captured = nil
            _ = delegate.handle(.leftMouseDown, event(.leftMouseDown, at: firstPoint, flags: held))
            wait(for: [began], timeout: 1)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, flags: held))
            XCTAssertNotEqual(delegate.state.phase, .ready)
            XCTAssertTrue(delegate.selectionBlocks.isEmpty)
        }
    }

}
