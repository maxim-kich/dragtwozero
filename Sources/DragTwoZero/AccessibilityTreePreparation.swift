import ApplicationServices
import Foundation

/// Some web-based apps expose their text tree only when an assistive client
/// requests it. Electron documents AXManualAccessibility for this purpose:
/// https://www.electronjs.org/docs/latest/tutorial/accessibility
/// Call only from AX workers, never from the input callback or main thread.
final class AccessibilityTreePreparation {
    static let shared = AccessibilityTreePreparation()
    private let lock = NSLock()
    private var attempts: [pid_t: TimeInterval] = [:]

    func prepare(pid: pid_t, now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                 enable: () -> AXError) {
        guard pid != getpid() else { return }
        lock.lock()
        if let next = attempts[pid], now < next { lock.unlock(); return }
        if attempts.count >= 128 { attempts = attempts.filter { $0.value > now } }
        if attempts.count >= 128 { attempts.removeAll() }
        // Reserve before the AX call so concurrent discovery does not repeat it.
        attempts[pid] = now + 1
        lock.unlock()
        let result = enable()
        lock.lock()
        // Retry transient failures, and eventually recheck after app restarts or
        // an application disables its tree. Never turn another client's tree off.
        attempts[pid] = now + (result == .success || result == .attributeUnsupported ? 5 : 1)
        lock.unlock()
    }
}
