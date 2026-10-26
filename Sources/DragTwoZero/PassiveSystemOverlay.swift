import AppKit
import ApplicationServices
import Security

/// These are observed compositor surfaces, not an exemption for every window
/// owned by Dock or Notification Center. Geometry and a fresh system AX hit are
/// required in addition to the exact Apple code identity.
enum PassiveSystemOverlayPolicy {
    enum Owner: String {
        case notificationCenter = "com.apple.notificationcenterui"
        case dock = "com.apple.dock"
        var layer: Int { self == .notificationCenter ? 21 : 20 }
        var appPath: String {
            "/System/Library/CoreServices/" + (self == .notificationCenter ? "NotificationCenter.app" : "Dock.app")
        }
    }

    static func isCandidate(_ window: HitTestWindow, owner: Owner, displays: [CGRect]) -> Bool {
        window.windowID != nil && window.alpha > 0 && window.layer == owner.layer
            && displays.contains {
                abs($0.minX - window.frame.minX) <= 1 && abs($0.minY - window.frame.minY) <= 1
                    && abs($0.width - window.frame.width) <= 1 && abs($0.height - window.frame.height) <= 1
            }
    }

    static func allowsPassThrough(underlyingPID: pid_t, systemHitPID: pid_t?) -> Bool {
        // No own-overlay fallback here: a fresh global hit must reach the same
        // real app that the window stack predicts beneath the passive surfaces.
        underlyingPID > 0 && systemHitPID == underlyingPID
    }
}

enum PassiveSystemOverlay {
    private struct Identity: Equatable {
        let launch: Date
        let owner: PassiveSystemOverlayPolicy.Owner
    }
    private static let lock = NSLock()
    private static var verified: [pid_t: Identity] = [:]

    static func authorizedWindows(in windows: [HitTestWindow], at point: CGPoint,
                                  ownPID: pid_t, nativeDragActive: Bool,
                                  diagnostic: (StaticString) -> Void = { _ in }) -> Set<CGWindowID> {
        // This function is used by AX workers, never by rendering or the tap.
        guard !Thread.isMainThread else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }
        let displays = displayIDs.prefix(Int(count)).map(CGDisplayBounds)
        let candidates = windows.filter {
            $0.alpha > 0 && $0.frame.contains(point) && [20, 21].contains($0.layer)
        }
        guard !candidates.isEmpty, candidates.count <= 8 else { return [] }
        var eligible = Set<CGWindowID>()
        for window in candidates {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                diagnostic("system-overlay-validation-timeout"); return []
            }
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isActive,
                  let owner = PassiveSystemOverlayPolicy.Owner(rawValue: app.bundleIdentifier ?? ""),
                  PassiveSystemOverlayPolicy.isCandidate(window, owner: owner, displays: displays),
                  trusted(app, owner: owner), let id = window.windowID else { continue }
            eligible.insert(id)
        }
        guard !eligible.isEmpty,
              case let .application(underlying) = WindowHitPolicy.resolve(windows, at: point, ownPID: ownPID,
                nativeDragActive: nativeDragActive, passiveSystemWindows: eligible) else { return [] }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            diagnostic("system-overlay-validation-timeout"); return []
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.06)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { diagnostic("system-overlay-hit-unavailable"); return [] }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success,
              ProcessInfo.processInfo.systemUptime < deadline else {
            diagnostic("system-overlay-validation-timeout"); return []
        }
        guard PassiveSystemOverlayPolicy.allowsPassThrough(underlyingPID: underlying, systemHitPID: hitPID) else {
            if hitPID == ownPID { diagnostic("system-overlay-hit-own-app") }
            else if windows.contains(where: { $0.pid == hitPID && $0.windowID.map(eligible.contains) == true }) {
                diagnostic("system-overlay-hit-controls")
            } else { diagnostic("system-overlay-hit-mismatch") }
            return []
        }
        diagnostic("system-overlay-pass-through")
        return eligible
    }

    static func trusted(_ app: NSRunningApplication, owner: PassiveSystemOverlayPolicy.Owner) -> Bool {
        guard !app.isTerminated, app.bundleIdentifier == owner.rawValue, app.bundleURL?.path == owner.appPath else { return false }
        // Some system agents have no launchDate. Verify those live every time;
        // never reject them or cache by a reusable PID alone.
        let identity = app.launchDate.map { Identity(launch: $0, owner: owner) }
        if let identity {
            lock.lock(); let cached = verified[app.processIdentifier] == identity; lock.unlock()
            if cached { return true }
        }
        var code: SecCode?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary,
            SecCSFlags(), &code) == errSecSuccess, let code,
            SecRequirementCreateWithString("anchor apple and identifier \"\(owner.rawValue)\"" as CFString,
                SecCSFlags(), &requirement) == errSecSuccess, let requirement,
            SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess else { return false }
        if let identity {
            lock.lock()
            if verified.count >= 16 { verified.removeAll() }
            verified[app.processIdentifier] = identity
            lock.unlock()
        }
        return true
    }
}
