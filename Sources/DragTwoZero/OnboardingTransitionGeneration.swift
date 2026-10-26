/// Invalidates asynchronous page completions when onboarding closes or starts anew.
struct OnboardingTransitionGeneration {
    private var value: UInt64 = 0
    mutating func begin() -> UInt64 {
        value &+= 1
        return value
    }
    mutating func invalidate() { value &+= 1 }
    func accepts(_ token: UInt64) -> Bool { token == value }
}
