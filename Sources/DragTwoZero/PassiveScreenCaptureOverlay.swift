import AppKit
import ApplicationServices
import Security

enum ScreenCaptureOverlayPolicy {
    static func isFullDisplayOverlay(_ window: HitTestWindow, displays: [CGRect]) -> Bool {
        window.windowID != nil && window.layer == Int(CGWindowLevelForKey(.mainMenuWindow))
            && displays.contains { display in
                abs(window.frame.minX - display.minX) <= 1 && abs(window.frame.minY - display.minY) <= 1
                    && abs(window.frame.width - display.width) <= 1 && abs(window.frame.height - display.height) <= 1
            }
    }

    /// During recording, AXWindows can retain the hidden toolbar. Its presence
    /// alone does not prove that capture controls are still on screen. Require
    /// a fresh system hit at each retained window to agree with the real app
    /// beneath the exact full-display recording surfaces.
    static func controlsAreHidden(accessibleWindowFrames: [CGRect]?, windows: [HitTestWindow],
                                  overlayIDs: Set<CGWindowID>, displays: [CGRect], ownPID: pid_t,
                                  nativeDragActive: Bool, systemHitPID: (CGPoint) -> pid_t?) -> Bool {
        guard let accessibleWindowFrames, accessibleWindowFrames.count <= 8 else { return false }
        for frame in accessibleWindowFrames {
            guard !frame.isNull, !frame.isInfinite,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
                  let visible = displays.map({ frame.intersection($0) })
                    .filter({ !$0.isNull && !$0.isEmpty }).max(by: { $0.width * $0.height < $1.width * $1.height }) else { return false }
            let point = CGPoint(x: visible.midX, y: visible.midY)
            guard case let .application(pid) = WindowHitPolicy.resolve(windows, at: point, ownPID: ownPID,
                    nativeDragActive: nativeDragActive, passiveScreenCaptureWindows: overlayIDs),
                  pid > 0, systemHitPID(point) == pid else { return false }
        }
        return true
    }

    static func allowsPassThrough(trustedOwner: Bool, ownerActive: Bool, captureControlsHidden: Bool,
                                  underlyingPID: pid_t, globalHitPID: pid_t?, ownPID: pid_t,
                                  ownOverlayAtPoint: Bool) -> Bool {
        guard trustedOwner, !ownerActive, captureControlsHidden, underlyingPID > 0,
              let globalHitPID, globalHitPID > 0 else { return false }
        return globalHitPID == underlyingPID || (globalHitPID == ownPID && ownOverlayAtPoint)
    }
}

/// Screenshot can leave a full-display, noninteractive window above normal apps.
/// Authorize its exact window IDs, never its owner name or arbitrary recording
/// windows. This runs on the existing AX workers, not the event tap.
enum PassiveScreenCaptureOverlay {
    private static let identityLock = NSLock()
    private static var verifiedLaunches: [pid_t: Date] = [:]

    static func authorizedWindows(in windows: [HitTestWindow], at point: CGPoint,
                                   ownPID: pid_t, nativeDragActive: Bool) -> Set<CGWindowID> {
        guard !Thread.isMainThread else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }
        let displays = displayIDs.prefix(Int(count)).map(CGDisplayBounds)
        let candidates = windows.filter {
            $0.alpha > 0 && $0.frame.contains(point)
                && ScreenCaptureOverlayPolicy.isFullDisplayOverlay($0, displays: displays)
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        func systemHitPID(at point: CGPoint) -> pid_t? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
                  let hit else { return nil }
            var pid: pid_t = 0
            guard AXUIElementGetPid(hit, &pid) == .success,
                  ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            return pid
        }
        var eligible = Set<CGWindowID>()
        var checkedOwners = Set<pid_t>()
        for window in candidates {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard checkedOwners.insert(window.pid).inserted else { continue }
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isActive,
                  trustedScreenshot(app) else { continue }
            let ax = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(ax, 0.05)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success,
                  let accessible = raw as? [AXUIElement], accessible.count <= 8 else { continue }
            var frames: [CGRect] = []
            for window in accessible {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return [] }
                AXUIElementSetMessagingTimeout(window, 0.05)
                guard let frame = bounds(window) else { return [] }
                frames.append(frame)
            }
            let ownerOverlays = Set(windows.filter {
                $0.pid == window.pid && $0.alpha > 0
                    && ScreenCaptureOverlayPolicy.isFullDisplayOverlay($0, displays: displays)
            }.compactMap(\.windowID))
            guard ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: frames, windows: windows,
                overlayIDs: ownerOverlays, displays: displays, ownPID: ownPID,
                nativeDragActive: nativeDragActive, systemHitPID: systemHitPID) else { continue }
            eligible.formUnion(ownerOverlays)
        }
        guard !eligible.isEmpty,
              case let .application(underlyingPID) = WindowHitPolicy.resolve(windows, at: point, ownPID: ownPID,
                nativeDragActive: nativeDragActive, passiveScreenCaptureWindows: eligible) else { return [] }
        guard let hitPID = systemHitPID(at: point) else { return [] }
        let ownOverlay = windows.contains {
            $0.pid == ownPID && $0.alpha > 0 && $0.frame.contains(point)
                && ($0.layer == CaptureWindowLayers.hint.rawValue
                    || (nativeDragActive && $0.layer == Int(CGWindowLevelForKey(.draggingWindow))))
        }
        return ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: true, ownerActive: false,
            captureControlsHidden: true, underlyingPID: underlyingPID, globalHitPID: hitPID,
            ownPID: ownPID, ownOverlayAtPoint: ownOverlay) ? eligible : []
    }

    private static func trustedScreenshot(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.bundleIdentifier == "com.apple.screencaptureui",
              app.bundleURL?.path == "/System/Library/CoreServices/screencaptureui.app",
              app.executableURL?.path == "/System/Library/CoreServices/screencaptureui.app/Contents/MacOS/screencaptureui" else { return false }
        if let launch = app.launchDate {
            identityLock.lock(); let cached = verifiedLaunches[app.processIdentifier] == launch; identityLock.unlock()
            if cached { return true }
        }
        var code: SecCode?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary,
                                            SecCSFlags(), &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.screencaptureui\"" as CFString,
                                             SecCSFlags(), &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess else { return false }
        if let launch = app.launchDate {
            identityLock.lock()
            if verifiedLaunches.count >= 8 { verifiedLaunches.removeAll() }
            verifiedLaunches[app.processIdentifier] = launch
            identityLock.unlock()
        }
        return true
    }
}
