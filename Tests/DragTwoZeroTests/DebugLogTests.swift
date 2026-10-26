import XCTest
@testable import DragTwoZero

final class DebugLogTests: XCTestCase {
    private func withLog(limit: Int = 1024, _ run: (DebugLog, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(DebugLog(directory: directory, limit: limit), directory)
    }

    func testExportIncludesOnlyOperationalStateAndNumericErrors() throws {
        try withLog(limit: 4096) { log, _ in
            log.record(.action(.settingsOpened))
            log.record(.inputInterrupted(timeout: true))
            log.record(.health(accessibility: true, listener: false, paused: true, phase: .idle, buffer: true, transfer: false))
            log.record(.update(phase: .idle, codes: [3001, -999]))
            log.record(.acceptance(stage: "drop", reason: "no-authorized-target"))
            let text = String(decoding: try log.snapshot(appVersion: "0.0.1"), as: UTF8.self)
            XCTAssertTrue(text.contains("version 0.0.1"))
            XCTAssertTrue(text.contains("inputInterrupted"))
            XCTAssertTrue(text.contains("\"errorCodes\":[3001,-999]"))
            XCTAssertTrue(text.contains("\"bufferOccupied\":true"))
            XCTAssertFalse(text.contains(NSHomeDirectory()))
            XCTAssertFalse(text.contains(NSUserName()))
        }
    }

    func testRotationBoundsBothFilesAndRetainsLatestEvents() throws {
        try withLog { log, directory in
            for index in 0..<100 { log.record(.slowInputHandler(milliseconds: index)) }
            let data = try log.snapshot(appVersion: "0.0.1")
            XCTAssertLessThan(data.count, 2 * 1024 + 512)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(text.contains("\"milliseconds\":99"))
            XCTAssertFalse(text.contains("\"milliseconds\":0,"))
            for name in ["status.log", "status.previous.log"] {
                let url = directory.appendingPathComponent(name)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                XCTAssertLessThanOrEqual((attributes[.size] as! NSNumber).intValue, 1024)
                XCTAssertEqual((attributes[.posixPermissions] as! NSNumber).intValue & 0o777, 0o600)
            }
        }
    }

    func testExportOmitsLegacyTextUnknownFieldsAndUnsafeTokens() throws {
        try withLog(limit: 4096) { log, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let untrusted = """
            old log /Users/private/person clipboard secret
            {"event":"health","capturedText":"private-message"}
            {"event":"acceptance","reason":"https://private.example"}
            {"event":"health","phase":"private-message"}
            {"event":"update","errorCodes":["private-message"]}
            {"event":"inputInterrupted","timeout":true}

            """
            try Data(untrusted.utf8).write(to: directory.appendingPathComponent("status.log"))
            let text = String(decoding: try log.snapshot(appVersion: "secret-user/path"), as: UTF8.self)
            XCTAssertTrue(text.contains("version unknown"))
            XCTAssertTrue(text.contains("inputInterrupted"))
            for secret in ["private-message", "private.example", "/Users/", "secret-user"] { XCTAssertFalse(text.contains(secret)) }
        }
    }

    func testDuplicateHealthEventsAreCoalesced() throws {
        try withLog { log, _ in
            for _ in 0..<50 { log.record(.health(accessibility: true, listener: true, paused: false, phase: .idle, buffer: false, transfer: false)) }
            let text = String(decoding: try log.snapshot(appVersion: "0.0.1"), as: UTF8.self)
            XCTAssertEqual(text.components(separatedBy: "\"event\":\"health\"").count - 1, 1)
        }
    }

    func testExportWritesChosenFileAndReportsFailureWithoutThrowingOnCaller() throws {
        try withLog { log, directory in
            log.record(.action(.launched))
            _ = try log.snapshot(appVersion: "0.0.1")
            let saved = expectation(description: "saved")
            let destination = directory.appendingPathComponent("export.txt")
            log.export(to: destination, appVersion: "0.0.1") { result in
                if case .failure(let error) = result { XCTFail("\(error)") }
                saved.fulfill()
            }
            wait(for: [saved], timeout: 2)
            XCTAssertTrue(try String(contentsOf: destination).contains("launched"))
            let failed = expectation(description: "failed")
            log.export(to: directory.appendingPathComponent("missing/export.txt"), appVersion: "0.0.1") { result in
                if case .success = result { XCTFail("Missing parent must fail") }
                failed.fulfill()
            }
            wait(for: [failed], timeout: 2)
        }
    }

    func testSymlinkLogIsNotFollowed() throws {
        try withLog { log, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("private.txt")
            try Data("private-message".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("status.log"), withDestinationURL: target)
            log.record(.action(.launched))
            let text = String(decoding: try log.snapshot(appVersion: "0.0.1"), as: UTF8.self)
            XCTAssertFalse(text.contains("private-message"))
            XCTAssertEqual(try String(contentsOf: target), "private-message")
        }
    }
}
