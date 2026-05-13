import AppKit
import Carbon.HIToolbox
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsModel: ObservableObject {
    @Published var launchAtLogin: Bool = false
    @Published var allWindows: HotkeyBinding = HotkeyConfig.shared.allWindows
    @Published var currentApp: HotkeyBinding = HotkeyConfig.shared.currentApp

    init() {
        refresh()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        allWindows = HotkeyConfig.shared.allWindows
        currentApp = HotkeyConfig.shared.currentApp
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = enabled
            } catch {
                NSLog("Switch: login-item toggle failed: \(error)")
                refresh()
            }
        }
    }

    func updateAllWindows(_ b: HotkeyBinding) {
        HotkeyConfig.shared.allWindows = b
        allWindows = b
    }

    func updateCurrentApp(_ b: HotkeyBinding) {
        HotkeyConfig.shared.currentApp = b
        currentApp = b
    }

    func resetHotkeys() {
        HotkeyConfig.shared.resetToDefaults()
        refresh()
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject private var prefs = SwitchPreferences.shared
    @State private var rejectMessage: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
    }

    private var appearanceTab: some View {
        Form {
            Section("Accent color") {
                HStack(spacing: 12) {
                    ForEach(SwitchPreferences.AccentChoice.allCases) { choice in
                        Button {
                            prefs.accent = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().stroke(
                                        prefs.accent == choice ? Color.primary : Color.secondary.opacity(0.3),
                                        lineWidth: prefs.accent == choice ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(choice.label)
                    }
                }
                .padding(.vertical, 4)
                Text("Affects the selection highlight and accent details. System follows your macOS accent.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Windows") {
                Toggle(isOn: $prefs.showCrossSpace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show windows from all Spaces")
                        Text("When off, only windows on your current Space appear. Cross-Space windows still get a badge when shown.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Switch at login")
                        Text("Run automatically when you sign in to your Mac.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Behavior") {
                Toggle(isOn: $prefs.stickyMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sticky picker")
                        Text("Release ⌘ to leave the picker open. Press Return to switch, Esc to cancel.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.disableMouse) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard only")
                        Text("Ignore mouse hover and click while the picker is open.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Hotkeys") {
                hotkeyEditor(label: "All windows", binding: model.allWindows) { b in
                    if let msg = HotkeyValidator.reject(keyCode: b.keyCode, flags: b.cgFlags) {
                        rejectMessage = msg
                    } else {
                        rejectMessage = nil
                        model.updateAllWindows(b)
                    }
                }
                hotkeyEditor(label: "Current app", binding: model.currentApp) { b in
                    if let msg = HotkeyValidator.reject(keyCode: b.keyCode, flags: b.cgFlags) {
                        rejectMessage = msg
                    } else {
                        rejectMessage = nil
                        model.updateCurrentApp(b)
                    }
                }
                if let msg = rejectMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        rejectMessage = nil
                        model.resetHotkeys()
                    }
                    .controlSize(.small)
                }

                Text("Type filters · Esc cancels · → closes the selected window · ⇧ reverses.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
    }

    private func hotkeyEditor(label: String, binding: HotkeyBinding, onCapture: @escaping (HotkeyBinding) -> Void) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            KeyRecorderField(initialBinding: binding, onCapture: onCapture)
                .frame(width: 160, height: 24)
            Spacer()
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("Switch")
                .font(.system(size: 22, weight: .semibold))
            Text("Version \(appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let stamp = buildStamp {
                Text(stamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Text("A keyboard-driven window switcher for macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 18) {
                Link("Website", destination: URL(string: "https://switch-dev.sanyamgarg.com")!)
                Link("@sanyamg_", destination: URL(string: "https://x.com/sanyamg_")!)
            }
            .font(.system(size: 12))
            Button("Check for Updates…") {
                NotificationCenter.default.post(name: .switchCheckForUpdates, object: nil)
            }
            .controlSize(.small)
            Text("© 2026 Sanyam Garg. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    /// nil in debug builds; release.sh stamps the plist.
    private var buildStamp: String? {
        let info = Bundle.main.infoDictionary
        guard let commit = info?["BuildCommit"] as? String,
              let date = info?["BuildDate"] as? String,
              !commit.isEmpty else { return nil }
        return "\(commit) · \(date)"
    }
}

// MARK: - Key recorder

struct KeyRecorderField: NSViewRepresentable {
    let initialBinding: HotkeyBinding
    let onCapture: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let v = KeyRecorderNSView()
        v.binding = initialBinding
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ view: KeyRecorderNSView, context: Context) {
        if view.binding != initialBinding {
            view.binding = initialBinding
        }
        view.onCapture = onCapture
    }
}

final class KeyRecorderNSView: NSView {
    var onCapture: ((HotkeyBinding) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var recording = false { didSet { redraw() } }

    var binding: HotkeyBinding = .defaultAllWindows {
        didSet { redraw() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        redraw()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if recording { stopRecording(commit: false) } else { startRecording() }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording(commit: false)
        return super.resignFirstResponder()
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    private func startRecording() {
        recording = true
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown {
                let nsMods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var cg: CGEventFlags = []
                if nsMods.contains(.command) { cg.insert(.maskCommand) }
                if nsMods.contains(.option) { cg.insert(.maskAlternate) }
                if nsMods.contains(.control) { cg.insert(.maskControl) }
                if nsMods.contains(.shift) { cg.insert(.maskShift) }
                let b = HotkeyBinding(keyCode: e.keyCode, modifiersRaw: cg.rawValue)
                self.binding = b
                self.onCapture?(b)
                self.stopRecording(commit: true)
                return nil
            }
            return e
        }
    }

    private func stopRecording(commit: Bool) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
    }

    private func redraw() {
        if recording {
            label.stringValue = "Press a key…"
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        } else {
            label.stringValue = binding.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}
