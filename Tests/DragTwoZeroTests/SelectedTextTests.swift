import AppKit
import XCTest
@testable import DragTwoZero

final class SelectedTextTests: XCTestCase {
    func testPageAndScreenBoundsCannotBeDrawnAsOneSelectedLine() {
        let page = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let glyph = CGRect(x: 100, y: 100, width: 12, height: 24)
        XCTAssertFalse(SelectedTextGeometry.isTextLine(page, character: glyph, length: 40, container: page))
        XCTAssertFalse(SelectedTextGeometry.isTextLine(page, character: page, length: 40, container: page))
        XCTAssertFalse(SelectedTextGeometry.isTextLine(CGRect(x: 0, y: 100, width: 1440, height: 24), character: glyph, length: 1, container: page))
    }

    func testRealLineAllowsTallerEmojiButRejectsUnrelatedBounds() {
        let glyph = CGRect(x: 100, y: 100, width: 12, height: 24)
        XCTAssertTrue(SelectedTextGeometry.isTextLine(CGRect(x: 100, y: 96, width: 300, height: 36), character: glyph, length: 25, container: nil))
        XCTAssertFalse(SelectedTextGeometry.isTextLine(CGRect(x: 100, y: 200, width: 300, height: 24), character: glyph, length: 25, container: nil))
    }

    private func marker(_ bytes: [UInt8]) -> AXTextMarker {
        bytes.withUnsafeBufferPointer { AXTextMarkerCreate(kCFAllocatorDefault, $0.baseAddress!, $0.count) }
    }

