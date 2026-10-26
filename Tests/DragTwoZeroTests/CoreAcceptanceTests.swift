import AppKit
import XCTest
@testable import DragTwoZero

final class CoreAcceptanceTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
    private let point = CGPoint(x: 20, y: 20)
    private let ownPID: pid_t = 10
    private let overlayLayer = 201

    func testExternalFloatingSurfaceBlocksUnderlyingEditor() {
        let windows = [HitTestWindow(pid: 20, layer: 3, frame: frame),
                       HitTestWindow(pid: 30, layer: 0, frame: frame)]
        XCTAssertEqual(WindowHitPolicy.resolve(windows, at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .blocked)
    }

    func testReservedCursorLayerDoesNotOccludeEditorButFloatingAndRecordingStillDo() {
        let cursorLayer = Int(CGWindowLevelForKey(.cursorWindow))
        let cursor = HitTestWindow(pid: 1, layer: cursorLayer, frame: frame)
        let editor = HitTestWindow(pid: 30, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([cursor, editor], at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .application(30))
        for layer in [3, 1499, cursorLayer - 1] {
            let occluder = HitTestWindow(pid: 20, layer: layer, frame: frame)
            XCTAssertEqual(WindowHitPolicy.resolve([cursor, occluder, editor], at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .blocked)
        }
    }

    func testOwnCaptureOverlayIsSkippedButOwnSettingsOccludes() {
        let editor = HitTestWindow(pid: 30, layer: 0, frame: frame)
        let overlay = HitTestWindow(pid: ownPID, layer: overlayLayer, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, editor], at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .application(30))
        let settings = HitTestWindow(pid: ownPID, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([overlay, settings, editor], at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .application(ownPID))
    }

    func testNoninteractiveTransparentAndNonoverlappingWindowsDoNotBlock() {
        let transparent = HitTestWindow(pid: 20, layer: 3, frame: frame, alpha: 0)
        let elsewhere = HitTestWindow(pid: 20, layer: 3, frame: frame.offsetBy(dx: 500, dy: 0))
        let editor = HitTestWindow(pid: 30, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([transparent, elsewhere, editor], at: point, ownPID: ownPID, captureOverlayLayer: overlayLayer), .application(30))
    }

    private func block(_ text: String, pid: pid_t, visible: Bool, page: String = "https://example.test/a") -> CaptureCandidate {
        var block = CaptureCandidate(payload: .init(title: text, markdown: text), frame: frame)
        block.anchor = AXUIElementCreateApplication(pid)
        block.context = CaptureElementContext(window: AXUIElementCreateApplication(100), document: nil, documentURL: page)
        if !visible { block.clipFrame = .zero }
        return block
    }

    func testVisibleAndOffscreenSelectionMembersUseTheirRespectiveResolvers() {
        let visible = block("Visible", pid: 30, visible: true)
        let hidden = block("Retained", pid: 31, visible: false)
        var hitTests = 0, retainedReads = 0
        let result = SelectionSourceValidation.resolve([visible, hidden], visibleSource: { _ in
            hitTests += 1; return visible
        }, retainedSource: { anchor in
            XCTAssertTrue(CFEqual(anchor, hidden.anchor!))
            retainedReads += 1; return hidden
        })
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(combinedSelection(result ?? [])?.payload.text, "Visible\n\nRetained")
        XCTAssertEqual(hitTests, 1)
        XCTAssertEqual(retainedReads, 1)
    }

    func testOffscreenRecycledAnchorChangedContentOrContextRejectsWholeSelection() {
        let expected = block("Retained", pid: 31, visible: false)
        for changed in [block("New content", pid: 31, visible: false),
                        block("Retained", pid: 32, visible: false),
                        block("Retained", pid: 31, visible: false, page: "https://example.test/b")] {
            XCTAssertNil(SelectionSourceValidation.resolve([expected], visibleSource: { _ in XCTFail("offscreen must not hit test"); return nil }, retainedSource: { _ in changed }))
        }
        XCTAssertNil(SelectionSourceValidation.resolve([expected], visibleSource: { _ in nil }, retainedSource: { _ in nil }))
    }

    func testVisibleOcclusionStillRejectsEvenWhenRetainedAnchorIsReadable() {
        let expected = block("Visible", pid: 30, visible: true)
        XCTAssertNil(SelectionSourceValidation.resolve([expected], visibleSource: { _ in nil }, retainedSource: { _ in expected }))
    }

    func testDestinationSelectionPreservesIntentionalReplacementAndOriginalValue() {
        let element = AXUIElementCreateApplication(30)
        let authorized = InputTarget(element: element, app: .current, frame: frame, dropPoint: point,
                                     insertionRange: CFRange(location: 2, length: 4), caretFrame: .zero,
                                     selectionValue: "Original draft")
        var newer = authorized
        newer.insertionRange = CFRange(location: 9, length: 0)
        newer.selectionValue = "Newer draft"
        let preserved = newer.preservingSelection(from: authorized)
        XCTAssertEqual(preserved.insertionRange?.location, 2)
        XCTAssertEqual(preserved.insertionRange?.length, 4)
        XCTAssertEqual(preserved.selectionValue, "Original draft")
    }

    func testSelectionRangeUsesUTF16BoundsAndRejectsInvalidOrOverflowingRanges() {
        let value = "A😀BC"
        XCTAssertEqual(InputTarget.validatedSelectionRange(CFRange(location: 1, length: 2), value: value)?.length, 2)
        XCTAssertEqual(InputTarget.validatedSelectionRange(CFRange(location: 5, length: 0), value: value)?.location, 5)
        for range in [CFRange(location: -1, length: 0), CFRange(location: 1, length: -1),
                      CFRange(location: 6, length: 0), CFRange(location: 2, length: Int.max)] {
            XCTAssertNil(InputTarget.validatedSelectionRange(range, value: value))
        }
    }
}
