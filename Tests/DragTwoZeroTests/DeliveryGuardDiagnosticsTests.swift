import XCTest
@testable import DragTwoZero

final class DeliveryGuardDiagnosticsTests: XCTestCase {
    func testCancellationIsDistinctAndDoesNotReadDeadline() {
        var events: [String] = []
        let result = DeliveryGuardDiagnostics.valid(isCurrent: { events.append("token-read"); return false },
            beforeDeadline: { XCTFail("cancelled guard must short circuit"); return true },
            diagnostic: { events.append(String(describing: $0)) })
        XCTAssertFalse(result)
        XCTAssertEqual(events, ["token-read", "transaction-cancelled"])
    }

    func testDeadlineIsDistinctAndEachOriginalConditionIsReadOnce() {
        var events: [String] = []
        XCTAssertFalse(DeliveryGuardDiagnostics.valid(isCurrent: { events.append("token-read"); return true },
            beforeDeadline: { events.append("deadline-read"); return false },
            diagnostic: { events.append(String(describing: $0)) }))
        XCTAssertEqual(events, ["token-read", "deadline-read", "transaction-deadline"])
    }

    func testAcceptedValidityHasNoDiagnosticAndKeepsGuardOrder() {
        var events: [String] = []
        XCTAssertTrue(DeliveryGuardDiagnostics.valid(isCurrent: { events.append("token-read"); return true },
            beforeDeadline: { events.append("deadline-read"); return true },
            diagnostic: { _ in XCTFail("successful guard must not report rejection") }))
        XCTAssertEqual(events, ["token-read", "deadline-read"])
    }

    func testInvalidAuthorizedRangeDoesNotReadEditorToDiagnose() {
        let invalid = EditorInsertionState(location: 4, length: 0, value: "abc")
        var reasons: [String] = []
        XCTAssertFalse(DeliveryGuardDiagnostics.selectionMatches(expected: invalid,
            read: { XCTFail("invalid range must short circuit before AX read"); return nil },
            diagnostic: { reasons.append(String(describing: $0)) }))
        XCTAssertEqual(reasons, ["authorized-range-invalid"])
    }

    func testUnreadableSelectionIsDistinctFromChangedStateWithSingleRead() {
        let expected = EditorInsertionState(location: 1, length: 1, value: "abc")
        for observed in [nil, EditorInsertionState(location: 1, length: 0, value: "abc"),
                         EditorInsertionState(location: 0, length: 1, value: "abc"),
                         EditorInsertionState(location: 1, length: 1, value: "axc")] {
            var reads = 0, reasons: [String] = []
            XCTAssertFalse(DeliveryGuardDiagnostics.selectionMatches(expected: expected,
                read: { reads += 1; return observed }, diagnostic: { reasons.append(String(describing: $0)) }))
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(reasons, [observed == nil ? "authorized-selection-unreadable" : "authorized-selection-changed"])
        }
    }

    func testMatchingStateDoesNotDiagnoseOrRepeatEditorRead() {
        let expected = EditorInsertionState(location: 1, length: 1, value: "abc")
        var reads = 0
        XCTAssertTrue(DeliveryGuardDiagnostics.selectionMatches(expected: expected,
            read: { reads += 1; return expected }, diagnostic: { _ in XCTFail("matching state rejected") }))
        XCTAssertEqual(reads, 1)
    }
}
