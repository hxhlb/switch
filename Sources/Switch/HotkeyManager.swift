import AppKit
import ApplicationServices
import CoreGraphics

final class HotkeyManager {
    enum Mode { case allWindows, currentApp }
    enum Direction { case left, right, up, down }

    var onArm: ((Mode) -> Void)?
    var onAdvance: ((Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCloseSelected: (() -> Void)?
    var onHideSelected: (() -> Void)?
    var onNavigate: ((Direction) -> Void)?
    var onPickIndex: ((Int) -> Void)?
    var onFilterAppend: ((Character) -> Void)?
    var onFilterBackspace: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var armed: Mode?

    private static let kcEscape: CGKeyCode = 53
    private static let kcDelete: CGKeyCode = 51
    private static let kcLeftArrow: CGKeyCode = 123
    private static let kcRightArrow: CGKeyCode = 124
    private static let kcDownArrow: CGKeyCode = 125
    private static let kcUpArrow: CGKeyCode = 126
    private static let kcW: CGKeyCode = 13
    private static let kcH: CGKeyCode = 4
    /// US-keyboard digit keycodes for 1-9 in order. `0` is intentionally absent
    /// because it's not a useful tenth pick and breaks naturally as filter input.
    private static let kcDigits: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    func start() {
        if !ensureAccessibility() { return }
        installTap()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        let cb: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return mgr.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: cb,
            userInfo: info
        ) else {
            NSLog("Switch: failed to create event tap")
            return
        }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = src
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        let opt = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown {
            let allBinding = HotkeyConfig.shared.allWindows
            let appBinding = HotkeyConfig.shared.currentApp

            if allBinding.matchesTrigger(keyCode: kc, flags: flags) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if armed == nil { armed = .allWindows; onArm?(.allWindows) }
                    else { onAdvance?(shift) }
                }
                return nil
            }
            if appBinding.matchesTrigger(keyCode: kc, flags: flags) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if armed == nil { armed = .currentApp; onArm?(.currentApp) }
                    else { onAdvance?(shift) }
                }
                return nil
            }

            if armed != nil {
                if kc == Self.kcEscape {
                    DispatchQueue.main.async { [weak self] in
                        self?.armed = nil
                        self?.onCancel?()
                    }
                    return nil
                }
                if kc == Self.kcDelete {
                    DispatchQueue.main.async { [weak self] in
                        self?.onFilterBackspace?()
                    }
                    return nil
                }
                // Cmd-W closes the selected window (replaces the right-arrow
                // shortcut from v0.1.5; right-arrow is now navigation).
                if cmd && kc == Self.kcW {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCloseSelected?()
                    }
                    return nil
                }
                // Cmd-H hides the selected window's app (system Hide gesture).
                if cmd && kc == Self.kcH {
                    DispatchQueue.main.async { [weak self] in
                        self?.onHideSelected?()
                    }
                    return nil
                }
                if let direction = arrowDirection(for: kc) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onNavigate?(direction)
                    }
                    return nil
                }
                // Digit 1-9 picks the Nth visible tile directly. Digits no
                // longer participate in filter input as a result.
                if let index = digitIndex(for: kc) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPickIndex?(index)
                    }
                    return nil
                }
                if let c = filterChar(from: event) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onFilterAppend?(c)
                    }
                    return nil
                }
            }
        }

        if type == .flagsChanged {
            if armed == .allWindows && !HotkeyConfig.shared.allWindows.modifiersHeld(flags) {
                DispatchQueue.main.async { [weak self] in
                    self?.armed = nil
                    self?.onCommit?()
                }
            } else if armed == .currentApp && !HotkeyConfig.shared.currentApp.modifiersHeld(flags) {
                DispatchQueue.main.async { [weak self] in
                    self?.armed = nil
                    self?.onCommit?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Reinstall the tap so the new HotkeyConfig is picked up. Called when bindings change.
    func reload() {
        guard tap != nil else { return }
        stop()
        installTap()
    }

    private func filterChar(from event: CGEvent) -> Character? {
        guard let ns = NSEvent(cgEvent: event),
              let chars = ns.charactersIgnoringModifiers,
              let c = chars.first else { return nil }
        // Digits are intercepted above as direct-pick shortcuts; not filter input.
        if c.isLetter || c == " " || c == "-" || c == "." {
            return Character(c.lowercased())
        }
        return nil
    }

    private func arrowDirection(for kc: CGKeyCode) -> Direction? {
        switch kc {
        case Self.kcLeftArrow:  return .left
        case Self.kcRightArrow: return .right
        case Self.kcUpArrow:    return .up
        case Self.kcDownArrow:  return .down
        default:                return nil
        }
    }

    private func digitIndex(for kc: CGKeyCode) -> Int? {
        Self.kcDigits.firstIndex(of: kc)
    }
}
