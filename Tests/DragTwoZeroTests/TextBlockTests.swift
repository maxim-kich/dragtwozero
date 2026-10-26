import XCTest
@testable import DragTwoZero

final class TextBlockTests: XCTestCase {
    func testInlineLinksKeepTextOrderAndWhitespace() {
        let fragment = TextFragment.group([.text("Read the "), .link("guide", URL(string: "https://example.com/guide")!), .text(" and then "), .link("examples", URL(string: "https://example.com/examples")!), .text(".\nNext line.")])
        XCTAssertEqual(fragment.markdown, "Read the [guide](https://example.com/guide) and then [examples](https://example.com/examples).\nNext line.")
    }
    func testMarkdownEscapesLabelsAndURLParentheses() {
        XCTAssertEqual(TextFragment.link("[a]*", URL(string: "https://example.com/a(b)")!).markdown, "[\\[a\\]\\*](https://example.com/a%28b%29)")
    }
    func testRepeatedLabelsPreserveDifferentDestinations() {
        let fragment = TextFragment.group([.link("here", URL(string: "https://one.test")!), .text(" or "), .link("here", URL(string: "https://two.test")!)])
        XCTAssertEqual(fragment.markdown, "[here](https://one.test) or [here](https://two.test)")
    }
}
