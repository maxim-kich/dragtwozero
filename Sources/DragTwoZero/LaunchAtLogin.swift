import AppKit
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// macOS owns this preference. Reading it never registers the app, and a
/// pending approval is never reported as an enabled login item.
final class LaunchAtLoginController {
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) { self.service = service }

    var status: SMAppService.Status { service.status }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled && status != .requiresApproval else { return }
            try service.register()
        } else {
            guard status == .enabled || status == .requiresApproval else { return }
            try service.unregister()
        }
    }
}

/// Shared by Settings and onboarding, including OS approval and error states.
final class LaunchAtLoginView: NSView {
    private let controller: LaunchAtLoginController
    private let openSettings: () -> Void
    private let toggle = NSSwitch()
    private let title = NSTextField(labelWithString: "Launch at login")
    private let detail = NSTextField(labelWithString: "")
    private let approval = NSButton(title: "Approval needed — open Login Items…", target: nil, action: nil)
    private var changeFailed = false

    init(frame: NSRect, leadingInset: CGFloat = 16, controller: LaunchAtLoginController,
         openSettings: @escaping () -> Void = SMAppService.openSystemSettingsLoginItems) {
        self.controller = controller
        self.openSettings = openSettings
        super.init(frame: frame)
        title.frame = NSRect(x: leadingInset, y: bounds.midY + 3, width: bounds.width - leadingInset - 100, height: 20)
        detail.frame = NSRect(x: leadingInset, y: bounds.midY - 20, width: bounds.width - leadingInset - 100, height: 18)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.setAccessibilityLabel("Launch at login status")
        toggle.frame = NSRect(x: bounds.width - 64, y: bounds.midY - 12, width: 40, height: 24)
        toggle.target = self
        toggle.action = #selector(changed)
        toggle.setAccessibilityLabel("Launch at login")
        [title, detail, toggle, approval].forEach(addSubview)
        alignSettingsLabels([title, detail], with: toggle)
        approval.frame = detail.frame.insetBy(dx: -4, dy: -3)
        approval.bezelStyle = .inline
        approval.font = .systemFont(ofSize: 12)
        approval.alignment = .left
        approval.target = self
        approval.action = #selector(openLoginItems)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        let state = controller.status
        let pending = state == .requiresApproval
        toggle.state = state == .enabled || pending ? .on : .off
        toggle.setAccessibilityHelp(pending ? "Launch at login is requested but needs approval in System Settings." : "Open Drag 2.0 automatically when you log in to your Mac.")
        approval.isHidden = !pending
        approval.title = changeFailed ? "Couldn’t change — open Login Items…" : "Approval needed — open Login Items…"
        detail.isHidden = pending
        if changeFailed {
            detail.stringValue = "Couldn’t change launch at login. Try again."
        } else {
            detail.stringValue = "Open Drag 2.0 automatically when you log in."
        }
    }

    @objc private func changed() {
        let requestedEnable = toggle.state == .on
        changeFailed = false
        do { try controller.setEnabled(requestedEnable) }
        catch { changeFailed = true }
        refresh()
        if requestedEnable && controller.status == .requiresApproval { openSettings() }
    }

    @objc private func openLoginItems() { openSettings() }
}
