import AppKit
import XCTest
@testable import DragTwoZero

final class CaptureValidationTests: XCTestCase {
    func testReadOnlyReceiptSurvivesCancellationButNeverItsDeadline() {
        let token = CaptureCommitToken()
        XCTAssertFalse(token.allowsReadOnlyReceipt(beforeDeadline: true))
        XCTAssertTrue(token.dispatch {})
        token.cancel()
        XCTAssertFalse(token.isValid, "No further writes may run")
        XCTAssertTrue(token.allowsReadOnlyReceipt(beforeDeadline: true), "The posted paste still needs a receipt")
        XCTAssertFalse(token.allowsReadOnlyReceipt(beforeDeadline: false), "Verification must remain bounded")
        let cancelled = CaptureCommitToken()
        cancelled.cancel()
        XCTAssertFalse(cancelled.allowsReadOnlyReceipt(beforeDeadline: true))
    }
    func testDispatchCannotRepeatAndCancellationPreservesItsReceipt() {
        let token = CaptureCommitToken()
        var posts = 0
        XCTAssertTrue(token.dispatch { posts += 1 })
        XCTAssertTrue(token.wasDispatched)
        XCTAssertFalse(token.dispatch { posts += 1 })
        token.cancel()
        XCTAssertTrue(token.wasDispatched)
        XCTAssertFalse(token.isValid)
        XCTAssertFalse(token.dispatch { posts += 1 })
        XCTAssertEqual(posts, 1)
        let expired = CaptureCommitToken(timeout: 0)
        XCTAssertFalse(expired.dispatch { XCTFail("Expired dispatch") })
        XCTAssertFalse(expired.wasDispatched)
    }
    private let rect = CGRect(x: 10, y: 10, width: 200, height: 40)
    private let point = CGPoint(x: 30, y: 30)

