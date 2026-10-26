import AppKit

enum CapturePreferences {
    static let bufferEnabledKey = "bufferEnabled"
    static let bufferPositionKey = "bufferPosition"
    static var bufferEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: bufferEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: bufferEnabledKey) }
    }
    static var bufferPosition: BufferPosition {
        get { BufferPosition(rawValue: UserDefaults.standard.string(forKey: bufferPositionKey) ?? "") ?? .notch }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bufferPositionKey) }
    }
    static let selectedTextDraggingKey = "selectedTextDraggingEnabled"
    static var selectedTextDraggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: selectedTextDraggingKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedTextDraggingKey) }
    }
    static var overwriteClipboard: Bool {
        get { UserDefaults.standard.bool(forKey: "overwriteClipboard") }
        set { UserDefaults.standard.set(newValue, forKey: "overwriteClipboard") }
    }
    static var multiselectEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "multiselectEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "multiselectEnabled") }
    }
    static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsEnabled") }
    }
    static var liquidGlassEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liquidGlassEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "liquidGlassEnabled") }
    }
    static var borderAppearance: BorderAppearance {
        get { BorderAppearance(rawValue: UserDefaults.standard.string(forKey: "borderAppearance") ?? "system") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "borderAppearance") }
    }
    static var borderColor: BorderColor {
        get { BorderColor(rawValue: UserDefaults.standard.string(forKey: "borderColor") ?? "accent") ?? .accent }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "borderColor") }
    }
    static var animationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "animationsEnabled") }
    }
    static var animationSpeed: Double {
        get {
            let value = UserDefaults.standard.object(forKey: "animationSpeed") as? Double ?? 1
            return value.isFinite ? min(2, max(0.5, value)) : 1
        }
        set { UserDefaults.standard.set(newValue.isFinite ? min(2, max(0.5, newValue)) : 1, forKey: "animationSpeed") }
    }
    static func animationDuration(_ duration: TimeInterval) -> TimeInterval {
        scaledAnimationDuration(duration, enabled: animationsEnabled && liquidGlassEnabled, speed: animationSpeed,
                                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    static let structureKey = "preserveContentStructure"
    static var preserveStructure: Bool {
        get { UserDefaults.standard.bool(forKey: structureKey) }
        set { UserDefaults.standard.set(newValue, forKey: structureKey) }
    }
}

func structuredMarkdown(_ text: String, role: String, subrole: String, headingLevel: Int?) -> String {
    if role == "AXHeading" || subrole == "AXHeading" {
        return String(repeating: "#", count: min(6, max(1, headingLevel ?? 1))) + " " + text
    }
    if role == "AXListItem" || subrole == "AXListItem" {
        var body = text
        for bullet in ["• ", "◦ ", "▪ ", "- "] where body.hasPrefix(bullet) {
            body.removeFirst(bullet.count)
            break
        }
        if let range = body.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            let marker = body[range].replacingOccurrences(of: ")", with: ".")
            return marker + body[range.upperBound...].replacingOccurrences(of: "\n", with: "\n   ")
        }
        return "- " + body.replacingOccurrences(of: "\n", with: "\n  ")
    }
    return text
}

func scaledAnimationDuration(_ duration: TimeInterval, enabled: Bool, speed: Double, reduceMotion: Bool) -> TimeInterval {
    guard enabled, !reduceMotion else { return 0 }
    let speed = speed.isFinite ? min(2, max(0.5, speed)) : 1
    return max(0, duration) / speed
}

enum BorderColor: String, CaseIterable {
    case accent, blue, purple, pink, red, orange, yellow, green, gray
    var title: String { self == .accent ? "System accent" : rawValue.capitalized }
    var color: NSColor {
        switch self {
        case .accent: return .controlAccentColor
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .gray: return .systemGray
        }
    }
}

enum BorderAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
