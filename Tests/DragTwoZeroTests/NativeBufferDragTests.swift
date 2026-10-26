import AppKit
import XCTest
@testable import DragTwoZero

final class NativeBufferDragTests: XCTestCase {
    private func plan(_ edits: [EditorInsertionState]) -> NativeDropPlan {
        let element = AXUIElementCreateApplication(getpid())
        let target = InputTarget(element: element, app: .current, frame: .init(x: 0, y: 0, width: 300, height: 100),
                                 dropPoint: .init(x: 60, y: 30), insertionRange: CFRange(location: 5, length: 0), caretFrame: .zero)
        return NativeDropPlan(target: target, expectedEdits: edits)
    }
    func testNativeConfirmationRequiresOneExactEditAtAuthorizedHitBoundary() {
        let plan = plan([.init(location: 5, length: 0, value: "LEFT|RIGHT"), .init(location: 6, length: 0, value: "LEFT|RIGHT")])
        XCTAssertTrue(plan.confirms("ALPHA", observed: "LEFT|ALPHARIGHT"))
        XCTAssertTrue(plan.confirms("ALPHA", observed: "LEFT|RALPHAIGHT"))
        XCTAssertFalse(plan.confirms("ALPHA", observed: "LEFT|RIALPHAGHT"))
        XCTAssertFalse(plan.confirms("ALPHA", observed: "LEFT|ALPHAALPHARIGHT"))
        XCTAssertFalse(plan.confirms("ALPHA", observed: "changed|ALPHARIGHT"))
        XCTAssertFalse(plan.confirms("ALPHA", observed: "LEFT|RIGHT"))
    }
    func testNativeConfirmationPreservesExactUnicodeAndIntentionalSelectionAuthority() {
        let payload = "Café 🌍 e\u{301}\nBRAVO"
        let plan = plan([.init(location: 5, length: 5, value: "LEFT|RIGHT")])
        XCTAssertTrue(plan.confirms(payload, observed: "LEFT|" + payload))
        XCTAssertFalse(plan.confirms(payload, observed: "LEFT|Café 🌍 é\nBRAVO"))
        XCTAssertFalse(plan.confirms(payload, observed: "LEFT|" + payload + "RIGHT"))
    }
    func testOnlyActiveOwnNativeDragImageIsTransparentToHitTesting() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 100), point = CGPoint(x: 40, y: 40)
        let image = HitTestWindow(pid: 101, layer: Int(CGWindowLevelForKey(.draggingWindow)), frame: frame)
        let editor = HitTestWindow(pid: 202, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([image, editor], at: point, ownPID: 101), .blocked)
        XCTAssertEqual(WindowHitPolicy.resolve([image, editor], at: point, ownPID: 101, nativeDragActive: true), .application(202))
        let foreign = HitTestWindow(pid: 303, layer: image.layer, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([foreign, editor], at: point, ownPID: 101, nativeDragActive: true), .blocked)
        let settings = HitTestWindow(pid: 101, layer: 0, frame: frame)
        XCTAssertEqual(WindowHitPolicy.resolve([settings, editor], at: point, ownPID: 101, nativeDragActive: true), .application(101))
    }
}