    private func block(_ text: String, pid: pid_t = 101, page: String = "https://example.test/a") -> CaptureCandidate {
        var block = CaptureCandidate(payload: .init(title: text, markdown: text), frame: rect)
        block.anchor = AXUIElementCreateApplication(pid)
        block.context = CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: page)
        return block
    }

    private func target(pid: pid_t = 101, page: String = "https://example.test/a", cellPID: pid_t? = nil) -> InputTarget {
        InputTarget(element: AXUIElementCreateApplication(pid), app: .current, frame: rect,
                    dropPoint: point, insertionRange: CFRange(location: 5, length: 0), caretFrame: .zero,
                    cellValueElement: cellPID.map { AXUIElementCreateApplication($0) },
                    context: CaptureElementContext(window: AXUIElementCreateApplication(201), document: nil, documentURL: page))
    }

    func testChangedTextInSameSourceRectangleIsRejected() {
        XCTAssertFalse(block("ALPHA").matchesCurrentSource(block("BRAVO"), at: point))
    }

    func testDifferentSourceBehindSameRectangleIsRejectedEvenWithSameText() {
        XCTAssertFalse(block("ALPHA").matchesCurrentSource(block("ALPHA", pid: 102), at: point))
    }

    func testPageChangeWithReusedSourceIdentityIsRejected() {
        XCTAssertFalse(block("ALPHA").matchesCurrentSource(block("ALPHA", page: "https://example.test/b"), at: point))
    }

    func testUnchangedSourceAndClippedVisiblePoint() {
        XCTAssertTrue(block("ALPHA").matchesCurrentSource(block("ALPHA"), at: point))
        var clipped = block("ALPHA")
        clipped.clipFrame = CGRect(x: 100, y: 10, width: 100, height: 40)
        XCTAssertFalse(block("ALPHA").matchesCurrentSource(clipped, at: point))
    }

    func testDifferentDestinationAtIdenticalCoordinatesIsRejected() {
        XCTAssertFalse(target().matchesCurrentTarget(target(pid: 102), at: point))
    }

    func testNavigationWithReusedEditorIdentityIsRejected() {
        XCTAssertFalse(target().matchesCurrentTarget(target(page: "https://example.test/b"), at: point))
    }

    func testReplacedWritableCellEditorIsRejected() {
        XCTAssertFalse(target(cellPID: 301).matchesCurrentTarget(target(cellPID: 302), at: point))
    }

    func testUnchangedTargetAndReleaseOutsideCurrentBounds() {
        XCTAssertTrue(target().matchesCurrentTarget(target(), at: point))
        XCTAssertFalse(target().matchesCurrentTarget(target(), at: CGPoint(x: 400, y: 30)))
    }

    func testAcceptanceResolvesAgainInsteadOfTrustingCachedSource() {
        let done = expectation(description: "fresh source resolved")
        let old = block("ALPHA"), fresh = block("BRAVO"), point = point
        CaptureValidation().validate(expected: old, resolve: { fresh },
            matches: { $0.matchesCurrentSource($1, at: point) }, isCurrent: { true }) { result in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNil(result)
                done.fulfill()
            }
        wait(for: [done], timeout: 2)
    }

    func testReleaseRejectsDestinationWhichDisappeared() {
        let done = expectation(description: "missing destination rejected")
        let point = point
        CaptureValidation().validate(expected: target(), resolve: { nil },
            matches: { $0.matchesCurrentTarget($1, at: point) }, isCurrent: { true }) { result in
                XCTAssertNil(result)
                done.fulfill()
            }
        wait(for: [done], timeout: 2)
    }

    func testSuccessfulFreshValidationCommitsOnMainWithoutResolvingThere() {
        let done = expectation(description: "unchanged target accepted")
        let current = target(), point = point
        CaptureValidation().validate(expected: current, resolve: {
            XCTAssertFalse(Thread.isMainThread)
            return current
        }, matches: { $0.matchesCurrentTarget($1, at: point) }, isCurrent: { true }) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result?.insertionRange?.location, 5)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testCancellationDuringSlowResolutionNeverCommitsLateResult() {
        let resolved = expectation(description: "slow work completed")
        let rejected = expectation(description: "cancelled commit is never called")
        rejected.isInverted = true
        let token = CaptureCommitToken()
        CaptureValidation().validate(expected: 1, resolve: {
            token.cancel()
            resolved.fulfill()
            return 1
        }, matches: ==, isCurrent: { token.isValid }) { _ in rejected.fulfill() }
        wait(for: [resolved, rejected], timeout: 0.15)
    }

    func testReplacementGestureCannotReceiveOldValidation() {
        let done = expectation(description: "new gesture completed")
        let oldToken = CaptureCommitToken()
        oldToken.cancel()
        let validator = CaptureValidation()
        validator.validate(expected: "OLD", resolve: { "OLD" }, matches: ==,
                           isCurrent: { oldToken.isValid }) { _ in XCTFail("old result committed") }
        validator.validate(expected: "NEW", resolve: { "NEW" }, matches: ==,
                           isCurrent: { true }) { result in
            XCTAssertEqual(result, "NEW")
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testCancelledQueuedValidationSkipsAllSourceReads() {
        let validator = CaptureValidation()
        let token = CaptureCommitToken(); token.cancel()
        let drained = expectation(description: "subsequent validation completed")
        validator.validate(expected: 1, resolve: { XCTFail("Canceled work read its source"); return 1 },
                           matches: ==, cancellation: token, isCurrent: { true }) { _ in XCTFail("Canceled completion") }
        validator.validate(expected: 2, resolve: { 2 }, matches: ==, isCurrent: { true }) { result in
            XCTAssertEqual(result, 2); drained.fulfill()
        }
        wait(for: [drained], timeout: 1)
    }

    func testExpiredActiveValidationCompletesAsFailureWithoutReadingSource() {
        let validator = CaptureValidation()
        let expired = CaptureCommitToken(timeout: 0)
        let done = expectation(description: "expired UI can reset")
        validator.validate(expected: 1, resolve: { XCTFail("Expired work read source"); return 1 },
                           matches: ==, cancellation: expired, isCurrent: { true }) { result in
            XCTAssertNil(result); done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func testSelectionValidationStopsBetweenMembersAfterCancellation() {
        let token = CaptureCommitToken()
        var reads = 0
        let expected = [block("First"), block("Second")]
        let result = SelectionSourceValidation.resolve(expected, visibleSource: { _ in
            reads += 1; token.cancel(); return expected[0]
        }, retainedSource: { _ in XCTFail("Visible fixture"); return nil }, shouldStop: { !token.isValid })
        XCTAssertNil(result)
        XCTAssertEqual(reads, 1)
    }


    func testCancelledAdaptersAndDiscoveryRejectBeforeAnyAccessibilityRead() {
        let inaccessible = AXUIElementCreateApplication(999_999)
        let stop = { true }
        XCTAssertNil(AccessibleTextBlockAdapter().candidate(at: inaccessible, shouldStop: stop))
        XCTAssertNil(AccessibleLinkAdapter().candidate(at: inaccessible, shouldStop: stop))
        let result = marqueeCandidates(root: inaccessible, rect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       adapters: [AccessibleTextBlockAdapter(), AccessibleLinkAdapter()], shouldStop: stop)
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertFalse(result.isComplete)
    }

}
