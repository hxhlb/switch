import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var accessibility = false
    @Published var screenCapture = false

    private var timer: Timer?

    var requiresScreenCapture: Bool { SwitchPreferences.shared.showThumbnails }
    var allGranted: Bool { accessibility && (!requiresScreenCapture || screenCapture) }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        if #available(macOS 11.0, *) {
            screenCapture = CGPreflightScreenCaptureAccess()
        } else {
            screenCapture = true
        }
    }

    func openAccessibility() {
        // Trigger the prompt as well so a system pop-up appears the first time.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openScreenCapture() {
        if #available(macOS 11.0, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
