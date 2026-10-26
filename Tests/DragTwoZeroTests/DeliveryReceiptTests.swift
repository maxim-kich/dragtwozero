import XCTest
@testable import DragTwoZero

final class DeliveryReceiptTests: XCTestCase {
    func testPlatformLineEndingsConfirmTheEntireAuthorizedEdit() {
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|RIGHT")
        XCTAssertTrue(before.confirmsLineNormalizedInsertion(of: "A\r\n🐈 é\r\nB", observed: "LEFT|A\n🐈 é\nBRIGHT"))
        XCTAssertFalse(before.confirmsLineNormalizedInsertion(of: "A\rB", observed: "LEFT|A\nBRIGHT"))
        XCTAssertTrue(before.confirmsLineNormalizedInsertion(of: "A\n\nB", observed: "LEFT|A\r\n\r\nBRIGHT"))
    }

    func testReceiptPreservesSpacesBlankLinesUnicodeAndEditBoundaries() {
        let before = EditorInsertionState(location: 5, length: 0, value: "LEFT|RIGHT")
        let payload = "Two  spaces\n\n🐈 é"
        for after in ["LEFT|Two spaces\n\n🐈 éRIGHT", "LEFT|Two  spaces\n🐈 éRIGHT",
                      "LEFT|Two  spaces\n\n🐈 éRIGHT", "LEFT|Two  spaces\n\n éRIGHT",
                      "LEFT|" + payload + "RIGHT extra", "LEFT|RIGHT" + payload,
                      "LEFT|" + payload + payload + "RIGHT", "LEFT|RIGHT"] {
            XCTAssertFalse(before.confirmsLineNormalizedInsertion(of: payload, observed: after))
        }
    }

    func testNoOpAndUnrelatedReplacementCannotConfirm() {
        let before = EditorInsertionState(location: 1, length: 2, value: "A\r\nB")
        XCTAssertFalse(before.confirmsLineNormalizedInsertion(of: "\n", observed: "A\nB"))
        XCTAssertFalse(before.confirmsLineNormalizedInsertion(of: "X", observed: "A\r\nBX"))
    }
}
