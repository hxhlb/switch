import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 460, height: 320)
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
