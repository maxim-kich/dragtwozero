import AppKit
import XCTest
@testable import DragTwoZero

final class PasteCommitTransactionTests: XCTestCase {
    private let expected = EditorInsertionState(location: 3, length: 0, value: "Original draft")

    private final class Fixture {
        var state: EditorInsertionState?
        var preparations = 0
        var installs = 0
        var restores = 0
        var posts = 0
        var diagnostics: [String] = []
        var ownsClipboard = true
        var valid = true
        var allowsPost = true
        var duringPreparation: (() -> Void)?
        var duringInstall: (() -> Void)?
        init(_ state: EditorInsertionState?) { self.state = state }

        func commit(expected: EditorInsertionState) -> Int? {
            PasteCommitTransaction.commit(expected: expected, readState: { self.valid ? self.state : nil }, prepareClipboard: {
                self.preparations += 1
                self.duringPreparation?()
                return 42
            }, installClipboard: { preparation in
                self.installs += 1
                self.duringInstall?()
                return preparation
            }, restoreClipboard: { _ in self.restores += 1 }, ownsClipboard: { _ in self.valid && self.ownsClipboard },
            postPaste: { guard self.allowsPost else { return false }; self.posts += 1; return true }, diagnostic: { self.diagnostics.append(String(describing: $0)) })
        }
    }

