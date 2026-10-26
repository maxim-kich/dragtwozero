import AppKit
import XCTest
@testable import DragTwoZero

final class BoundedTargetResolutionTests: XCTestCase {
    private final class Fixture {
        var time: TimeInterval = 0
        var current = true
        var reads = 0
        var matches = 0
        var reasons: [String] = []
        var results: [TargetLookupResult<Int>]
        var afterRead: ((Int) -> Void)?
        var afterMatch: (() -> Void)?
        init(_ results: [TargetLookupResult<Int>]) { self.results = results }
        func resolve(allowsRecovery: Bool = true) -> Int? {
            BoundedTargetResolution.resolve(expected: 10, deadline: 0.25, allowsRecovery: allowsRecovery,
                isCurrent: { self.current }, clock: { self.time }, lookup: {
                    let result = self.results[self.reads]
                    self.reads += 1
                    self.afterRead?(self.reads)
                    return result
                }, matches: { original, fresh in
                    self.matches += 1
                    self.afterMatch?()
                    return original == fresh
                }, diagnostic: { self.reasons.append(String(describing: $0)) })
        }
    }

    func testOneOperationalFailureCanRecoverOnlyWithFreshMatchingResult() {
        let fixture = Fixture([.operationallyUnavailable, .found(10)])
        XCTAssertEqual(fixture.resolve(), 10)
        XCTAssertEqual(fixture.reads, 2)
        XCTAssertEqual(fixture.matches, 1)
        XCTAssertEqual(fixture.reasons, ["target-resolution-reread", "target-resolution-recovered"])
    }

    func testUnavailableExhaustionIsBoundedAndNeverReturnsCachedExpectedValue() {
        let fixture = Fixture([.operationallyUnavailable, .operationallyUnavailable])
        XCTAssertNil(fixture.resolve())
        XCTAssertEqual(fixture.reads, 2)
        XCTAssertEqual(fixture.matches, 0)
    }

    func testTerminalRejectionAndIdentityMismatchAreNeverRetried() {
        for result: TargetLookupResult<Int> in [.rejected, .found(11)] {
            let fixture = Fixture([result])
            XCTAssertNil(fixture.resolve())
            XCTAssertEqual(fixture.reads, 1)
        }
        let fixture = Fixture([.operationallyUnavailable, .found(11)])
        XCTAssertNil(fixture.resolve())
        XCTAssertEqual(fixture.reads, 2)
        XCTAssertEqual(fixture.reasons.last, "target-resolution-mismatch")
    }

    func testCallerCanDisableRecovery() {
        let fixture = Fixture([.operationallyUnavailable])
        XCTAssertNil(fixture.resolve(allowsRecovery: false))
        XCTAssertEqual(fixture.reads, 1)
    }

    func testCancellationBeforeReadOrDuringFirstReadPreventsSecondRead() {
        let before = Fixture([])
        before.current = false
        XCTAssertNil(before.resolve())
        XCTAssertEqual(before.reads, 0)
        let during = Fixture([.operationallyUnavailable])
        during.afterRead = { _ in during.current = false }
        XCTAssertNil(during.resolve())
        XCTAssertEqual(during.reads, 1)
    }

    func testQueueWaitConsumesAbsoluteDeadlineAndLateSuccessIsRejected() {
        let queued = Fixture([])
        queued.time = 0.25
        XCTAssertNil(queued.resolve())
        XCTAssertEqual(queued.reads, 0)
        let late = Fixture([.found(10)])
        late.afterRead = { _ in late.time = 0.25 }
        XCTAssertNil(late.resolve())
        XCTAssertEqual(late.matches, 0)
        let retryLate = Fixture([.operationallyUnavailable, .found(10)])
        retryLate.afterRead = { read in if read == 2 { retryLate.time = 0.3 } }
        XCTAssertNil(retryLate.resolve())
    }

    func testCancellationDuringMatchingCannotAcceptLateResult() {
        let fixture = Fixture([.found(10)])
        fixture.afterMatch = { fixture.current = false }
        XCTAssertNil(fixture.resolve())
        XCTAssertEqual(fixture.reads, 1)
        XCTAssertEqual(fixture.reasons.last, "target-resolution-cancelled")
    }

    func testOnlyExplicitOperationalAXErrorsAreClassifiedAsRecoverable() {
        XCTAssertTrue(AXTargetReadFailure.isOperational(.cannotComplete))
        XCTAssertTrue(AXTargetReadFailure.isOperational(.noValue))
        for error: AXError in [.apiDisabled, .invalidUIElement, .attributeUnsupported, .failure, .notImplemented] {
            XCTAssertFalse(AXTargetReadFailure.isOperational(error))
        }
    }

    private func target(cell: Bool = false) -> InputTarget {
        InputTarget(element: AXUIElementCreateApplication(101), app: .current,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100), dropPoint: CGPoint(x: 10, y: 10),
            insertionRange: CFRange(location: 1, length: 1), caretFrame: .zero,
            cellValueElement: cell ? AXUIElementCreateApplication(102) : nil,
            context: CaptureElementContext(window: AXUIElementCreateApplication(103), document: nil, documentURL: "https://example.test/a"),
            selectionValue: "abc")
    }

    func testOriginalExactSelectionValueAndContextAreRequiredAfterRecovery() {
        let original = target()
        let point = original.dropPoint
        XCTAssertTrue(original.matchesAuthorizedTarget(target(), at: point))
        var changedRange = target(); changedRange.insertionRange = CFRange(location: 1, length: 0)
        var changedValue = target(); changedValue.selectionValue = "axc"
        var changedContext = target(); changedContext.context = CaptureElementContext(window: nil, document: nil, documentURL: "https://example.test/b")
        for changed in [changedRange, changedValue, changedContext] {
            var reads = 0
            let result = BoundedTargetResolution.resolve(expected: original, deadline: 0.25, allowsRecovery: true,
                isCurrent: { true }, clock: { 0 }, lookup: {
                    reads += 1
                    return reads == 1 ? .operationallyUnavailable : .found(changed)
                }, matches: { $0.matchesAuthorizedTarget($1, at: point) })
            XCTAssertNil(result)
            XCTAssertEqual(reads, 2)
        }
    }

    func testCellsCannotRecoverEvenIfCallerAccidentallyEnablesIt() {
        var reads = 0
        let original = target(cell: true)
        let result = BoundedTargetResolution.resolve(expected: original, deadline: 0.25, allowsRecovery: true,
            isCurrent: { true }, clock: { 0 }, lookup: { reads += 1; return .operationallyUnavailable },
            matches: { $0.matchesAuthorizedTarget($1, at: original.dropPoint) })
        XCTAssertNil(result)
        XCTAssertEqual(reads, 1)
    }
}
