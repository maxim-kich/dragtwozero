import XCTest
@testable import DragTwoZero

final class EditorSelectionScopeTests: XCTestCase {
    private let roles = ["web": "AXWebArea", "otherWeb": "AXWebArea", "input": "AXTextArea",
                         "otherInput": "AXTextArea", "paragraph": "AXParagraph", "start": "AXStaticText",
                         "end": "AXStaticText", "inputGroup": "AXGroup"]
    private func outside(hit: [String], start: [String], end: [String], web: String = "web") -> Bool {
        EditorSelectionScope.isOutsideSelectedEditor(hitChain: hit, startChain: start, endChain: end,
            webArea: web, same: ==, role: { self.roles[$0] ?? "AXGroup" })
    }

    func testRecipientInputSelectionDoesNotBlockUnrelatedParagraph() {
        XCTAssertTrue(outside(hit: ["paragraph", "web"], start: ["start", "inputGroup", "input", "web"],
                              end: ["end", "inputGroup", "input", "web"]))
    }

    func testEmptySpaceOutsideSelectedEditorRemainsEligibleForMarquee() {
        XCTAssertTrue(outside(hit: ["web"], start: ["start", "input", "web"], end: ["end", "input", "web"]))
    }

    func testMovingIntoSelectedInputStillRequiresNativeSelectionCapture() {
        let start = ["start", "input", "web"], end = ["end", "input", "web"]
        XCTAssertTrue(outside(hit: ["paragraph", "web"], start: start, end: end))
        XCTAssertFalse(outside(hit: ["start", "input", "web"], start: start, end: end))
        XCTAssertFalse(outside(hit: ["input", "web"], start: start, end: end))
    }

    func testReadonlyParagraphSelectionCannotBeIgnored() {
        XCTAssertFalse(outside(hit: ["paragraph", "web"], start: ["start", "paragraph", "web"],
                               end: ["end", "paragraph", "web"]))
    }

    func testDifferentEditorsOrMissingOwnerEvidenceCannotWidenCapture() {
        XCTAssertFalse(outside(hit: ["paragraph", "web"], start: ["start", "input", "web"],
                               end: ["end", "otherInput", "web"]))
        XCTAssertFalse(outside(hit: ["paragraph", "web"], start: [], end: ["end", "input", "web"]))
        XCTAssertFalse(outside(hit: ["paragraph", "web"], start: ["start", "input", "web"], end: []))
    }

    func testSelectionOwnersMustBelongToTheSameDocumentAsTheHit() {
        XCTAssertFalse(outside(hit: ["paragraph", "web"], start: ["start", "input", "otherWeb"],
                               end: ["end", "input", "otherWeb"]))
        XCTAssertFalse(outside(hit: ["paragraph", "otherWeb"], start: ["start", "input", "web"],
                               end: ["end", "input", "web"]))
    }

    func testExpiredOwnershipReadCannotIgnoreSelection() {
        var cancelled = false
        XCTAssertFalse(EditorSelectionScope.isOutsideSelectedEditor(
            hitChain: ["paragraph", "web"], startChain: ["start", "input", "web"],
            endChain: ["end", "input", "web"], webArea: "web", same: ==,
            role: { node in cancelled = true; return self.roles[node] ?? "AXGroup" },
            shouldStop: { cancelled }))
        XCTAssertFalse(EditorSelectionScope.isOutsideSelectedEditor(
            hitChain: ["paragraph", "web"], startChain: ["start", "input", "web"],
            endChain: ["end", "input", "web"], webArea: "web", same: ==,
            role: { _ in XCTFail("Cancelled lookup must not probe roles"); return "AXTextArea" },
            shouldStop: { true }))
    }
}
