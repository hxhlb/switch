import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: SwitchModel?
    private var hotkey: HotkeyManager?
    private var window: SwitcherWindow?
    private var statusBar: StatusBarController?
    private var onboardingModel: OnboardingModel?
    private var onboardingWindow: NSWindow?
    private var hotkeyStarted = false
    private var permsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = SwitchModel()
        let window = SwitcherWindow(model: model)
        let hotkey = HotkeyManager()

        hotkey.onArm = { mode in
            model.arm(mode)
            window.present()
        }
        hotkey.onAdvance = { reverse in
            model.advance(reverse: reverse)
        }
        let commitAndDismiss: () -> Void = {
            model.commit()
            window.dismiss()
        }
        hotkey.onCommit = commitAndDismiss
        model.commitAndDismiss = commitAndDismiss
        let cancelAndDismiss: () -> Void = {
            model.cancel()
            window.dismiss()
        }
        hotkey.onCancel = cancelAndDismiss
        model.cancelAndDismiss = cancelAndDismiss
        hotkey.onCloseSelected = {
            model.closeSelected()
        }
        hotkey.onHideSelected = {
            model.hideSelected()
        }
        hotkey.onNavigate = { direction in
            model.navigate(direction: direction)
        }
        hotkey.onPickIndex = { index in
            model.pickIndex(index)
        }
        hotkey.onFilterAppend = { c in
            model.appendFilter(c)
        }
        hotkey.onFilterBackspace = {
            model.backspaceFilter()
        }

        self.model = model
        self.hotkey = hotkey
        self.window = window
        self.statusBar = StatusBarController()
        self.onboardingModel = OnboardingModel()

        NotificationCenter.default.addObserver(
            self, selector: #selector(showOnboarding),
            name: .switchShowOnboarding, object: nil
        )
        NotificationCenter.default.addObserver(
            forName: HotkeyConfig.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotkey?.reload()
        }

        // Show onboarding if any permission is missing; otherwise install the tap.
        let needs = !AXIsProcessTrusted() || (CGPreflightScreenCaptureAccess() == false)
        if needs {
            showOnboarding()
        } else {
            startHotkeyIfNeeded()
        }

        // Background poll: as soon as both are granted, install the tap.
        permsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() && CGPreflightScreenCaptureAccess() {
                self.startHotkeyIfNeeded()
            }
        }
    }

    private func startHotkeyIfNeeded() {
        guard !hotkeyStarted else { return }
        hotkey?.start()
        hotkeyStarted = true
    }

    @objc private func showOnboarding() {
        guard let onboardingModel else { return }
        if onboardingWindow == nil {
            let host = NSHostingView(rootView: OnboardingView().environmentObject(onboardingModel))
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Switch"
            win.contentView = host
            win.center()
            win.isReleasedWhenClosed = false
            onboardingWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SwitcherWindow: NSPanel {
    init(model: SwitchModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let host = NSHostingView(rootView: SwitchView().environmentObject(model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        // Re-asserted every present so the panel migrates across Spaces.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        }
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