    func testUnchangedCollapsedRangeAndValueCanPostOnce() {
        let fixture = Fixture(expected)
        XCTAssertEqual(fixture.commit(expected: expected), 42)
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertEqual(fixture.restores, 0)
    }
    func testCancellationAtDispatchGateRestoresInstalledClipboardWithoutPosting() {
        let fixture = Fixture(expected)
        fixture.allowsPost = false
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.installs, 1)
        XCTAssertEqual(fixture.restores, 1)
        XCTAssertEqual(fixture.posts, 0)
        XCTAssertEqual(fixture.diagnostics, ["commit-cancelled-before-post"])
    }

    func testChangesDuringSelectionSettlingDelayRejectBeforeClipboardPreparation() {
        for changed in [
            EditorInsertionState(location: 3, length: 5, value: expected.value),
            EditorInsertionState(location: 8, length: 0, value: expected.value),
            EditorInsertionState(location: 3, length: 0, value: "Newer draft")
        ] {
            // expected was captured before the production 60 ms settling gap.
            let fixture = Fixture(changed)
            XCTAssertNil(fixture.commit(expected: expected))
            XCTAssertEqual(fixture.preparations, 0)
            XCTAssertEqual(fixture.diagnostics, ["commit-initial-state-rejected"])
            XCTAssertEqual(fixture.posts, 0)
        }
    }

    func testCanonicallyEquivalentReplacementStillInvalidatesUTF16Offsets() {
        let original = EditorInsertionState(location: 1, length: 0, value: "é draft")
        let changed = EditorInsertionState(location: 1, length: 0, value: "e\u{301} draft")
        let fixture = Fixture(changed)
        XCTAssertNil(fixture.commit(expected: original))
        XCTAssertEqual(fixture.preparations, 0)
    }

    func testUnreadableSelectionOrValueFailsClosed() {
        let fixture = Fixture(nil)
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.installs, 0)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testAuthorizedNoncollapsedSelectionCanBeReplaced() {
        let selected = EditorInsertionState(location: 3, length: 5, value: expected.value)
        let fixture = Fixture(selected)
        XCTAssertEqual(fixture.commit(expected: selected), 42)
        XCTAssertEqual(fixture.posts, 1)
    }

    func testChangedAuthorizedSelectionRejectsBeforePaste() {
        let selected = EditorInsertionState(location: 3, length: 5, value: expected.value)
        let fixture = Fixture(EditorInsertionState(location: 3, length: 6, value: expected.value))
        XCTAssertNil(fixture.commit(expected: selected))
        XCTAssertEqual(fixture.posts, 0)
    }

    func testExactConfirmationRejectsPreexistingPayloadAndUnrelatedEdit() {
        let state = EditorInsertionState(location: 0, length: 0, value: "ALPHA old text")
        XCTAssertFalse(state.confirmsInsertion(of: "ALPHA", observed: "ALPHA old text!"))
        XCTAssertTrue(state.confirmsInsertion(of: "ALPHA", observed: "ALPHAALPHA old text"))
    }

    func testSelectedReplacementConfirmsOnlyExactExpectedUTF16Edit() {
        let state = EditorInsertionState(location: 5, length: 5, value: "LEFT|RIGHT")
        XCTAssertEqual(state.replacingSelection(with: "NEW"), "LEFT|NEW")
        XCTAssertTrue(state.confirmsInsertion(of: "NEW", observed: "LEFT|NEW"))
        XCTAssertFalse(state.confirmsInsertion(of: "NEW", observed: "LEFT|NEWRIGHT"))
        XCTAssertFalse(state.confirmsInsertion(of: "RIGHT", observed: "LEFT|RIGHT"))
    }

    func testInvalidAndSplitSurrogateRangesFailClosed() {
        for state in [EditorInsertionState(location: -1, length: 0, value: "abc"),
                      EditorInsertionState(location: 1, length: Int.max, value: "abc"),
                      EditorInsertionState(location: 1, length: 1, value: "😀text")] {
            XCTAssertFalse(state.hasValidRange)
            XCTAssertNil(Fixture(state).commit(expected: state))
        }
        XCTAssertEqual(EditorInsertionState(location: 0, length: 2, value: "😀text").replacingSelection(with: "X"), "Xtext")
    }

    func testSelectionMutationDuringSlowPreparationNeverInstallsPayload() {
        let fixture = Fixture(expected)
        fixture.duringPreparation = { fixture.state = EditorInsertionState(location: 3, length: 4, value: self.expected.value) }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.preparations, 1)
        XCTAssertEqual(fixture.diagnostics, ["commit-state-changed-during-preparation"])
        XCTAssertEqual(fixture.installs, 0)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testMutationAfterPreparationAndInstallRestoresWithoutPosting() {
        let fixture = Fixture(expected)
        fixture.duringInstall = { fixture.state = EditorInsertionState(location: 4, length: 0, value: self.expected.value) }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.installs, 1)
        XCTAssertEqual(fixture.diagnostics, ["commit-state-changed-after-install"])
        XCTAssertEqual(fixture.restores, 1)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testNewerClipboardAfterInstallationPreventsPosting() {
        let fixture = Fixture(expected)
        fixture.duringInstall = { fixture.ownsClipboard = false }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.diagnostics, ["commit-clipboard-ownership-lost"])
        XCTAssertEqual(fixture.restores, 1)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testCancelledDuringPreparationLeavesClipboardUntouched() {
        let fixture = Fixture(expected)
        fixture.duringPreparation = { fixture.valid = false }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.installs, 0)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testCancelledAfterInstallRollsBackWithoutPosting() {
        let fixture = Fixture(expected)
        fixture.duringInstall = { fixture.valid = false }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.restores, 1)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testUnreadableStateAfterPreparationNeverInstalls() {
        let fixture = Fixture(expected)
        fixture.duringPreparation = { fixture.state = nil }
        XCTAssertNil(fixture.commit(expected: expected))
        XCTAssertEqual(fixture.installs, 0)
        XCTAssertEqual(fixture.posts, 0)
    }

    func testPreparedClipboardRejectsNewUserCopyBeforeInstall() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Old user copy", forType: .string)
        let preparation = CaptureClipboard.prepare(board: board)
        board.clearContents(); board.setString("New user copy", forType: .string)
        let clipboard = CaptureClipboard(prepared: preparation)
        XCTAssertFalse(clipboard.install(text: "Capture"))
        clipboard.abortBeforePaste()
        XCTAssertEqual(board.string(forType: .string), "New user copy")
    }

    func testCancellationDuringClipboardInstallationRestoresOwnedClear() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("User copy", forType: .string)
        let clipboard = CaptureClipboard(prepared: CaptureClipboard.prepare(board: board))
        var checks = 0
        XCTAssertFalse(clipboard.install(text: "Capture", isCurrent: {
            checks += 1
            return checks < 3
        }))
        clipboard.abortBeforePaste()
        XCTAssertEqual(board.string(forType: .string), "User copy")
        XCTAssertNil(board.string(forType: CaptureClipboard.marker))
    }

    func testAbortedUnpostedPasteRestoresPreviousClipboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("User copy", forType: .string)
        let clipboard = CaptureClipboard(prepared: CaptureClipboard.prepare(board: board))
        XCTAssertTrue(clipboard.install(text: "Capture"))
        XCTAssertTrue(clipboard.isCurrent)
        clipboard.abortBeforePaste()
        XCTAssertEqual(board.string(forType: .string), "User copy")
        XCTAssertFalse(clipboard.isCurrent)
    }

    func testAbortedUnpostedPasteDoesNotRestoreOverNewerCopy() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("User copy", forType: .string)
        let clipboard = CaptureClipboard(text: "Capture", board: board)
        board.clearContents(); board.setString("New user copy", forType: .string)
        XCTAssertFalse(clipboard.isCurrent)
        clipboard.abortBeforePaste()
        XCTAssertEqual(board.string(forType: .string), "New user copy")
    }
}
