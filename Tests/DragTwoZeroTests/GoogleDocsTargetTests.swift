import XCTest
@testable import DragTwoZero

final class GoogleDocsTargetTests: XCTestCase {
    func testHighlightIsCompactAndUsesCaretWhenAvailable() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = GoogleDocsTarget.highlightFrame(caret: CGRect(x: 200, y: 300, width: 1, height: 20),
                                                  pointer: CGPoint(x: 600, y: 600), viewport: viewport)
        XCTAssertEqual(rect.width, 64)
        XCTAssertEqual(rect.height, 28)
        XCTAssertEqual(rect.midX, 200.5)
        XCTAssertEqual(rect.midY, 310)
        let fallback = GoogleDocsTarget.highlightFrame(caret: .zero, pointer: CGPoint(x: 600, y: 600), viewport: viewport)
        XCTAssertEqual(fallback, CGRect(x: 568, y: 584, width: 64, height: 32))
    }
    func testOnlyGoogleDocumentEditURLsMatch() {
        XCTAssertTrue(GoogleDocsTarget.isDocumentURL("https://docs.google.com/document/d/example/edit?tab=t.0"))
        XCTAssertFalse(GoogleDocsTarget.isDocumentURL("https://docs.google.com/spreadsheets/d/example/edit"))
        XCTAssertFalse(GoogleDocsTarget.isDocumentURL("https://docs.google.com/document/d/example/preview"))
        XCTAssertFalse(GoogleDocsTarget.isDocumentURL("https://docs.google.com.example.org/document/d/example/edit"))
    }
    func testViewportExcludesToolbarAndSidePanelsWithoutDependingOnScreenOrigin() {
        let frame = CGRect(x: 200, y: 100, width: 1000, height: 800)
        let result = GoogleDocsTarget.viewport(frame, excluding: [
            CGRect(x: 200, y: 100, width: 1000, height: 100),
            CGRect(x: 200, y: 200, width: 180, height: 700),
            CGRect(x: 1160, y: 200, width: 40, height: 700),
            CGRect(x: 700, y: 500, width: 30, height: 30)
        ])
        XCTAssertEqual(result, CGRect(x: 380, y: 200, width: 780, height: 700))
        XCTAssertFalse(result.contains(CGPoint(x: 250, y: 400)))
        XCTAssertTrue(result.contains(CGPoint(x: 800, y: 400)))
    }
}
