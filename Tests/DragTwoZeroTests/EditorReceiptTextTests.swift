import AppKit
import XCTest
@testable import DragTwoZero

final class EditorReceiptTextTests: XCTestCase {
    func testOnlyKnownNotoEmojiResourceShapeIsRepresentable() {
        XCTAssertEqual(EditorReceiptText.notoEmoji(URL(string: "https://fonts.gstatic.com/s/e/notoemoji/17.0/1f408/72.png")!), "🐈")
        XCTAssertEqual(EditorReceiptText.notoEmoji(URL(string: "https://fonts.gstatic.com/s/e/notoemoji/16.0/1f469_200d_1f4bb/32.png")!), "👩‍💻")
        for raw in ["http://fonts.gstatic.com/s/e/notoemoji/17.0/1f408/72.png",
                    "https://fonts.gstatic.com.evil.test/s/e/notoemoji/17.0/1f408/72.png",
                    "https://fonts.gstatic.com@evil.test/s/e/notoemoji/17.0/1f408/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/1f408/72.png?other=1",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/110000/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/d800/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/ffffffffffffffffffffff_1f408/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/61/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/1f408_1f408/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/%31f408/72.png",
                    "https://fonts.gstatic.com/s/e/notoemoji/17.0/1f408/extra/72.png"] {
            XCTAssertNil(EditorReceiptText.notoEmoji(URL(string: raw)!))
        }
    }

    private func markerRange(_ end: UInt8 = 2) -> AXTextMarkerRange {
        func marker(_ byte: UInt8) -> AXTextMarker {
            [byte].withUnsafeBufferPointer { AXTextMarkerCreate(kCFAllocatorDefault, $0.baseAddress!, 1) }
        }
        return AXTextMarkerRangeCreate(kCFAllocatorDefault, marker(1), marker(end))
    }

