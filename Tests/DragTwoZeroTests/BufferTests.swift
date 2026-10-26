import AppKit
import XCTest
@testable import DragTwoZero

final class BufferTests: XCTestCase {
    private let payload = CapturePayload(title: "Synthetic link", url: URL(string: "https://example.test/buffer")!)

    private func withBuffer(sourceLookupResolver: ((CGPoint, SelectionCaptureSession) -> SourceCaptureLookup)? = nil,
                            _ body: (AppDelegate) -> Void) {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = [CapturePreferences.bufferEnabledKey, CapturePreferences.bufferPositionKey, "captureShortcut", "animationsEnabled", "overwriteClipboard"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        CapturePreferences.bufferEnabled = true
        CapturePreferences.bufferPosition = .leftBottom
        CapturePreferences.animationsEnabled = false
        CapturePreferences.overwriteClipboard = false
        CaptureShortcut.current = .defaultValue
        let delegate = AppDelegate(sourceLookupResolver: sourceLookupResolver ?? { _, _ in
            XCTFail("Buffered snapshots must not resolve the old source")
            return SourceCaptureLookup(candidate: nil, allowsMarquee: false)
        })
        delegate.captureEnabled = true
        defer { delegate.cancel(); delegate.bufferOverlay.close(); delegate.overlay.close() }
        body(delegate)
    }
    private func event(_ type: CGEventType, _ point: CGPoint, key: Int64 = 0) -> CGEvent {
        let event = CGEvent(source: nil)!
        event.type = type; event.location = point
        event.flags = []; event.setIntegerValueField(.keyboardEventKeycode, value: key)
        return event
    }
    private func fill(_ delegate: AppDelegate) -> CGPoint {
        delegate.buffer.store(payload, symbol: "link")
        delegate.bufferOverlay.refresh(item: delegate.buffer.item)
        let frame = delegate.bufferOverlay.targetFrame!
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Exercise the actual physical-press route; no native drop owns the caret.
    @discardableResult private func lift(_ delegate: AppDelegate, at point: CGPoint) -> Bool {
        let id = delegate.buffer.item!.id
        XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, point)))
        XCTAssertFalse(delegate.bufferNativePress)
        XCTAssertFalse(delegate.nativeBufferDrag.isActive)
        XCTAssertTrue(delegate.swallowedMouseDown)
        XCTAssertEqual(delegate.bufferDragID, id)
        XCTAssertEqual(delegate.state.phase, .dragging)
        return delegate.bufferDragID == id
    }

    func testExpandingNotchDoesNotRevealClippedControlLines() {
        for height: CGFloat in [0, 2, 12, 32, 54] {
            XCTAssertEqual(BufferMotion.contentOpacity(visibleHeight: height, fullHeight: 108), 0)
        }
        var previous: CGFloat = 0
        for height in stride(from: CGFloat(54), through: 108, by: 1) {
            let opacity = BufferMotion.contentOpacity(visibleHeight: height, fullHeight: 108)
            XCTAssertGreaterThanOrEqual(opacity, previous)
            XCTAssertLessThanOrEqual(opacity, 1)
            previous = opacity
        }
        XCTAssertEqual(previous, 1)
    }
    func testIslandSurfaceStaysInvisibleWhileItWouldBeAThinLine() {
        for safeTop: CGFloat in [0, 32, 38] {
            let screen = CGRect(x: -1440, y: 900, width: 1440, height: 900)
            let shown = bufferFrame(position: .notch, screen: screen, visibleFrame: screen,
                                    safeAreaTop: safeTop, notchWidth: safeTop == 0 ? 0 : 180)
            let hidden = BufferMotion.hiddenFrame(position: .notch, shown: shown, screen: screen,
                                                   safeAreaTop: safeTop, notchWidth: safeTop == 0 ? 0 : 180)
            XCTAssertEqual(BufferMotion.surfaceOpacity(frameHeight: hidden.height, shownHeight: shown.height), 0)
            for exposed: CGFloat in [0, 1, 2, 8, 18] {
                XCTAssertEqual(BufferMotion.surfaceOpacity(frameHeight: safeTop + exposed, shownHeight: shown.height), 0)
            }
            var previous: CGFloat = 0
            for tick in 0...120 {
                let progress = BufferMotion.progress(CGFloat(tick) / 120, position: .notch)
                let frame = BufferMotion.frame(from: hidden, to: shown, progress: progress)
                let opacity = BufferMotion.surfaceOpacity(frameHeight: frame.height, shownHeight: shown.height)
                XCTAssertGreaterThanOrEqual(opacity, previous)
                XCTAssertLessThanOrEqual(opacity, 1)
                previous = opacity
            }
            XCTAssertEqual(previous, 1)
        }
    }
    func testIslandReversalKeepsSurfaceOpacityContinuousAndExitHidesTheLine() {
        let shownHeight: CGFloat = 140
        let start = CGRect(x: 0, y: 0, width: 180, height: 59)
        let hidden = CGRect(x: 0, y: 27, width: 180, height: 32)
        let initialOpacity = BufferMotion.surfaceOpacity(frameHeight: start.height, shownHeight: shownHeight)
        XCTAssertGreaterThan(initialOpacity, 0)
        XCTAssertLessThan(initialOpacity, 1)
        var previous = initialOpacity
        for tick in 0...120 {
            let frame = BufferMotion.frame(from: start, to: hidden,
                                           progress: BufferMotion.progress(CGFloat(tick) / 120, position: .notch))
            let opacity = BufferMotion.surfaceOpacity(frameHeight: frame.height, shownHeight: shownHeight)
            XCTAssertLessThanOrEqual(opacity, previous)
            XCTAssertGreaterThanOrEqual(opacity, 0)
            previous = opacity
        }
        XCTAssertEqual(previous, 0)
    }
    func testDefaultsOffAndDefaultPositionAndExplicitChoicesPersist() {
        let defaults = UserDefaults.standard
        let keys = [CapturePreferences.bufferEnabledKey, CapturePreferences.bufferPositionKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        keys.forEach { defaults.removeObject(forKey: $0) }
        XCTAssertFalse(CapturePreferences.bufferEnabled)
        XCTAssertEqual(CapturePreferences.bufferPosition, .notch)
        XCTAssertEqual(CapturePreferences.bufferPosition.title, "Dynamic Island")
        CapturePreferences.bufferEnabled = true
        XCTAssertTrue(defaults.bool(forKey: CapturePreferences.bufferEnabledKey))
        for position in BufferPosition.allCases {
            CapturePreferences.bufferPosition = position
            XCTAssertEqual(CapturePreferences.bufferPosition, position)
        }
        defaults.set("obsolete-position", forKey: CapturePreferences.bufferPositionKey)
        XCTAssertEqual(CapturePreferences.bufferPosition, .notch)
    }
    func testDeliberateDropReplacesFullBufferAndOldReceiptCannotRemoveReplacement() {
        withBuffer { delegate in
            let point = fill(delegate)
            let oldID = delegate.buffer.item!.id
            delegate.state = CaptureState(); delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.captured = CaptureCandidate(payload: .init(title: "Replacement", markdown: "Replacement"), frame: .zero)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, point)))
            XCTAssertEqual(delegate.buffer.item?.payload.text, "Replacement")
            XCTAssertNotEqual(delegate.buffer.item?.id, oldID)
            let newID = delegate.buffer.item?.id
            delegate.bufferItemFinished(id: oldID, confirmed: true)
            delegate.bufferItemFinished(id: oldID, confirmed: false)
            XCTAssertEqual(delegate.buffer.item?.id, newID)
        }
    }
    func testCancelledReplacementKeepsExistingContent() {
        withBuffer { delegate in
            _ = fill(delegate)
            let id = delegate.buffer.item?.id
            delegate.state = CaptureState(); delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.captured = CaptureCandidate(payload: .init(title: "Replacement", markdown: "Replacement"), frame: .zero)
            delegate.cancel()
            XCTAssertEqual(delegate.buffer.item?.id, id)
        }
    }
    func testNotchAnimationKeepsNativeWindowFrameFixedThroughReversal() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = [CapturePreferences.bufferEnabledKey, CapturePreferences.bufferPositionKey, "animationsEnabled"]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) } }
        CapturePreferences.bufferEnabled = true
        CapturePreferences.bufferPosition = .notch
        CapturePreferences.animationsEnabled = true
        let previousWindows = Set(NSApp.windows.map(\.windowNumber))
        let overlay = BufferOverlay()
        defer { overlay.close() }
        overlay.beginCapture(at: .zero)
        guard let window = NSApp.windows.first(where: { !previousWindows.contains($0.windowNumber) && $0.level == CaptureWindowLayers.buffer }) else {
            return XCTFail("Buffer window missing")
        }
        let frame = window.frame
        XCTAssertGreaterThanOrEqual(frame.height, BufferLayout.contentHeight)
        for tick in 0..<30 {
            if tick == 6 { overlay.endCapture() }
            if tick == 9 { overlay.beginCapture(at: .zero) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            XCTAssertEqual(window.frame, frame, "Only the surface should resize, never the native window")
        }
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 1, accuracy: 0.001)
        XCTAssertNotNil(overlay.targetFrame)
    }
    func testShortcutShowsEmptyBufferBeforeAnySourceResolvesAndReleaseHidesIt() {
        withBuffer(sourceLookupResolver: { _, _ in SourceCaptureLookup(candidate: nil, allowsMarquee: false) }) { delegate in
            let point = CGPoint(x: 500, y: 500)
            let down = event(.flagsChanged, point)
            down.flags = [.maskAlternate, .maskCommand]
            _ = delegate.handle(.flagsChanged, down)
            XCTAssertEqual(delegate.state.phase, .armed)
            XCTAssertNil(delegate.candidate)
            XCTAssertNotNil(delegate.bufferOverlay.targetFrame, "The shortcut reveals Buffer synchronously, even over empty space")
            _ = delegate.handle(.flagsChanged, event(.flagsChanged, point))
            XCTAssertNil(delegate.bufferOverlay.targetFrame)
            delegate.bufferOverlay.showCaptureTarget(at: point)
            XCTAssertNil(delegate.bufferOverlay.targetFrame, "A stale source result must not reopen an ended capture")
        }
    }
    func testShortcutDoesNotShowBufferWhenTheSettingIsOff() {
        withBuffer(sourceLookupResolver: { _, _ in SourceCaptureLookup(candidate: nil, allowsMarquee: false) }) { delegate in
            CapturePreferences.bufferEnabled = false
            let down = event(.flagsChanged, CGPoint(x: 500, y: 500))
            down.flags = [.maskAlternate, .maskCommand]
            _ = delegate.handle(.flagsChanged, down)
            XCTAssertNil(delegate.bufferOverlay.targetFrame)
        }
    }
    func testOnlyConfirmedMatchingDeliveryRemovesItemAndSnapshotKeepsMarkdown() {
        var buffer = CaptureBuffer()
        XCTAssertTrue(buffer.store(payload, symbol: "link"))
        let item = buffer.item!
        XCTAssertEqual(item.payload.text, "[Synthetic link](https://example.test/buffer)")
        XCTAssertEqual(item.symbol, "link")
        XCTAssertFalse(buffer.store(.init(title: "Other", markdown: "Other"), symbol: "text.alignleft"))
        buffer.finishDelivery(id: item.id, confirmed: false)
        XCTAssertEqual(buffer.item?.id, item.id)
        buffer.finishDelivery(id: UUID(), confirmed: true)
        XCTAssertEqual(buffer.item?.id, item.id)
        buffer.finishDelivery(id: item.id, confirmed: true)
        XCTAssertNil(buffer.item)
        buffer.store(payload, symbol: "link")
        let newID = buffer.item?.id
        buffer.finishDelivery(id: item.id, confirmed: true)
        XCTAssertEqual(buffer.item?.id, newID)
    }
    private func nativePlan(at point: CGPoint) -> NativeDropPlan {
        let target = InputTarget(element: AXUIElementCreateApplication(getpid()), app: .current,
                                 frame: CGRect(x: point.x - 100, y: point.y - 20, width: 200, height: 40),
                                 dropPoint: point, insertionRange: CFRange(location: 0, length: 0), caretFrame: .zero)
        // Intentionally no readable editor/context: receiver acceptance, rather
        // than a later AX value match, must settle the Buffer item.
        return NativeDropPlan(target: target, expectedEdits: [])
    }
    func testAcceptedNativeReceiptEmptiesSlotBeforeNextShortcutWithEitherClipboardPreference() {
        for overwrite in [false, true] {
            withBuffer(sourceLookupResolver: { _, _ in SourceCaptureLookup(candidate: nil, allowsMarquee: false) }) { delegate in
                CapturePreferences.overwriteClipboard = overwrite
                let point = fill(delegate)
                let transfer = NativeBufferDrag.Transfer(item: delegate.buffer.item!, frame: delegate.bufferOverlay.targetFrame!,
                                                         clipboardRevision: NSPasteboard.general.changeCount)
                XCTAssertTrue(lift(delegate, at: point))
                let token = CaptureCommitToken(); token.recordDispatched(); delegate.deliveryToken = token
                delegate.finishNativeBufferDrag(transfer, at: point, operation: .copy, plan: nativePlan(at: point))
                XCTAssertNil(delegate.buffer.item)
                XCTAssertNil(delegate.bufferDragID)
                XCTAssertFalse(delegate.dropping, "Optional clipboard verification cannot block the next capture")
                let multiselect = CapturePreferences.multiselectEnabled
                CapturePreferences.multiselectEnabled = false
                defer { CapturePreferences.multiselectEnabled = multiselect }
                let shortcut = event(.flagsChanged, point)
                shortcut.flags = [.maskAlternate, .maskCommand]
                _ = delegate.handle(.flagsChanged, shortcut)
                XCTAssertEqual(delegate.state.phase, .armed)
                XCTAssertNil(delegate.buffer.item, "A new shortcut must reveal an empty slot")
                XCTAssertNotNil(delegate.bufferOverlay.targetFrame)
                delegate.cancel()
                XCTAssertTrue(delegate.buffer.store(.init(title: "New item", markdown: "New item"), symbol: "text.alignleft"))
                let newer = delegate.buffer.item!.id
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                XCTAssertEqual(delegate.buffer.item?.id, newer, "Late optional verification cannot restore the consumed snapshot or remove a new one")
            }
        }
    }
    func testNativeRejectedOrUnauthorizedReceiptKeepsStoredItem() {
        for authorized in [false, true] {
            withBuffer { delegate in
                let point = fill(delegate), id = delegate.buffer.item!.id
                let transfer = NativeBufferDrag.Transfer(item: delegate.buffer.item!, frame: delegate.bufferOverlay.targetFrame!,
                                                         clipboardRevision: NSPasteboard.general.changeCount)
                XCTAssertTrue(lift(delegate, at: point))
                let token = CaptureCommitToken()
                if authorized { token.recordDispatched() }
                delegate.deliveryToken = token
                delegate.finishNativeBufferDrag(transfer, at: point, operation: authorized ? [] : .copy,
                                                plan: authorized ? nativePlan(at: point) : nil)
                XCTAssertEqual(delegate.buffer.item?.id, id)
                delegate.bufferOverlay.beginCapture(at: point)
                XCTAssertNotNil(delegate.bufferOverlay.targetFrame)
            }
        }
    }
    func testClickAfterPasteDispatchDoesNotRestoreBufferWhileVerificationIsPending() {
        withBuffer { delegate in
            let point = fill(delegate)
            let id = delegate.buffer.item!.id
            _ = lift(delegate, at: point)
            _ = delegate.state.drop(valid: true); delegate.swallowedMouseDown = false
            let token = CaptureCommitToken(); delegate.deliveryToken = token; delegate.dropping = true
            XCTAssertTrue(token.dispatch {})
            let input = CGPoint(x: 900, y: 400)
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, input)), "The click reaches the input")
            XCTAssertTrue(token.isValid, "Read-only verification continues after the click")
            XCTAssertNil(delegate.bufferOverlay.containerFrame, "A click before the dispatch receipt must not restore the hidden item")
            delegate.bufferItemDispatched(id: id)
            XCTAssertEqual(delegate.buffer.item?.id, id, "Dispatch keeps a recovery snapshot")
            delegate.bufferItemFinished(id: id, confirmed: false)
            delegate.cancel()
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
            XCTAssertEqual(delegate.buffer.item?.id, id)
            XCTAssertTrue(delegate.buffer.item?.deliveryUnconfirmed == true)
            delegate.sourceApplicationDidChange()
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
            delegate.bufferOverlay.beginCapture(at: input)
            XCTAssertNotNil(delegate.bufferOverlay.targetFrame, "Only a fresh capture reveals recovery")
            delegate.bufferItemFinished(id: id, confirmed: true)
            XCTAssertNil(delegate.buffer.item)
        }
    }
    func testInputBeforeDispatchCancelsPasteAndReturnsItemToBuffer() {
        withBuffer { delegate in
            let point = fill(delegate)
            let id = delegate.buffer.item!.id
            _ = lift(delegate, at: point)
            _ = delegate.state.drop(valid: true); delegate.swallowedMouseDown = false
            let token = CaptureCommitToken(); delegate.deliveryToken = token; delegate.dropping = true
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, CGPoint(x: 900, y: 400))))
            XCTAssertTrue(token.isCancelled)
            XCTAssertFalse(token.dispatch { XCTFail("A cancelled pending drop must never post Paste") })
            XCTAssertEqual(delegate.buffer.item?.id, id)
            XCTAssertNotNil(delegate.bufferOverlay.containerFrame)
        }
    }
    func testCancellationAfterDispatchBeforeReceiptRetainsRecoveryAndLateReceiptsCannotTouchNewItem() {
        withBuffer { delegate in
            let point = fill(delegate)
            let id = delegate.buffer.item!.id
            _ = lift(delegate, at: point)
            let token = CaptureCommitToken(); delegate.deliveryToken = token
            XCTAssertTrue(token.dispatch {})
            delegate.cancel()
            XCTAssertEqual(delegate.buffer.item?.id, id)
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
            delegate.closeBuffer()
            delegate.bufferOverlay.beginCapture(at: point)
            delegate.buffer.store(.init(title: "New item", markdown: "New item"), symbol: "text.alignleft")
            let newer = delegate.buffer.item!.id
            delegate.bufferOverlay.refresh(item: delegate.buffer.item)
            delegate.bufferItemDispatched(id: id)
            delegate.bufferItemFinished(id: id, confirmed: true)
            XCTAssertEqual(delegate.buffer.item?.id, newer)
            XCTAssertNotNil(delegate.bufferOverlay.containerFrame)
        }
    }
    func testClosingStoredBufferDoesNotCancelAlreadyPostedDirectDelivery() {
        withBuffer { delegate in
            _ = fill(delegate)
            let token = CaptureCommitToken()
            delegate.deliveryToken = token; delegate.dropping = true
            _ = delegate.state.drop(valid: true)
            XCTAssertTrue(token.dispatch {})
            let frame = delegate.bufferOverlay.closeFrame!
            let point = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, point)))
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, point)))
            XCTAssertTrue(token.isValid, "Closing the unrelated shelf must let read-only cleanup finish")
            XCTAssertTrue(delegate.dropping)
            XCTAssertNil(delegate.buffer.item)
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
        }
    }
    func testClosingBufferStillCancelsBeforePasteDispatch() {
        withBuffer { delegate in
            _ = fill(delegate)
            let token = CaptureCommitToken()
            delegate.deliveryToken = token; delegate.dropping = true
            delegate.closeBuffer()
            XCTAssertFalse(token.dispatch { XCTFail("Closing before dispatch must cancel the pending edit") })
            XCTAssertNil(delegate.buffer.item)
        }
    }
    func testIdleStoredCornerColorsFollowEffectiveAppearanceWithoutHover() throws {
        var failure: Error?
        withBuffer { delegate in
            let previous = NSApp.appearance
            defer { NSApp.appearance = previous }
            do {
                NSApp.appearance = NSAppearance(named: .darkAqua)
                _ = fill(delegate)
                func findSlot(_ view: NSView) -> NSView? {
                    if view.accessibilityLabel()?.hasPrefix("Buffered content.") == true { return view }
                    return view.subviews.compactMap { findSlot($0) }.first
                }
                let panel = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.level == CaptureWindowLayers.buffer })
                let slot = try XCTUnwrap(panel.contentView.flatMap { findSlot($0) })
                let border = try XCTUnwrap(slot.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
                let before = try XCTUnwrap(border.strokeColor)
                NSApp.appearance = NSAppearance(named: .aqua); NSApp.updateWindows()
                let changed = expectation(description: "Appearance propagated")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { changed.fulfill() }
                wait(for: [changed], timeout: 1)
                XCTAssertEqual(slot.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
                XCTAssertFalse(CFEqual(before, try XCTUnwrap(border.strokeColor)))
            } catch { failure = error }
        }
        if let failure { throw failure }
    }
    func testSourceDropStoresAndShortcutReleaseAndAppSwitchRetainItem() {
        withBuffer { delegate in
            delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.captured = CaptureCandidate(payload: payload, frame: .init(x: 400, y: 300, width: 200, height: 30))
            delegate.bufferOverlay.beginCapture(at: .zero)
            delegate.bufferOverlay.showCaptureTarget(at: .zero)
            let frame = delegate.bufferOverlay.targetFrame!
            let point = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, point)))
            XCTAssertEqual(delegate.buffer.item?.payload.text, payload.text)
            XCTAssertNil(delegate.captured)
            _ = delegate.handle(.flagsChanged, event(.flagsChanged, point))
            delegate.sourceApplicationDidChange()
            XCTAssertNotNil(delegate.buffer.item)
            XCTAssertNotNil(delegate.bufferOverlay.targetFrame)
        }
    }
    func testNoShortcutDragAndEscapeOrInvalidDropRetainItem() {
        withBuffer { delegate in
            let point = fill(delegate)
            let id = delegate.buffer.item!.id
            XCTAssertTrue(lift(delegate, at: point))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertEqual(delegate.bufferDragID, id)
            XCTAssertNil(delegate.captured)
            XCTAssertNil(delegate.bufferOverlay.containerFrame, "The container disappears immediately when its item is lifted")
            XCTAssertNotNil(delegate.overlay.dragHintFrame, "Lifting a stored item must reveal the same visible drag hint as capture")
            _ = delegate.handle(.flagsChanged, event(.flagsChanged, point))
            XCTAssertEqual(delegate.state.phase, .dragging)
            XCTAssertTrue(delegate.handle(.keyDown, event(.keyDown, point, key: 53)))
            XCTAssertEqual(delegate.buffer.item?.id, id)
            XCTAssertNotNil(delegate.bufferOverlay.containerFrame, "Cancelling returns the item to its slot")
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, point))
            XCTAssertTrue(lift(delegate, at: point))
            let outside = CGPoint(x: -9000, y: -9000)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, outside)))
            XCTAssertEqual(delegate.buffer.item?.id, id)
            XCTAssertNil(delegate.bufferDragID)
        }
    }
    func testCloseClearsContentConsumesOnlyPairedClickAndNewCaptureCanReopen() {
        withBuffer { delegate in
            _ = fill(delegate)
            let frame = delegate.bufferOverlay.closeFrame!
            let close = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(delegate.bufferOverlay.closeContains(close))
            XCTAssertFalse(delegate.bufferOverlay.slotContains(close), "The close control belongs to the header, outside the content slot")
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, close)))
            XCTAssertNil(delegate.buffer.item)
            XCTAssertNil(delegate.bufferOverlay.targetFrame)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, close)))
            XCTAssertFalse(delegate.handle(.leftMouseDown, event(.leftMouseDown, .zero)))
            delegate.bufferOverlay.beginCapture(at: .zero)
            delegate.bufferOverlay.showCaptureTarget(at: .zero)
            XCTAssertNotNil(delegate.bufferOverlay.targetFrame)
        }
    }
    func testSourcePendingValidationCannotBeStored() {
        withBuffer { delegate in
            delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.validatingSource = true
            delegate.captured = CaptureCandidate(payload: payload, frame: .zero)
            delegate.bufferOverlay.beginCapture(at: .zero)
            delegate.bufferOverlay.showCaptureTarget(at: .zero)
            let frame = delegate.bufferOverlay.targetFrame!
            let point = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, point)))
            XCTAssertNil(delegate.buffer.item)
        }
    }
    func testCornersRespectVisibleFrameAndNotchReservesCameraOnOffsetScreen() {
        let screen = CGRect(x: -1728, y: 200, width: 1728, height: 1117)
        let visible = screen.insetBy(dx: 0, dy: 38)
        for position in BufferPosition.allCases where position != .notch {
            let frame = bufferFrame(position: position, screen: screen, visibleFrame: visible, safeAreaTop: 38)
            XCTAssertTrue(visible.contains(frame))
            XCTAssertEqual(frame.height, 108)
            XCTAssertEqual(position == .leftBottom || position == .leftTop ? frame.minX : frame.maxX,
                           position == .leftBottom || position == .leftTop ? visible.minX + 20 : visible.maxX - 20)
        }
        let notch = bufferFrame(position: .notch, screen: screen, visibleFrame: visible, safeAreaTop: 38, notchWidth: 300)
        XCTAssertEqual(notch.maxY, screen.maxY)
        XCTAssertEqual(notch.midX, screen.midX)
        XCTAssertEqual(notch.width, 332)
        XCTAssertEqual(notch.height, 146)
        let noNotch = bufferFrame(position: .notch, screen: screen, visibleFrame: visible, safeAreaTop: 0)
        XCTAssertEqual(noNotch.height, 108)
    }
    func testEdgeMotionStartsOutsideTheCorrectSideWithoutVerticalMovement() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        for position in [BufferPosition.leftBottom, .leftTop, .rightBottom, .rightTop] {
            let shown = bufferFrame(position: position, screen: screen, visibleFrame: screen.insetBy(dx: 0, dy: 30), safeAreaTop: 30)
            let hidden = BufferMotion.hiddenFrame(position: position, shown: shown, screen: screen, safeAreaTop: 30, notchWidth: 180)
            if position == .leftBottom || position == .leftTop { XCTAssertLessThan(hidden.maxX, screen.minX) }
            else { XCTAssertGreaterThan(hidden.minX, screen.maxX) }
            XCTAssertEqual(hidden.minY, shown.minY)
            XCTAssertEqual(hidden.size, shown.size)
            for t in stride(from: CGFloat(0), through: 1, by: 0.1) {
                let p = BufferMotion.progress(t, position: position)
                XCTAssertTrue((0...1).contains(p), "Edge motion must not wobble or overshoot")
                let frame = BufferMotion.frame(from: hidden, to: shown, progress: p)
                XCTAssertEqual(frame.minY, shown.minY)
            }
        }
    }
    func testTopNotchMotionRemainsJoinedToTheTopEdgeWhileExpanding() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let shown = bufferFrame(position: .notch, screen: screen, visibleFrame: screen, safeAreaTop: 32, notchWidth: 180)
        let hidden = BufferMotion.hiddenFrame(position: .notch, shown: shown, screen: screen, safeAreaTop: 32, notchWidth: 180)
        XCTAssertEqual(hidden.height, 32)
        XCTAssertEqual(hidden.width, 180)
        for t in stride(from: CGFloat(0), through: 1, by: 0.05) {
            let frame = BufferMotion.frame(from: hidden, to: shown, progress: BufferMotion.progress(t, position: .notch))
            XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
            XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
        }
        XCTAssertEqual(BufferMotion.progress(1, position: .notch), 1)
    }
    func testNotchExpansionArrivesOnceWithoutASecondSettlingMovement() {
        var previous: CGFloat = 0
        for t in stride(from: CGFloat(0), through: 1, by: 0.01) {
            let progress = BufferMotion.progress(t, position: .notch)
            XCTAssertTrue((0...1).contains(progress))
            XCTAssertGreaterThanOrEqual(progress, previous)
            previous = progress
        }
        XCTAssertGreaterThan(BufferMotion.progress(0.75, position: .notch), 0.995)
        XCTAssertEqual(BufferMotion.progress(0, position: .notch), 0)
        XCTAssertEqual(BufferMotion.progress(1, position: .notch), 1)
    }
    func testReopeningDuringExitCannotBeHiddenByTheOldAnimation() {
        withBuffer { delegate in
            CapturePreferences.animationsEnabled = true
            let point = CGPoint(x: 400, y: 300)
            delegate.bufferOverlay.beginCapture(at: point)
            delegate.bufferOverlay.showCaptureTarget(at: point)
            delegate.bufferOverlay.endCapture()
            delegate.bufferOverlay.beginCapture(at: point)
            delegate.bufferOverlay.showCaptureTarget(at: point)
            let settled = expectation(description: "Reversed entrance settles")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
            XCTAssertNotNil(delegate.bufferOverlay.targetFrame)
            delegate.bufferOverlay.endCapture()
            XCTAssertNil(delegate.bufferOverlay.targetFrame, "An exiting panel stops accepting drops immediately")
            let hidden = expectation(description: "Exit settles")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hidden.fulfill() }
            wait(for: [hidden], timeout: 2)
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
        }
    }
    func testHeaderIsNeitherADropTargetNorADragHandle() {
        withBuffer { delegate in
            let point = fill(delegate)
            let slot = delegate.bufferOverlay.targetFrame!
            let container = delegate.bufferOverlay.containerFrame!
            XCTAssertTrue(container.contains(slot))
            XCTAssertEqual(slot.height, 48)
            let header = CGPoint(x: container.minX + 70, y: container.minY + 22)
            XCTAssertTrue(delegate.bufferOverlay.contains(header))
            XCTAssertFalse(delegate.bufferOverlay.slotContains(header))
            XCTAssertFalse(delegate.bufferOverlay.closeContains(header))
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, header)))
            XCTAssertNotEqual(delegate.state.phase, .dragging)
            XCTAssertNotNil(delegate.buffer.item)
            _ = delegate.handle(.leftMouseUp, event(.leftMouseUp, header))
            delegate.closeBuffer()
            delegate.bufferOverlay.beginCapture(at: point)
            delegate.bufferOverlay.showCaptureTarget(at: point)
            delegate.state = CaptureState(); delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.captured = CaptureCandidate(payload: payload, frame: .zero)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, header)))
            XCTAssertNil(delegate.buffer.item, "Dropping on the header must not fill the slot")
        }
    }
    func testRaisedHintRemainsTransparentToSourceAndDestinationHitTesting() {
        let point = CGPoint(x: 140, y: 120)
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let ownPID: pid_t = 101
        let hint = HitTestWindow(pid: ownPID, layer: CaptureWindowLayers.hint.rawValue, frame: frame)
        let editor = HitTestWindow(pid: 202, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([hint, editor], at: point, ownPID: ownPID), .application(202))
        let buffer = HitTestWindow(pid: ownPID, layer: CaptureWindowLayers.buffer.rawValue, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([hint, buffer, editor], at: point, ownPID: ownPID), .blocked)
        let settings = HitTestWindow(pid: ownPID, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([hint, settings, editor], at: point, ownPID: ownPID), .application(ownPID))
    }
    func testHintLiftsFromSlotAndIsAboveBufferAndInterruptedParkingCannotResurrectClosedItem() {
        withBuffer { delegate in
            let point = fill(delegate)
            let frame = delegate.bufferOverlay.targetFrame!
            CapturePreferences.animationsEnabled = true
            XCTAssertTrue(lift(delegate, at: point))
            XCTAssertEqual(delegate.overlay.dragHintFrame, frame, "The first morph frame starts at the actual slot")
            XCTAssertGreaterThan(CaptureWindowLayers.hint.rawValue, CaptureWindowLayers.buffer.rawValue)
            delegate.cancel()
            delegate.closeBuffer()
            delegate.bufferOverlay.beginCapture(at: point); delegate.bufferOverlay.showCaptureTarget(at: point)
            delegate.state = CaptureState(); delegate.state.modifiers(held: true); delegate.state.begin()
            delegate.captured = CaptureCandidate(payload: payload, frame: .zero)
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, point)))
            XCTAssertNotNil(delegate.buffer.item, "The payload is retained before the merge animation finishes")
            XCTAssertTrue(delegate.dropping)
            let closeFrame = delegate.bufferOverlay.closeFrame!
            let close = CGPoint(x: closeFrame.midX, y: closeFrame.midY)
            XCTAssertTrue(delegate.handle(.leftMouseDown, event(.leftMouseDown, close)), "Closing during merge must consume the click")
            XCTAssertTrue(delegate.handle(.leftMouseUp, event(.leftMouseUp, close)))
            let drained = expectation(description: "Obsolete parking animation drained")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertNil(delegate.buffer.item)
            XCTAssertNil(delegate.bufferOverlay.containerFrame)
            XCTAssertFalse(delegate.dropping)
        }
    }
}
