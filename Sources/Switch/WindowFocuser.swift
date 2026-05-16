import AppKit
import ApplicationServices

private func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    let err = _AXUIElementGetWindow(element, &id)
    return err == .success ? id : nil
}

enum WindowFocuser {
    static func focus(_ window: WindowInfo) {
        if window.isWindowless {
            let app = NSRunningApplication(processIdentifier: window.pid)
            if let url = app?.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            } else {
                app?.activate(options: [])
            }
            return
        }
        if window.isCrossSpace {
            let cid = CGSMainConnectionID()
            let currentSpace = CGSGetActiveSpace(cid)
            let ids = [NSNumber(value: window.id)] as CFArray
            CGSMoveWindowsToManagedSpace(cid, ids, currentSpace)
        }

        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true { app?.unhide() }

        let appAX = AXUIElementCreateApplication(window.pid)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &ref) == .success,
           let axWindows = ref as? [AXUIElement],
           let target = bestMatch(for: window, in: axWindows) ?? axWindows.first {
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }

        app?.activate(options: [])

        WindowMRU.touch(window.id)
    }

    /// Direct CGWindowID match via private SPI. Title and bounds matching
    /// both fail for Chrome (identical titles + shadow padding throws bounds
    /// off). This is the ID the OS itself uses, so it's exact.
    private static func bestMatch(for window: WindowInfo, in axWindows: [AXUIElement]) -> AXUIElement? {
        if let exact = axWindows.first(where: { axWindowID($0) == window.id }) {
            return exact
        }
        // Fallbacks if the SPI failed for some element (rare).
        var bestByBounds: (element: AXUIElement, distance: CGFloat)?
        for ax in axWindows {
            guard let frame = AXHelpers.frame(of: ax) else { continue }
            let d = abs(frame.origin.x - window.bounds.origin.x)
                  + abs(frame.origin.y - window.bounds.origin.y)
                  + abs(frame.size.width  - window.bounds.size.width)
                  + abs(frame.size.height - window.bounds.size.height)
            if bestByBounds == nil || d < bestByBounds!.distance {
                bestByBounds = (ax, d)
            }
        }
        if let bestByBounds, bestByBounds.distance < 40 { return bestByBounds.element }
        return axWindows.first(where: { AXHelpers.title(of: $0) == window.title })
    }
}

enum AppCloser {
    static func close(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
    }
}

enum WindowCloser {
    static func close(_ window: WindowInfo) { pressButton(window, attribute: kAXCloseButtonAttribute) }
}

enum WindowMinimizer {
    static func minimize(_ window: WindowInfo) { pressButton(window, attribute: kAXMinimizeButtonAttribute) }
}

enum WindowZoomer {
    static func zoom(_ window: WindowInfo) { pressButton(window, attribute: kAXZoomButtonAttribute) }
}

/// Press one of the stoplight buttons on the AX window matching `window`. Best-effort.
private func pressButton(_ window: WindowInfo, attribute: String) {
    let appAX = AXUIElementCreateApplication(window.pid)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &ref) == .success,
          let axWindows = ref as? [AXUIElement] else { return }
    let exact = axWindows.first(where: { axWindowID($0) == window.id })
    let target = exact
        ?? axWindows.first(where: { AXHelpers.title(of: $0) == window.title })
        ?? axWindows.first
    guard let target else { return }
    var btnRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(target, attribute as CFString, &btnRef) == .success,
          let btnObj = btnRef else { return }
    AXUIElementPerformAction(btnObj as! AXUIElement, kAXPressAction as CFString)
}

enum AXHelpers {
    static func title(of element: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        return ref as? String ?? ""
    }

    /// AX position + size as a CGRect, or nil if either attribute is missing.
    /// Used to disambiguate windows when titles collide (e.g. Chrome).
    static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        guard let posObj = posRef, let sizeObj = sizeRef else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posObj as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeObj as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
