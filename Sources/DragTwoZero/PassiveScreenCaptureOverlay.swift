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

    static func allowsPassThrough(trustedOwner: Bool, ownerActive: Bool, accessibleWindowCount: Int?,
                                  underlyingPID: pid_t, globalHitPID: pid_t?, ownPID: pid_t,
                                  ownOverlayAtPoint: Bool) -> Bool {
        guard trustedOwner, !ownerActive, accessibleWindowCount == 0, underlyingPID > 0,
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
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }
        let displays = displayIDs.prefix(Int(count)).map(CGDisplayBounds)
        let candidates = windows.filter {
            $0.alpha > 0 && $0.frame.contains(point)
                && ScreenCaptureOverlayPolicy.isFullDisplayOverlay($0, displays: displays)
        }
        var eligible = Set<CGWindowID>()
        for window in candidates {
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isActive,
                  trustedScreenshot(app), let id = window.windowID else { continue }
            let ax = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(ax, 0.08)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success,
                  let accessible = raw as? [AXUIElement], accessible.isEmpty else { continue }
            eligible.insert(id)
        }
        guard !eligible.isEmpty,
              case let .application(underlyingPID) = WindowHitPolicy.resolve(windows, at: point, ownPID: ownPID,
                nativeDragActive: nativeDragActive, passiveScreenCaptureWindows: eligible) else { return [] }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return [] }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success else { return [] }
        let ownOverlay = windows.contains {
            $0.pid == ownPID && $0.alpha > 0 && $0.frame.contains(point)
                && ($0.layer == CaptureWindowLayers.hint.rawValue
                    || (nativeDragActive && $0.layer == Int(CGWindowLevelForKey(.draggingWindow))))
        }
        return ScreenCaptureOverlayPolicy.allowsPassThrough(trustedOwner: true, ownerActive: false,
            accessibleWindowCount: 0, underlyingPID: underlyingPID, globalHitPID: hitPID,
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
