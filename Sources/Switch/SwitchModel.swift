import AppKit
import SwiftUI

@MainActor
final class SwitchModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected: Int = 0
    @Published var mode: HotkeyManager.Mode = .allWindows
    @Published var visible: Bool = false
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var filterText: String = ""

    /// Set by AppDelegate so the view can request a commit + window dismiss from a mouse click.
    var commitAndDismiss: (() -> Void)?
    /// Set by AppDelegate so the model can request a dismiss when no windows remain after a close.
    var cancelAndDismiss: (() -> Void)?

    private var refreshTimer: Timer?
    private var prewarmTimer: Timer?
    private var hasArmedOnce = false

    var filteredWindows: [WindowInfo] {
        let q = filterText.lowercased()
        if q.isEmpty { return windows }
        return windows.filter {
            $0.appName.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
    }

    func arm(_ mode: HotkeyManager.Mode) {
        self.mode = mode
        filterText = ""
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // FocusTracker keeps WindowMRU current across all focus events (Switch-driven
        // and external clicks). MRU-sort active-Space too so that when an Arc window
        // is raised, all OTHER Arc windows don't cluster ahead of the previously-focused
        // window from a different app. CGWindowList z-order groups windows by app
        // when any one is raised, which is the wrong signal for a window switcher.
        let enumeration = WindowEnumerator.enumerate(scope: mode, frontmostPID: frontmostPID)
        let activeFront = enumeration.activeSpace.first
        let ws: [WindowInfo]
        if SwitchPreferences.shared.staticOrder {
            let order = SwitchPreferences.shared.appOrder
            let rank: (String) -> Int = { order.firstIndex(of: $0) ?? Int.max }
            let stable: (WindowInfo, WindowInfo) -> Bool = {
                let ra = rank($0.appName), rb = rank($1.appName)
                if ra != rb { return ra < rb }
                if $0.appName.lowercased() != $1.appName.lowercased() {
                    return $0.appName.lowercased() < $1.appName.lowercased()
                }
                return $0.id < $1.id
            }
            ws = enumeration.activeSpace.sorted(by: stable) + enumeration.crossSpace.sorted(by: stable)
        } else if SwitchPreferences.shared.mruMixSpaces {
            let merged = enumeration.activeSpace + enumeration.crossSpace
            ws = WindowMRU.sorted(merged, frontmost: activeFront)
        } else {
            let activeSorted = WindowMRU.sorted(enumeration.activeSpace, frontmost: activeFront)
            let crossSorted = WindowMRU.sorted(enumeration.crossSpace, frontmost: nil)
            ws = activeSorted + crossSorted
        }
        var final = ws
        if SwitchPreferences.shared.includeWindowlessApps && mode == .allWindows {
            let livePIDs = Set(final.map { $0.pid })
            let ownBundle = Bundle.main.bundleIdentifier
            let extras = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !livePIDs.contains($0.processIdentifier) && $0.bundleIdentifier != ownBundle }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                .map { app in
                    WindowInfo(
                        id: CGWindowID(0xF0000000) | CGWindowID(UInt32(bitPattern: Int32(app.processIdentifier))),
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "",
                        title: "",
                        bounds: .zero,
                        isWindowless: true
                    )
                }
            final += extras
        }
        WindowMRU.purge(keeping: Set(final.map { $0.id }))
        windows = final
        selected = final.count > 1 ? 1 : 0
        visible = true
        let liveIDs = Set(final.filter { !$0.isWindowless }.map { $0.id })
        let thumbTargets = final.filter { !$0.isWindowless }
        Task {
            if #available(macOS 14.0, *) {
                // Don't full-purge — pre-warmed thumbs are valid as long as the window still exists.
                await WindowSnapshotter.shared.purge(keeping: liveIDs)
            }
            await fetchThumbnails(for: thumbTargets, force: false)
        }
        startRefreshTimer()
        if !hasArmedOnce {
            hasArmedOnce = true
            startPrewarmTimer()
        }
    }

    func closeSelected() {
        let list = filteredWindows
        guard list.indices.contains(selected) else { return }
        close(list[selected])
    }

    func close(_ target: WindowInfo) {
        WindowCloser.close(target)
        windows.removeAll { $0.id == target.id }
        thumbnails[target.id] = nil
        let remaining = filteredWindows
        if remaining.isEmpty {
            cancelAndDismiss?()
            return
        }
        if selected >= remaining.count {
            selected = remaining.count - 1
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ws = self.windows
                guard !ws.isEmpty, self.visible else { return }
                await self.fetchThumbnails(for: ws, force: true)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Background snapshot pre-warm. Runs every 3s while the panel is hidden, populating
    /// the WindowSnapshotter cache so the next ⌘-Tab opens with thumbs already drawn.
    private func startPrewarmTimer() {
        prewarmTimer?.invalidate()
        prewarmTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.visible { return } // arm-driven refresh handles the visible case
                await self.prewarmCache()
            }
        }
    }

    private func prewarmCache() async {
        guard #available(macOS 14.0, *) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ws = WindowEnumerator.currentWindows(scope: .allWindows, frontmostPID: frontmost)
        let liveIDs = Set(ws.map { $0.id })
        await WindowSnapshotter.shared.purge(keeping: liveIDs)
        await withTaskGroup(of: Void.self) { group in
            for w in ws {
                group.addTask {
                    _ = await WindowSnapshotter.shared.snapshot(for: w.id, force: false)
                }
            }
        }
    }

    func advance(reverse: Bool) {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        let n = list.count
        selected = reverse ? (selected - 1 + n) % n : (selected + 1) % n
    }

    func navigate(direction: HotkeyManager.Direction) {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        let n = list.count
        let cols = SwitchPreferences.shared.verticalList ? 1 : 4
        let delta: Int
        switch direction {
        case .left:  delta = -1
        case .right: delta = 1
        case .up:    delta = -cols
        case .down:  delta = cols
        }
        selected = ((selected + delta) % n + n) % n
    }

    func pickIndex(_ index: Int) {
        let list = filteredWindows
        guard list.indices.contains(index) else { return }
        selected = index
        commitAndDismiss?()
    }

    func closeSelectedApp() {
        let list = filteredWindows
        guard list.indices.contains(selected) else { return }
        AppCloser.close(list[selected])
        cancelAndDismiss?()
    }

    func hideSelected() {
        let list = filteredWindows
        guard list.indices.contains(selected) else { return }
        let target = list[selected]
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            app.hide()
        }
        cancelAndDismiss?()
    }

    func appendFilter(_ char: Character) {
        filterText.append(char)
        selected = 0
    }

    func backspaceFilter() {
        guard !filterText.isEmpty else { return }
        filterText.removeLast()
        selected = 0
    }

    func commit() {
        let list = filteredWindows
        if list.indices.contains(selected) {
            WindowFocuser.focus(list[selected])
        }
        teardown()
    }

    func cancel() {
        teardown()
    }

    private func teardown() {
        visible = false
        windows = []
        thumbnails = [:]
        filterText = ""
        stopRefreshTimer()
    }

    private func fetchThumbnails(for windows: [WindowInfo], force: Bool) async {
        if #available(macOS 14.0, *) {
            await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                for w in windows {
                    group.addTask {
                        let img = await WindowSnapshotter.shared.snapshot(for: w.id, force: force)
                        return (w.id, img)
                    }
                }
                for await (id, img) in group {
                    if let img { thumbnails[id] = img }
                }
            }
        }
    }
}
