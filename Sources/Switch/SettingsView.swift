import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 360)
    }
}

private struct GeneralTab: View {
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else  { try SMAppService.mainApp.unregister() }
                        } catch {
                            print("[settings] launch-at-login toggle failed: \(error)")
                        }
                    }
            }
            Section("Hotkey") {
                LabeledContent("Cycle all windows", value: "⌘-Tab")
                LabeledContent("Cycle in current app", value: "⌥-`")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 96, height: 96)
            }
            Text("Switch").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary).font(.callout)
            HStack(spacing: 18) {
                Link("Website", destination: URL(string: "https://switch-dev.sanyamgarg.com")!)
                Link("Source", destination: URL(string: "https://github.com/Sanyam-G/switch")!)
            }
            .font(.callout)
            Spacer()
        }
        .padding(24)
    }
}
