import Foundation
import CoreGraphics

/// Window-server front-to-back order is authoritative, including floating surfaces.
struct HitTestWindow {
    let pid: pid_t
    let layer: Int
    let frame: CGRect
    var alpha: Double = 1
    var windowID: CGWindowID? = nil
}

enum WindowHitResolution: Equatable {
    case application(pid_t)
    case blocked
    case none
}

enum WindowHitPolicy {
    static func resolve(_ windows: [HitTestWindow], at point: CGPoint, ownPID: pid_t,
                        captureOverlayLayer: Int = CaptureWindowLayers.hint.rawValue,
                        nativeDragActive: Bool = false,
                        passiveScreenCaptureWindows: Set<CGWindowID> = [],
                        passiveSystemWindows: Set<CGWindowID> = [],
                        cursorLayer: Int = Int(CGWindowLevelForKey(.cursorWindow))) -> WindowHitResolution {
        for window in windows where window.alpha > 0 && window.frame.contains(point) {
            // The Window Server cursor is itself a window under the pointer.
            // Its exact reserved public layer identifies this noninteractive
            // surface; no broad system/recording/floating layer exemption.
            if window.layer == cursorLayer { continue }
            // Both Screenshot and its selected-portion helper need exact IDs
            // authorized together by the recording policy, never a layer exemption.
            if [Int(CGWindowLevelForKey(.mainMenuWindow)), ScreenCaptureOverlayPolicy.Owner.recordingHelper.layer].contains(window.layer),
               let id = window.windowID, passiveScreenCaptureWindows.contains(id) { continue }
            if [20, 21].contains(window.layer), let id = window.windowID,
               passiveSystemWindows.contains(id) { continue }
            // Only our known noninteractive capture surfaces are transparent to
            // capture. Own normal windows are sources and still occlude apps below.
            if window.pid == ownPID && window.layer == captureOverlayLayer { continue }
            if nativeDragActive && window.pid == ownPID && window.layer == Int(CGWindowLevelForKey(.draggingWindow)) { continue }
            guard window.layer == 0 else { return .blocked }
            return .application(window.pid)
        }
        return .none
    }
}