    func testWholeMarkerSubtreeAndPhantomImageValueProveExactUnicodeEdit() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|ALPHA: "), .emoji("🐈"), .text(" éRIGHT")]
        let observed = EditorReceiptText.reconcile(value: "LEFT|ALPHA: \n\n éRIGHT", fragments: fragments, markerText: "LEFT|ALPHA: \u{FFFC} éRIGHT")
        XCTAssertEqual(observed, "LEFT|ALPHA: 🐈 éRIGHT")
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|RIGHT")
        XCTAssertTrue(before.confirmsInsertion(of: "ALPHA: 🐈 é", observed: observed!))
        XCTAssertFalse(before.confirmsInsertion(of: "ALPHA: 🐈 é", observed: observed!))
    }

    func testRealNewlinesMustBePresentInEveryLiteralProjection() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|before\n\n"), .emoji("🐈"), .text("afterRIGHT")]
        XCTAssertEqual(EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: fragments,
                        markerText: "LEFT|before\n\n\u{FFFC}afterRIGHT"), "LEFT|before\n\n🐈afterRIGHT")
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|before\n\n\n\nafterRIGHT", fragments: fragments,
                        markerText: "LEFT|before\n\n\u{FFFC}afterRIGHT"))
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|before\n\n\n\nafterRIGHT",
                        fragments: [.text("LEFT|before"), .emoji("🐈"), .text("afterRIGHT")], markerText: "LEFT|before\u{FFFC}afterRIGHT"))
    }

    func testOwnedMarkerTwoLineGapIsPreservedWithoutGuessingFromPayload() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|before"), .emoji("🐈"), .text("afterRIGHT")]
        let semantic = EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: fragments, markerText: "LEFT|before\n\n\u{FFFC}afterRIGHT")
        XCTAssertEqual(semantic, "LEFT|before\n\n🐈afterRIGHT")
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|RIGHT")
        XCTAssertFalse(before.confirmsInsertion(of: "before🐈after", observed: semantic!))
        XCTAssertTrue(before.confirmsInsertion(of: "before\n\n🐈after", observed: semantic!))
        for marker in ["LEFT|before\n\u{FFFC}afterRIGHT", "LEFT|before\n\n\n\u{FFFC}afterRIGHT", "LEFT|before\r\n\u{FFFC}afterRIGHT", "LEFT|before\u{FFFC}\n\nafterRIGHT"] {
            XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: fragments, markerText: marker))
        }
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: [.text("LEFT|before"), .emoji("🐈"), .emoji("🐈"), .text("afterRIGHT")], markerText: "LEFT|before\u{FFFC}\u{FFFC}afterRIGHT"))
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|\n\n\n\nRIGHT", fragments: [.text("LEFT|"), .emoji("🐈"), .text(""), .emoji("🐈"), .text("RIGHT")], markerText: "LEFT|\u{FFFC}\u{FFFC}RIGHT"))
    }

    func testMissingExtraDuplicatedOrForeignMarkerContentCannotConfirm() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|"), .emoji("🐈"), .text("RIGHT")]
        for marker in ["LEFT|RIGHT", "LEFT|\u{FFFC}\u{FFFC}RIGHT", "LEFT|\u{FFFC}RIGHT extra",
                       "RIGHT\u{FFFC}LEFT|", "LEFT|\n\u{FFFC}RIGHT", "LEFT|foreign control\u{FFFC}RIGHT"] {
            XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|\n\nRIGHT", fragments: fragments, markerText: marker))
        }
        for value in ["LEFT|RIGHT", "LEFT|\nRIGHT", "LEFT|\n\n\nRIGHT", "LEFT|\n\nRIGHT extra", "LEFT| \n\nRIGHT"] {
            XCTAssertNil(EditorReceiptText.reconcile(value: value, fragments: fragments, markerText: "LEFT|\u{FFFC}RIGHT"))
        }
    }

    func testLiteralObjectReplacementCharacterIsNotAnImageLeaf() {
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|\u{FFFC}\n\nRIGHT",
            fragments: [.text("LEFT|\u{FFFC}"), .emoji("🐈"), .text("RIGHT")], markerText: "LEFT|\u{FFFC}\u{FFFC}RIGHT"))
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|\u{FFFC}RIGHT", fragments: [.text("LEFT|\u{FFFC}RIGHT")], markerText: "LEFT|\u{FFFC}RIGHT"))
    }

    func testBeforeStateWithExistingOmittedImageDoesNotFalselyConfirm() {
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|\n\nRIGHT")
        XCTAssertFalse(before.confirmsInsertion(of: "🐈", observed: "LEFT|🐈🐈RIGHT"))
    }

    func testChangedRangeSubtreeMarkerStringOrIncompleteReadCannotConfirm() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|"), .emoji("🐈"), .text("RIGHT")]
        let first = EditorReceiptText.Snapshot(value: "LEFT|\n\nRIGHT", fragments: fragments, markerText: "LEFT|\u{FFFC}RIGHT", markerRange: markerRange())
        let changed = EditorReceiptText.Snapshot(value: first.value, fragments: [.text("LEFT|"), .emoji("👩‍💻"), .text("RIGHT")], markerText: first.markerText, markerRange: markerRange())
        let changedRange = EditorReceiptText.Snapshot(value: first.value, fragments: fragments, markerText: first.markerText, markerRange: markerRange(3))
        let changedText = EditorReceiptText.Snapshot(value: first.value, fragments: fragments, markerText: first.markerText+"extra", markerRange: markerRange())
        for second: EditorReceiptText.Snapshot? in [changed, changedRange, changedText, nil] {
            var reads = 0
            XCTAssertNil(EditorReceiptText.readStable(snapshot: { reads += 1; return reads == 1 ? first:second }, valid: { true }))
        }
        var reads = 0
        XCTAssertNil(EditorReceiptText.readStable(snapshot: { reads += 1; return first }, valid: { reads == 0 }))
        XCTAssertEqual(reads, 1)
    }

    func testSnapshotFragmentsRejectCanonicalUnicodeChanges() {
        XCTAssertNotEqual(EditorReceiptText.Fragment.text("é"), .text("é"))
        XCTAssertNotEqual(EditorReceiptText.Fragment.emoji("é"), .emoji("é"))
        XCTAssertNotEqual(EditorReceiptText.Fragment.text("🐈"), .emoji("🐈"))
    }
}
