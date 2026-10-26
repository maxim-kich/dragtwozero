import Foundation

/// Compact composition keeps full-sized text and controls within the short viewport.
struct CompactOnboardingComposition {
    let headingY: CGFloat
    let detailY: CGFloat
    let iconY: CGFloat
    let bodyY: CGFloat
    init(height: CGFloat, finalPage: Bool) {
        if finalPage {
            // Menu cue occupies the top 82 points; center the remaining 286-point stack.
            let origin = max(0, (height - 82 - 286) / 2)
            bodyY = origin
            detailY = origin + 126
            headingY = origin + 216
            iconY = 0
        } else {
            let origin = max(0, (height - 270) / 2)
            detailY = origin
            headingY = origin + 90
            iconY = origin + 206
            bodyY = 0
        }
    }
}
