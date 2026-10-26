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

    func testWholeOwnedTextAndUnambiguousEmojiConfirmExactUnicodePayload() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|ALPHA: "), .emoji("🐈"), .text(" éRIGHT")]
        let observed = EditorReceiptText.reconcile(value: "LEFT|ALPHA:  éRIGHT", fragments: fragments)
        XCTAssertEqual(observed, "LEFT|ALPHA: 🐈 éRIGHT")
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|RIGHT")
        XCTAssertTrue(before.confirmsInsertion(of: "ALPHA: 🐈 é", observed: observed!))
        XCTAssertFalse(before.confirmsInsertion(of: "ALPHA: 🐈 é", observed: observed!))
    }

    func testNewlinePlacementAroundAnOmittedImageIsAmbiguousAndRejects() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|before"), .emoji("🐈"), .text("afterRIGHT")]
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: fragments))
        XCTAssertEqual(EditorReceiptText.reconcile(value: "LEFT|before\n\nafterRIGHT", fragments: [.text("LEFT|before\n\n"), .emoji("🐈"), .text("afterRIGHT")]), "LEFT|before\n\n🐈afterRIGHT")
        XCTAssertNil(EditorReceiptText.reconcile(value: "before\n", fragments: [.text("before"), .emoji("🐈")]))
    }

    func testExtraReorderedOrDuplicatedOwnedTextCannotProduceReceipt() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|"), .emoji("🐈"), .text("RIGHT")]
        for value in ["LEFT|RIGHT extra", "RIGHTLEFT|", "LEFT|LEFTRIGHT", "LEFT| RIGHT", "LEFT|RIGHTRIGHT"] {
            XCTAssertNil(EditorReceiptText.reconcile(value: value, fragments: fragments))
        }
        XCTAssertNil(EditorReceiptText.reconcile(value: "LEFT|RIGHT", fragments: [.text("LEFT|"), .text("RIGHT")]))
    }

    func testChangedOrIncompleteSubtreeAndCancelledReadCannotConfirm() {
        let first = EditorReceiptText.Snapshot(value: "LEFT|RIGHT", fragments: [.text("LEFT|"), .emoji("🐈"), .text("RIGHT")])
        let changed = EditorReceiptText.Snapshot(value: "LEFT|RIGHT", fragments: [.text("LEFT|"), .emoji("👩‍💻"), .text("RIGHT")])
        for second: EditorReceiptText.Snapshot? in [changed, nil] {
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

    func testStructuralLinesOutsideImagesRemainExact() {
        let fragments: [EditorReceiptText.Fragment] = [.text("LEFT|first"), .text("second "), .emoji("🐈"), .text("RIGHT")]
        XCTAssertEqual(EditorReceiptText.reconcile(value: "LEFT|first\n\nsecond RIGHT", fragments: fragments), "LEFT|first\n\nsecond 🐈RIGHT")
    }
}
