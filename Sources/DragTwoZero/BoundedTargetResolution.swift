import Foundation

enum TargetLookupResult<Value> {
    case found(Value)
    case operationallyUnavailable
    case rejected
}

/// Read-only acceptance recovery. Never substitutes the retained target for a
/// fresh lookup, and never retries a mismatch or a known terminal rejection.
enum BoundedTargetResolution {
    static func resolve<Value>(expected: Value, deadline: TimeInterval, allowsRecovery: Bool,
                               isCurrent: () -> Bool,
                               clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                               lookup: () -> TargetLookupResult<Value>, matches: (Value, Value) -> Bool,
                               diagnostic: (StaticString) -> Void = { _ in }) -> Value? {
        func live() -> Bool {
            guard isCurrent() else { diagnostic("target-resolution-cancelled"); return false }
            guard clock() < deadline else { diagnostic("target-resolution-deadline"); return false }
            return true
        }
        // A direct cell write has no captured text-selection/value snapshot.
        let isCell = (expected as? InputTarget)?.cellValueElement != nil
        for attempt in 0..<2 {
            guard live() else { return nil }
            let result = lookup()
            guard live() else { return nil }
            switch result {
            case .found(let current):
                guard matches(expected, current) else { diagnostic("target-resolution-mismatch"); return nil }
                guard live() else { return nil }
                diagnostic(attempt == 0 ? "target-resolution-found" : "target-resolution-recovered")
                return current
            case .rejected:
                diagnostic("target-resolution-terminal"); return nil
            case .operationallyUnavailable:
                guard allowsRecovery, !isCell, attempt == 0 else {
                    diagnostic("target-resolution-unavailable"); return nil
                }
                diagnostic("target-resolution-reread")
            }
        }
        return nil
    }
}