    func testBrowserSelectionIdentityUsesBothOpaqueEndpoints() {
        let old = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([1, 2, 3]), marker([4, 5, 6]))
        let same = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([1, 2, 3]), marker([4, 5, 6]))
        let changed = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([1, 2, 3]), marker([4, 5, 7]))
        let reversed = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([4, 5, 6]), marker([1, 2, 3]))
        XCTAssertTrue(SelectedTextMarkers.sameRange(old, same))
        XCTAssertFalse(SelectedTextMarkers.sameRange(old, changed))
        XCTAssertFalse(SelectedTextMarkers.sameRange(old, reversed))
        XCTAssertFalse(SelectedTextMarkers.sameRange(old, nil))
    }

    func testBrowserRangeCannotBeReplacedByNativeRangeWithSameOffsetsAndText() {
        var browser = selection(), native = selection()
        browser.selectedTextMarkerRange = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([1]), marker([2]))
        XCTAssertFalse(browser.matchesRetainedSource(native))
        native.selectedTextMarkerRange = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([1]), marker([2]))
        XCTAssertTrue(browser.matchesRetainedSource(native))
        native.selectedTextMarkerRange = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker([3]), marker([4]))
        XCTAssertFalse(browser.matchesRetainedSource(native))
    }

    func testPartialWrappedSelectionRequestsOnlySelectedSegments() throws {
        var requested: [NSRange] = []
        let frames = try XCTUnwrap(SelectedTextGeometry.frames(for: CFRange(location: 3, length: 12), lineRange: { index in
            index < 10 ? CFRange(location: 0, length: 10) : CFRange(location: 10, length: 10)
        }, bounds: { range in
            requested.append(NSRange(location: range.location, length: range.length))
            return CGRect(x: (range.location % 10) * 8, y: (range.location / 10) * 20, width: range.length * 8, height: 18)
        }))
        XCTAssertEqual(requested, [NSRange(location: 3, length: 7), NSRange(location: 10, length: 5)])
        XCTAssertEqual(frames, [CGRect(x: 24, y: 0, width: 56, height: 18), CGRect(x: 0, y: 20, width: 40, height: 18)])
    }

    func testEndAtLineBoundaryDoesNotIncludeFollowingLine() {
        var calls = 0
        let frames = SelectedTextGeometry.frames(for: CFRange(location: 4, length: 6), lineRange: { _ in
            calls += 1
            return CFRange(location: 0, length: 10)
        }, bounds: { _ in CGRect(x: 30, y: 0, width: 50, height: 18) })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(frames?.count, 1)
    }

    func testInvalidOrMissingLineGeometryFailsClosed() {
        for line: CFRange? in [nil, CFRange(location: 0, length: 0), CFRange(location: 8, length: 5), CFRange(location: 0, length: 2), CFRange(location: 1, length: Int.max)] {
            XCTAssertNil(SelectedTextGeometry.frames(for: CFRange(location: 3, length: 5), lineRange: { _ in line }, bounds: { _ in .zero }))
        }
        XCTAssertNil(SelectedTextGeometry.frames(for: CFRange(location: 3, length: 5), lineRange: { _ in CFRange(location: 0, length: 10) }, bounds: { _ in nil }))
    }

    func testEmptyCaretAndOverflowAreRejected() {
        for range in [CFRange(location: 0, length: 0), CFRange(location: -1, length: 1), CFRange(location: Int.max, length: 2)] {
            XCTAssertNil(SelectedTextGeometry.frames(for: range, lineRange: { _ in XCTFail("invalid range was queried"); return nil }, bounds: { _ in nil }))
        }
    }

    func testCancelledAndOversizedGeometryStopWithoutPartialResult() {
        XCTAssertNil(SelectedTextGeometry.frames(for: CFRange(location: 0, length: 1), lineRange: { _ in XCTFail("cancelled work continued"); return nil }, bounds: { _ in nil }, shouldStop: { true }))
        var calls = 0
        XCTAssertNil(SelectedTextGeometry.frames(for: CFRange(location: 0, length: 513), lineRange: { index in
            calls += 1
            return CFRange(location: index, length: 1)
        }, bounds: { _ in CGRect(x: 0, y: 0, width: 10, height: 10) }))
        XCTAssertEqual(calls, 512)
    }

    func testBoundaryWithUpstreamAffinityAdvancesWithoutDroppingTheNextLineStart() throws {
        let frames = try XCTUnwrap(SelectedTextGeometry.frames(for: CFRange(location: 3, length: 12), lineRange: { index in
            index <= 10 ? CFRange(location: 0, length: 10) : CFRange(location: 10, length: 10)
        }, bounds: { range in
            CGRect(x: (range.location % 10) * 8, y: (range.location / 10) * 20, width: range.length * 8, height: 18)
        }))
        XCTAssertEqual(frames, [CGRect(x: 24, y: 0, width: 56, height: 18), CGRect(x: 0, y: 20, width: 40, height: 18)])
    }
    func testLineBreakGlyphsDoNotWidenSelectedGeometryButPayloadOffsetsStayUnchanged() {
        let units = Array("AB\r\nCD\nEF".utf16), selection = CFRange(location: 20, length: 9)
        let first = SelectedTextGeometry.visibleRange(CFRange(location: 20, length: 4), selection: selection, text: units)
        XCTAssertEqual(first.location, 20); XCTAssertEqual(first.length, 2)
        let second = SelectedTextGeometry.visibleRange(CFRange(location: 24, length: 3), selection: selection, text: units)
        XCTAssertEqual(second.location, 24); XCTAssertEqual(second.length, 2)
        XCTAssertEqual(String(decoding: units, as: UTF16.self), "AB\r\nCD\nEF")
    }

    func testGlyphMergingRetainsWrappedLineEdgesAndDoesNotBridgeUnselectedGaps() {
        let glyphs = [CGRect(x: 70, y: 10, width: 9, height: 18), CGRect(x: 79, y: 10, width: 8, height: 18),
                      CGRect(x: 10, y: 32, width: 8, height: 18), CGRect(x: 18, y: 32, width: 10, height: 18),
                      CGRect(x: 70, y: 32, width: 8, height: 18)]
        XCTAssertEqual(SelectedTextGeometry.mergeGlyphs(glyphs), [CGRect(x: 70, y: 10, width: 17, height: 18),
                      CGRect(x: 10, y: 32, width: 18, height: 18), CGRect(x: 70, y: 32, width: 8, height: 18)])
    }

    func testNativeCharacterProbeDoesNotCrossLinesAndKeepsEmojiSurrogatesTogether() {
        let text = Array("A\n🐈B".utf16), selected = CFRange(location: 20, length: 5)
        let ascii = SelectedTextGeometry.firstGlyphRange(CFRange(location: 20, length: 1), selection: selected, text: text)
        XCTAssertEqual(ascii.location, 20); XCTAssertEqual(ascii.length, 1)
        let emoji = SelectedTextGeometry.firstGlyphRange(CFRange(location: 22, length: 3), selection: selected, text: text)
        XCTAssertEqual(emoji.location, 22); XCTAssertEqual(emoji.length, 2)
    }

    private func selection(location: Int = 3) -> CaptureCandidate {
        let frames = [CGRect(x: 50, y: 20, width: 100, height: 18), CGRect(x: 10, y: 40, width: 80, height: 18)]
        var candidate = CaptureCandidate(payload: .init(title: "Selected text", markdown: "same selected text"), frame: frames[0].union(frames[1]))
        candidate.textFrames = frames
        candidate.selectedTextRange = CFRange(location: location, length: 18)
        candidate.anchor = AXUIElementCreateApplication(101)
        candidate.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: nil)
        return candidate
    }

    func testHoverAndDragRejectUnselectedSpaceInsideBoundingBox() {
        let candidate = selection()
        let gap = CGPoint(x: 20, y: 25)
        XCTAssertTrue(candidate.frame.contains(gap))
        XCTAssertFalse(candidate.containsVisiblePoint(gap))
        XCTAssertFalse(candidate.matchesCurrentSource(selection(), at: gap))
        XCTAssertTrue(candidate.matchesCurrentSource(selection(), at: CGPoint(x: 70, y: 45)))
    }

    func testChangedRangeIsRejectedEvenWithIdenticalSelectedText() {
        XCTAssertFalse(selection().matchesRetainedSource(selection(location: 30)))
        var wholeBlock = selection()
        wholeBlock.selectedTextRange = nil
        XCTAssertFalse(selection().matchesRetainedSource(wholeBlock))
    }

    func testClippingAndRepositioningPreserveIndividualLinesAndWholePayload() {
        let old = selection()
        let moved = old.repositioned(to: old.frame.offsetBy(dx: 0, dy: -20), clippedTo: CGRect(x: 0, y: 20, width: 200, height: 100))
        XCTAssertEqual(moved.visibleHighlightFrames, [CGRect(x: 10, y: 20, width: 80, height: 18)])
        XCTAssertFalse(moved.containsVisiblePoint(CGPoint(x: 70, y: 10)))
        XCTAssertEqual(moved.payload.text, old.payload.text)
        XCTAssertEqual(moved.selectedTextRange?.location, old.selectedTextRange?.location)
        XCTAssertTrue(old.matchesRetainedSource(moved))
    }

    func testMultipleLineHighlightsRemainOneCompleteDragPayload() {
        let candidate = selection()
        let combined = combinedSelection([candidate])
        XCTAssertEqual(combined?.payload.text, "same selected text")
        XCTAssertEqual(combined?.textFrames?.count, 2)
        XCTAssertEqual(combined?.selectedTextRange?.location, 3)
    }
}
