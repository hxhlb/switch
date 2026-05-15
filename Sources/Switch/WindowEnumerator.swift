import AppKit
import ApplicationServices
import CoreGraphics

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect
    var isCrossSpace: Bool = false
    var isMinimized: Bool = false
    var spaceLabel: String?
}

enum WindowEnumerator {
    private static let skipApps: Set<String> = [
        "Window Server", "Dock", "SystemUIServer", "Control Center",
        "Notification Center", "Spotlight", "WallpaperAgent", "Switch",
        "loginwindow", "talagent", "TextInputMenuAgent", "TextInputSwitcher",
        "universalControl", "ControlStrip", "ScreenshotCapture"
    ]

    private static let helperSuffixes: [String] = [
        "Helper", " Helper", " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)",
        "Agent", " Agent",
        "Service", " Service", " View Service",
        "Renderer", "(Renderer)",
        "WebContent", "Networking",
        "Extension"
    ]

    private static func isHelperProcess(_ name: String) -> Bool {
        for s in helperSuffixes where name.hasSuffix(s) { return true }
        return false
    }

    struct Enumeration {
        let activeSpace: [WindowInfo]
        let crossSpace: [WindowInfo]
    }

    static func currentWindows(scope: HotkeyManager.Mode, frontmostPID: pid_t?) -> [WindowInfo] {
        let e = enumerate(scope: scope, frontmostPID: frontmostPID)
        return e.activeSpace + e.crossSpace
    }

    static func enumerate(scope: HotkeyManager.Mode, frontmostPID: pid_t?) -> Enumeration {
        let activeSpace = enumerate(option: [.optionOnScreenOnly, .excludeDesktopElements], scope: scope, frontmostPID: frontmostPID)

        // UserDefaults read direct — SwitchPreferences is @MainActor and this
        // static func runs from prewarm background queues.
        let showCross = (UserDefaults.standard.object(forKey: "switch.showCrossSpace") as? Bool) ?? true
        guard showCross else {
            return Enumeration(activeSpace: activeSpace, crossSpace: [])
        }

        let everything = enumerate(option: [.optionAll, .excludeDesktopElements], scope: scope, frontmostPID: frontmostPID)
        let activeIDs = Set(activeSpace.map { $0.id })
        let crossSpace = everything
            .filter { !activeIDs.contains($0.id) }
            .map { var w = $0; w.isCrossSpace = true; return w }
        let annotated = annotateAndPrune(crossSpace)
        return Enumeration(activeSpace: activeSpace, crossSpace: annotated)
    }

    private static func annotateAndPrune(_ candidates: [WindowInfo]) -> [WindowInfo] {
        var minimizedIDs: Set<CGWindowID> = []
        for pid in Set(candidates.map { $0.pid }) {
            let appAX = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &ref) == .success,
                  let axWindows = ref as? [AXUIElement] else { continue }
            for ax in axWindows {
                var id: CGWindowID = 0
                if _AXUIElementGetWindow(ax, &id) == .success, id != 0 {
                    var minRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(ax, kAXMinimizedAttribute as CFString, &minRef) == .success,
                       let isMin = minRef as? Bool, isMin {
                        minimizedIDs.insert(id)
                    }
                }
            }
        }
        let cid = CGSMainConnectionID()
        let labels = spaceLabels(cid: cid)
        return candidates.compactMap { w in
            let arr = [NSNumber(value: w.id)] as CFArray
            let spaces = CGSCopySpacesForWindows(cid, 7, arr)?.takeRetainedValue() as? [Int] ?? []
            if spaces.isEmpty { return nil }
            var out = w
            if minimizedIDs.contains(w.id) {
                out.isMinimized = true
                out.isCrossSpace = false
            } else if let sid = spaces.first {
                out.spaceLabel = labels[sid]
            }
            return out
        }
    }

    /// Builds a `spaceID → "Desktop N" / "Fullscreen"` map by walking CGS's managed-display spaces in order.
    private static func spaceLabels(cid: CGSConnectionID) -> [Int: String] {
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        var out: [Int: String] = [:]
        var desktop = 0
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let id = space["id64"] as? Int else { continue }
                let type = space["type"] as? Int ?? 0
                if type == 0 {
                    desktop += 1
                    out[id] = "Desktop \(desktop)"
                } else {
                    out[id] = "Fullscreen"
                }
            }
        }
        return out
    }

    private static func enumerate(option: CGWindowListOption, scope: HotkeyManager.Mode, frontmostPID: pid_t?) -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let blacklist = Set(UserDefaults.standard.stringArray(forKey: SwitchPreferences.blacklistKey) ?? [])
        var blockedPIDs: Set<pid_t> = []
        if !blacklist.isEmpty {
            for app in NSWorkspace.shared.runningApplications {
                if let bid = app.bundleIdentifier, blacklist.contains(bid) {
                    blockedPIDs.insert(app.processIdentifier)
                }
            }
        }
        var out: [WindowInfo] = []
        var seenIDs: Set<CGWindowID> = []
        for d in raw {
            let appName = d[kCGWindowOwnerName as String] as? String ?? ""
            guard let layer = d[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let alpha = d[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
            guard let id = d[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if skipApps.contains(appName) { continue }
            if isHelperProcess(appName) { continue }
            if blockedPIDs.contains(pid) { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            if app == nil || app?.activationPolicy == .prohibited { continue }
            let title = d[kCGWindowName as String] as? String ?? ""
            let boundsDict = d[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            if bounds.width < 100 || bounds.height < 80 { continue }
            if title.isEmpty && (bounds.width < 400 || bounds.height < 300) { continue }
            // Dedupe by CGWindowID only — it's already unique per window.
            // The earlier (pid, title, bounds) dedupe was collapsing multiple
            // Chrome windows that shared the same active-tab title.
            if seenIDs.contains(id) { continue }
            seenIDs.insert(id)
            if scope == .currentApp, let f = frontmostPID, pid != f { continue }
            out.append(WindowInfo(id: id, pid: pid, appName: appName, title: title, bounds: bounds))
        }
        return out
    }
}
