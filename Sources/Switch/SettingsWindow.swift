import AppKit
import SwiftUI

/// Promotes app to .regular while open, reverts to .accessory on close.
/// Required because SwiftUI's Settings scene + .accessory don't cooperate.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    private init() {}

    func show() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        if let existing = window {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        let host = NSHostingController(rootView: SettingsView())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Switch Settings"
        win.contentViewController = host
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = SettingsWindowDelegate.shared

        window = win
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    func handleClose() {
        window = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            SettingsWindow.shared.handleClose()
        }
    }
}
