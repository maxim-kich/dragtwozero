import XCTest
import Sparkle
@testable import DragTwoZero

final class UpdateConsentTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let update = ReleaseUpdate(version: "0.0.2",
        archive: URL(string: "https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/Drag-2.0-v0.0.2-macOS-arm64.zip")!,
        length: 123, feed: URL(string: "https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml")!)
    override func setUp() {
        suite = "DragTwoZero.UpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "checkForUpdates")
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func checker(_ confirmation: @escaping (String, String, String) -> Bool = { _, _, _ in true }) -> UpdateChecker {
        let checker = UpdateChecker(defaults: defaults, confirm: confirmation)
        checker.activity = { UpdateActivity() }
        return checker
    }
    func testDownloadRequiresConsentAndPreservesDailyPreference() {
        var consent = false
        let checker = checker { _, _, button in XCTAssertEqual(button, "Download & Install"); return consent }
        var choices: [SPUUserUpdateChoice] = []
        checker.offerUpdate(update) { choices.append($0) }
        XCTAssertTrue(choices.isEmpty)
        checker.openUpdate()
        XCTAssertTrue(choices.isEmpty)
        consent = true
        checker.openUpdate()
        XCTAssertEqual(choices, [.install])
        XCTAssertEqual(checker.phase, .downloading)
        XCTAssertFalse(checker.automaticChecks)
        XCTAssertFalse(checker.permitsTermination(), "Ordinary Quit must not install on exit without Restart consent")
    }
    func testRestartRequiresSeparateConsentAndEmptyBuffer() {
        var consent = true
        let checker = checker { _, _, _ in consent }
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        var result: SPUUserUpdateChoice?
        checker.showReady(toInstallAndRelaunch: { result = $0 })
        XCTAssertNil(result)
        checker.activity = { UpdateActivity(buffer: true) }
        checker.openUpdate()
        XCTAssertNil(result)
        XCTAssertFalse(checker.restartAuthorized)
        XCTAssertTrue(checker.message.contains("Buffer"))
        checker.activity = { UpdateActivity() }
        consent = false
        checker.openUpdate()
        XCTAssertNil(result)
        consent = true
        checker.openUpdate()
        XCTAssertEqual(result, .install)
        XCTAssertTrue(checker.restartAuthorized)
        XCTAssertTrue(checker.permitsTermination())
    }
    func testRestartRechecksActivityAfterModalConfirmationAndAtTermination() {
        var activity = UpdateActivity()
        var confirmations = 0
        let checker = checker { _, _, button in
            if button == "Restart" { activity.transfer = true; confirmations += 1 }
            return true
        }
        checker.activity = { activity }
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        var result: SPUUserUpdateChoice?
        checker.showReady(toInstallAndRelaunch: { result = $0 })
        checker.openUpdate()
        XCTAssertEqual(confirmations, 1)
        XCTAssertNil(result)
        XCTAssertFalse(checker.restartAuthorized)
        XCTAssertFalse(checker.permitsTermination())
    }
    func testCancellationOfStagedUpdateUsesSkipRatherThanInstallOnQuitDismissal() {
        let checker = checker()
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        var result: SPUUserUpdateChoice?
        checker.showReady(toInstallAndRelaunch: { result = $0 })
        checker.cancel()
        XCTAssertEqual(result, .skip)
        XCTAssertEqual(checker.phase, .idle)
        XCTAssertTrue(checker.permitsTermination())
        XCTAssertFalse(checker.restartAuthorized)
    }
    func testCancellationWhileRestartConfirmationIsOpenInvalidatesItsReply() {
        var checker: UpdateChecker!
        checker = self.checker { _, _, button in
            if button == "Restart" { checker.cancel() }
            return true
        }
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        var choices: [SPUUserUpdateChoice] = []
        checker.showReady(toInstallAndRelaunch: { choices.append($0) })
        checker.openUpdate()
        XCTAssertEqual(choices, [.skip])
        XCTAssertFalse(checker.restartAuthorized)
        XCTAssertEqual(checker.phase, .idle)
    }
    func testCancellationDuringExtractionWaitsAndThenDisarmsInstaller() {
        let checker = checker()
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        checker.showDownloadDidStartExtractingUpdate()
        checker.cancel()
        XCTAssertEqual(checker.phase, .extracting)
        XCTAssertFalse(checker.permitsTermination())
        var result: SPUUserUpdateChoice?
        checker.showReady(toInstallAndRelaunch: { result = $0 })
        XCTAssertEqual(result, .skip)
    }
    func testDownloadCancellationAndErrorDoNotAuthorizeRestart() {
        let checker = checker()
        checker.offerUpdate(update) { _ in }
        checker.openUpdate()
        var cancelled = false
        checker.showDownloadInitiated { cancelled = true }
        checker.cancel()
        XCTAssertTrue(cancelled)
        XCTAssertFalse(checker.restartAuthorized)
        var acknowledged = false
        checker.showUpdaterError(NSError(domain: "test", code: 1)) { acknowledged = true }
        XCTAssertTrue(acknowledged)
        XCTAssertFalse(checker.restartAuthorized)
    }
    func testWrappedSignatureFailureShowsSafeActionableMessage() {
        let checker = checker()
        let signature = NSError(domain: SUSparkleErrorDomain, code: 3002,
                                userInfo: [NSLocalizedDescriptionKey: "untrusted server text"])
        let installer = NSError(domain: SUSparkleErrorDomain, code: 4005,
                                userInfo: [NSUnderlyingErrorKey: signature])
        checker.showUpdaterError(installer) {}
        XCTAssertTrue(checker.message.contains("signature"))
        XCTAssertFalse(checker.message.contains("untrusted server text"))
        XCTAssertFalse(checker.restartAuthorized)
    }
    func testEveryTransientCaptureAndTransferStateBlocksRestart() {
        XCTAssertNil(UpdateActivity().restartBlock)
        XCTAssertNotNil(UpdateActivity(transfer: true).restartBlock)
        XCTAssertNotNil(UpdateActivity(selection: true).restartBlock)
        XCTAssertNotNil(UpdateActivity(buffer: true).restartBlock)
        let app = AppDelegate()
        XCTAssertNil(app.updateActivity.restartBlock)
        app.state.modifiers(held: true)
        XCTAssertNotNil(app.updateActivity.restartBlock)
        app.state.cancel()
        app.dropping = true
        XCTAssertTrue(app.updateActivity.transfer)
        app.dropping = false
        app.pendingPress = .init(start: .zero, end: .zero)
        XCTAssertTrue(app.updateActivity.transfer)
        app.pendingPress = nil
        _ = app.buffer.store(CapturePayload(title: "test", markdown: "test"), symbol: "text")
        XCTAssertTrue(app.updateActivity.buffer)
    }
}
