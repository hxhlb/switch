import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onCmdTab: (_ shift: Bool) -> Void = { _ in }
    var onCmdRelease: () -> Void = {}

    func install() {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue))

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: opaque
        ) else {
            print("[hotkey] tap create failed — Accessibility not granted?")
            return
        }
        self.tap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let cmd = event.flags.contains(.maskCommand)
            let shift = event.flags.contains(.maskShift)
            // 48 = Tab, 50 = grave
            if cmd && (keyCode == 48 || keyCode == 50) {
                DispatchQueue.main.async { self.onCmdTab(shift) }
                return nil
            }
        }
        if type == .flagsChanged {
            // Cmd release — commit current selection.
            if !event.flags.contains(.maskCommand) {
                DispatchQueue.main.async { self.onCmdRelease() }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
