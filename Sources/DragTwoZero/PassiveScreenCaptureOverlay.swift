import AppKit
import ApplicationServices
import Security

enum ScreenCaptureOverlayPolicy {
    enum Owner: String, CaseIterable {
        case screenshot = "com.apple.screencaptureui"
        case recordingHelper = "com.apple.screencapture"

        var layer: Int { self == .screenshot ? Int(CGWindowLevelForKey(.mainMenuWindow)) : 1499 }
        var bundlePath: String {
            self == .screenshot ? "/System/Library/CoreServices/screencaptureui.app" : "/usr/sbin/screencapture"
        }
        var executablePath: String {
            self == .screenshot ? bundlePath + "/Contents/MacOS/screencaptureui" : bundlePath
        }

        func matches(bundleIdentifier: String?, bundlePath: String?, executablePath: String?) -> Bool {
            (self == .recordingHelper ? bundleIdentifier == nil : bundleIdentifier == rawValue)
                && bundlePath == self.bundlePath && executablePath == self.executablePath
        }
    }

    static func isFullDisplayOverlay(_ window: HitTestWindow, displays: [CGRect], owner: Owner = .screenshot) -> Bool {
        window.windowID != nil && window.alpha > 0 && window.layer == owner.layer
            && displays.contains { display in
                abs(window.frame.minX - display.minX) <= 1 && abs(window.frame.minY - display.minY) <= 1
                    && abs(window.frame.width - display.width) <= 1 && abs(window.frame.height - display.height) <= 1
            }
    }

    /// The command-line helper is used by native selected-portion recording.
    /// Its AX API is unavailable, so it is never exempted on its own: require
    /// the verified Screenshot surface at the pointer and validate Screenshot's
    /// controls and system hits across both surfaces before returning any IDs.
    static func surfaceIDs(in windows: [HitTestWindow], at point: CGPoint,
                           verifiedOwners: [pid_t: Owner], displays: [CGRect]) -> Set<CGWindowID> {
        guard windows.contains(where: {
            verifiedOwners[$0.pid] == .screenshot && $0.frame.contains(point)
                && isFullDisplayOverlay($0, displays: displays)
        }) else { return [] }
        return Set(windows.filter {
            guard let owner = verifiedOwners[$0.pid] else { return false }
            return isFullDisplayOverlay($0, displays: displays, owner: owner)
        }.compactMap(\.windowID))
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
    private struct Identity: Equatable {
        let launch: Date
        let owner: ScreenCaptureOverlayPolicy.Owner
    }
    private static let identityLock = NSLock()
    private static var verifiedLaunches: [pid_t: Identity] = [:]

    static func authorizedWindows(in windows: [HitTestWindow], at point: CGPoint,
                                   ownPID: pid_t, nativeDragActive: Bool) -> Set<CGWindowID> {
        guard !Thread.isMainThread else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }
        let displays = displayIDs.prefix(Int(count)).map(CGDisplayBounds)
        let candidates = windows.filter { window in
            window.alpha > 0 && window.frame.contains(point)
                && ScreenCaptureOverlayPolicy.Owner.allCases.contains { owner in
                    ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: displays, owner: owner)
                }
        }
        guard !candidates.isEmpty, candidates.count <= 8 else { return [] }
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
        var owners: [pid_t: ScreenCaptureOverlayPolicy.Owner] = [:]
        var checkedOwners = Set<pid_t>()
        for window in candidates {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard !checkedOwners.contains(window.pid) else { continue }
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isActive,
                  let owner = ScreenCaptureOverlayPolicy.Owner.allCases.first(where: {
                      $0.matches(bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundleURL?.path,
                                 executablePath: app.executableURL?.path)
                          && ScreenCaptureOverlayPolicy.isFullDisplayOverlay(window, displays: displays, owner: $0)
                  }), trusted(app, owner: owner) else { continue }
            checkedOwners.insert(window.pid)
            owners[window.pid] = owner
        }
        let eligible = ScreenCaptureOverlayPolicy.surfaceIDs(in: windows, at: point,
            verifiedOwners: owners, displays: displays)
        guard !eligible.isEmpty else { return [] }
        for (pid, owner) in owners where owner == .screenshot {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            let ax = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(ax, 0.05)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success,
                  let accessible = raw as? [AXUIElement], accessible.count <= 8 else { return [] }
            var frames: [CGRect] = []
            for window in accessible {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return [] }
                AXUIElementSetMessagingTimeout(window, 0.05)
                guard let frame = bounds(window) else { return [] }
                frames.append(frame)
            }
            guard ScreenCaptureOverlayPolicy.controlsAreHidden(accessibleWindowFrames: frames, windows: windows,
                overlayIDs: eligible, displays: displays, ownPID: ownPID,
                nativeDragActive: nativeDragActive, systemHitPID: systemHitPID) else { return [] }
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

    private static func trusted(_ app: NSRunningApplication, owner: ScreenCaptureOverlayPolicy.Owner) -> Bool {
        guard !app.isTerminated, owner.matches(bundleIdentifier: app.bundleIdentifier,
            bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path) else { return false }
        let identity = app.launchDate.map { Identity(launch: $0, owner: owner) }
        if let identity {
            identityLock.lock(); let cached = verifiedLaunches[app.processIdentifier] == identity; identityLock.unlock()
            if cached { return true }
        }
        var code: SecCode?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary,
                                            SecCSFlags(), &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple and identifier \"\(owner.rawValue)\"" as CFString,
                                             SecCSFlags(), &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess else { return false }
        if let identity {
            identityLock.lock()
            if verifiedLaunches.count >= 8 { verifiedLaunches.removeAll() }
            verifiedLaunches[app.processIdentifier] = identity
            identityLock.unlock()
        }
        return true
    }
}
