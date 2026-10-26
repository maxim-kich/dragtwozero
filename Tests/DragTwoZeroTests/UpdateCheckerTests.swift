import XCTest
import Sparkle
@testable import DragTwoZero

final class UpdateCheckerTests: XCTestCase {
    func testStreamingBodyAcceptsExactLimitAndRejectsOneExtraByte() async throws {
        func bytes(_ count: Int) -> AsyncStream<UInt8> {
            AsyncStream { continuation in
                for _ in 0..<count { continuation.yield(65) }
                continuation.finish()
            }
        }
        let accepted = try await BoundedReleaseBody.read(bytes(BoundedReleaseBody.limit))
        XCTAssertEqual(accepted.count, BoundedReleaseBody.limit)
        do {
            _ = try await BoundedReleaseBody.read(bytes(BoundedReleaseBody.limit + 1), expectedLength: 1)
            XCTFail("Misleading Content-Length must not bypass streaming bound")
        } catch BoundedReleaseBody.Failure.tooLarge {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testOversizedDeclaredLengthRejectsBeforeReadingBody() async {
        let empty = AsyncStream<UInt8> { $0.finish() }
        do {
            _ = try await BoundedReleaseBody.read(empty, expectedLength: Int64(BoundedReleaseBody.limit + 1))
            XCTFail("Declared oversized response must fail")
        } catch BoundedReleaseBody.Failure.tooLarge {} catch { XCTFail("Unexpected error: \(error)") }
    }
    private func release(tag: String = "v0.0.2", draft: Bool = false, prerelease: Bool = false,
                         host: String = "github.com", assetName: String? = nil,
                         assetHost: String = "github.com", size: Int = 100,
                         state: String = "uploaded") -> PublishedRelease {
        let name = assetName ?? "Drag-2.0-\(tag)-macOS-arm64.zip"
        return PublishedRelease(tag_name: tag, draft: draft, prerelease: prerelease,
            html_url: URL(string: "https://\(host)/maxim-kich/dragtwozero/releases/tag/\(tag)")!,
            assets: [.init(name: name,
                browser_download_url: URL(string: "https://\(assetHost)/maxim-kich/dragtwozero/releases/download/\(tag)/\(name)")!,
                size: size, state: state),
                     .init(name: "appcast.xml", browser_download_url: URL(string: "https://github.com/maxim-kich/dragtwozero/releases/download/\(tag)/appcast.xml")!, size: 1024, state: "uploaded")])
    }
    func testNumericComparisonDoesNotSortLexically() {
        XCTAssertLessThan(ReleaseVersion("0.0.9")!, ReleaseVersion("v0.0.10")!)
        XCTAssertLessThan(ReleaseVersion("0.9.99")!, ReleaseVersion("1.0.0")!)
        XCTAssertEqual(ReleaseVersion("v0.0.1"), ReleaseVersion("0.0.1"))
    }
    func testRejectsNonStableAndMalformedVersions() {
        for tag in ["0.1", "1.2.3.4", "v0.0.2-beta", "1.2.3+build", "-1.0.0", " 0.0.1", "١.٢.٣", "999999999999999999999999.0.0"] {
            XCTAssertNil(ReleaseVersion(tag), tag)
        }
    }
    func testNewerStableAppleSiliconReleaseIsOffered() {
        XCTAssertEqual(release().update(current: "0.0.1")?.feed.absoluteString,
                       "https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml")
    }
    func testSameAndOlderVersionsAreNotOffered() {
        XCTAssertNil(release().update(current: "0.0.2"))
        XCTAssertNil(release().update(current: "0.0.3"))
    }
    func testDraftAndPrereleaseAreNotOffered() {
        XCTAssertNil(release(draft: true).update(current: "0.0.1"))
        XCTAssertNil(release(prerelease: true).update(current: "0.0.1"))
    }
    func testOnlyExpectedRepositoryAndDownloadHostsAllowed() {
        XCTAssertNil(release(host: "github.com.evil.example").update(current: "0.0.1"))
        XCTAssertNil(release(assetHost: "evil.example").update(current: "0.0.1"))
        let wrongRepo = PublishedRelease(tag_name: "v0.0.2", draft: false, prerelease: false,
            html_url: URL(string: "https://github.com/other/project/releases/tag/v0.0.2")!, assets: release().assets)
        XCTAssertNil(wrongRepo.update(current: "0.0.1"))
    }
    func testSourceOnlyWrongArchitectureOrEmptyAssetsNotOffered() {
        XCTAssertNil(release(assetName: "source.zip").update(current: "0.0.1"))
        XCTAssertNil(release(assetName: "Drag-2.0-v0.0.2-macOS-x86_64.zip").update(current: "0.0.1"))
        XCTAssertNil(release(size: 0).update(current: "0.0.1"))
        XCTAssertNil(release(state: "new").update(current: "0.0.1"))
        let noAssets = PublishedRelease(tag_name: "v0.0.2", draft: false, prerelease: false,
            html_url: release().html_url, assets: [])
        XCTAssertNil(noAssets.update(current: "0.0.1"))
    }
    func testDMGIsNotAnUpdaterArchive() {
        XCTAssertNil(release(assetName: "Drag-2.0-v0.0.2-macOS-arm64.dmg").update(current: "0.0.1"))
    }
    func testRequiresFeedFromTheSameOrdinaryRelease() {
        let original = release()
        let zipOnly = PublishedRelease(tag_name: original.tag_name, draft: false, prerelease: false,
                                       html_url: original.html_url, assets: [original.assets[0]])
        XCTAssertNil(zipOnly.update(current: "0.0.1"))
        for url in ["https://github.com/other/project/releases/download/v0.0.2/appcast.xml",
                    "https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.3/appcast.xml",
                    "https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml?token=bad",
                    "https://user@github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml",
                    "http://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml"] {
            let altered = PublishedRelease(tag_name: original.tag_name, draft: false, prerelease: false,
                html_url: original.html_url, assets: [original.assets[0],
                    .init(name: "appcast.xml", browser_download_url: URL(string: url)!, size: 123, state: "uploaded")])
            XCTAssertNil(altered.update(current: "0.0.1"))
        }
    }
    func testSignedFeedItemMustMatchReleaseVersionArchiveAndLength() throws {
        let selected = try XCTUnwrap(release().update(current: "0.0.1"))
        func item(version: String = "0.0.2", url: String? = nil, length: Int = 100,
                  extra: [String: Any] = [:]) throws -> SUAppcastItem {
            var values: [String: Any] = ["sparkle:version": version, "sparkle:shortVersionString": version,
                "enclosure": ["url": url ?? selected.archive.absoluteString, "length": String(length),
                              "type": "application/octet-stream"]]
            values.merge(extra) { _, replacement in replacement }
            return try XCTUnwrap(SUAppcastItem(dictionary: values))
        }
        XCTAssertTrue(selected.matches(try item()))
        XCTAssertFalse(selected.matches(try item(version: "0.0.3")))
        XCTAssertFalse(selected.matches(try item(length: 101)))
        XCTAssertFalse(selected.matches(try item(url: "https://example.com/update.zip")))
        XCTAssertFalse(selected.matches(try item(extra: ["sparkle:phasedRolloutInterval": "86400"])))
    }
    func testReleaseJSONDecoding() throws {
        let data = Data("""
        {"tag_name":"v0.0.2","draft":false,"prerelease":false,
        "html_url":"https://github.com/maxim-kich/dragtwozero/releases/tag/v0.0.2",
        "assets":[{"name":"Drag-2.0-v0.0.2-macOS-arm64.zip","size":123,"state":"uploaded",
        "browser_download_url":"https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/Drag-2.0-v0.0.2-macOS-arm64.zip"},
        {"name":"appcast.xml","size":123,"state":"uploaded",
        "browser_download_url":"https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.2/appcast.xml"}]}
        """.utf8)
        XCTAssertNotNil(try JSONDecoder().decode(PublishedRelease.self, from: data).update(current: "0.0.1"))
    }
}
