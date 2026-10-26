import Foundation

/// Shared by main-thread cancellation and off-main delivery work.
final class CaptureCommitToken {
    private let lock = NSLock()
    private var valid = true
    private var dispatched = false
    private let deadline: TimeInterval?
    init(timeout: TimeInterval? = nil) {
        deadline = timeout.map { ProcessInfo.processInfo.systemUptime + $0 }
    }
    var isValid: Bool {
        lock.lock(); defer { lock.unlock() }
        return valid && (deadline.map { ProcessInfo.processInfo.systemUptime < $0 } ?? true)
    }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return !valid
    }
    var wasDispatched: Bool {
        lock.lock(); defer { lock.unlock() }
        return dispatched
    }
    /// Cancellation can stop a pending write, but cannot undo an already posted
    /// paste. Its bounded, read-only receipt must still reconcile Buffer state.
    func allowsReadOnlyReceipt(beforeDeadline: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dispatched && beforeDeadline
    }
    /// Serialize cancellation with the two short keyboard-event posts. Never do
    /// AX reads, clipboard work, or other blocking operations under this lock.
    @discardableResult func dispatch(_ post: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard valid, deadline.map({ ProcessInfo.processInfo.systemUptime < $0 }) ?? true, !dispatched else { return false }
        post()
        dispatched = true
        return true
    }
    /// A successful AX cell write is already irreversible. Record its result
    /// after the call, without holding the event-tap cancellation lock across AX.
    func recordDispatched() {
        lock.lock(); defer { lock.unlock() }
        dispatched = true
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        valid = false
    }
}

/// Resolve at the acceptance point off the event-tap loop. A late result must
/// never commit a gesture which has since been cancelled or replaced.
final class CaptureValidation {
    private let queue = DispatchQueue(label: "capture.commitValidation", qos: .userInteractive)

    func validate<Value>(expected: Value, resolve: @escaping () -> Value?,
                         matches: @escaping (Value, Value) -> Bool,
                         cancellation: CaptureCommitToken? = nil,
                         isCurrent: @escaping () -> Bool,
                         completion: @escaping (Value?) -> Void) {
        queue.async {
            guard cancellation?.isCancelled != true else { return }
            let current = cancellation?.isValid == false ? nil : resolve()
            guard cancellation?.isCancelled != true else { return }
            // A timed-out active request still completes with nil so its UI
            // can reset. Canceled/replaced requests fail the main-thread gate.
            let accepted = cancellation?.isValid == false ? nil : current.flatMap { matches(expected, $0) ? $0 : nil }
            DispatchQueue.main.async {
                guard cancellation?.isCancelled != true, isCurrent() else { return }
                completion(cancellation?.isValid == false ? nil : accepted)
            }
        }
    }
}
