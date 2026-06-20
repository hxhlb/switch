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
    @Published var panelSize = CGSize(width: 880, height: 560)

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
        let scored: [(WindowInfo, Int)] = windows.compactMap { w in
            let a = Self.fuzzyScore(pattern: q, target: w.appName.lowercased())
            let t = Self.fuzzyScore(pattern: q, target: w.title.lowercased())
            guard let s = [a, t].compactMap({ $0 }).max() else { return nil }
            return (w, s)
        }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    private static func fuzzyScore(pattern: String, target: String) -> Int? {
        let pat = Array(pattern)
        let tgt = Array(target)
        var score = 0
        var patIdx = 0
        var lastMatch = -1
        for (i, c) in tgt.enumerated() {
            guard patIdx < pat.count else { break }
            if c == pat[patIdx] {
                score += 1
                if lastMatch == i - 1 { score += 5 }
                if i == 0 || !tgt[i - 1].isLetter { score += 3 }
                lastMatch = i
                patIdx += 1
            }
        }
        return patIdx == pat.count ? score : nil
    }

    func arm(_ mode: HotkeyManager.Mode) {
        self.mode = mode
        filterText = ""
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if mode == .spaces {
            let final = WindowEnumerator.spaceRepresentatives(frontmostPID: frontmostPID)
            windows = final
            if let current = final.firstIndex(where: { !$0.isCrossSpace }), final.count > 1 {
                selected = (current + 1) % final.count
            } else {
                selected = 0
            }
            visible = true
            let liveIDs = Set(final.map { $0.id })
            Task {
                if SwitchPreferences.shared.showThumbnails, #available(macOS 14.0, *) {
                    await WindowSnapshotter.shared.purge(keeping: liveIDs)
                }
                await fetchThumbnails(for: final, force: false)
            }
            startRefreshTimer()
            if !hasArmedOnce {
                hasArmedOnce = true
                startPrewarmTimer()
            }
            return
        }
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
            let switchablePIDs = WindowEnumerator.windowOwningPIDs(scope: mode, frontmostPID: frontmostPID)
            let ownBundle = Bundle.main.bundleIdentifier
            let extras = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !switchablePIDs.contains($0.processIdentifier) && $0.bundleIdentifier != ownBundle }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                .map { app in
                    WindowInfo(
                        id: CGWindowID(0xF0000000) | CGWindowID(UInt32(bitPattern: Int32(app.processIdentifier))),
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "",
                        title: "",
                        bounds: .zero,
                        isWindowless: true,
                        bundleID: app.bundleIdentifier
                    )
                }
            final += extras
        }
        let pinned = SwitchPreferences.shared.pinnedBundleIDs
        if !pinned.isEmpty {
            final.sort { (a, b) in
                let aP = a.bundleID.map { pinned.contains($0) } ?? false
                let bP = b.bundleID.map { pinned.contains($0) } ?? false
                return aP && !bP
            }
        }
        WindowMRU.purge(keeping: Set(final.map { $0.id }))
        windows = final
        selected = SwitchPreferences.shared.stickyMode ? 0 : (final.count > 1 ? 1 : 0)
        visible = true
        let liveIDs = Set(final.filter { !$0.isWindowless }.map { $0.id })
        let thumbTargets = final.filter { !$0.isWindowless }
        let capturePIDs = Set(thumbTargets.map { $0.pid })
        Task.detached(priority: .utility) {
            AXWindowCache.capture(pids: capturePIDs)
        }
        Task {
            if SwitchPreferences.shared.showThumbnails, #available(macOS 14.0, *) {
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
        guard mode != .spaces else { return }
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
                guard SwitchPreferences.shared.showThumbnails else { return }
                let ws = self.windows
                guard !ws.isEmpty, self.visible else { return }
                await self.fetchThumbnails(for: ws, force: self.mode != .spaces)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

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
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ws = WindowEnumerator.currentWindows(scope: .allWindows, frontmostPID: frontmost)
        let liveIDs = Set(ws.map { $0.id })
        // Keep AX elements for every visible window on hand: once a window goes
        // fullscreen on its own Space, Chromium apps stop enumerating it via AX
        // and this cached element is the only way to focus it.
        let capturePIDs = Set(ws.map { $0.pid })
        Task.detached(priority: .utility) {
            AXWindowCache.purgeDead()
            AXWindowCache.capture(pids: capturePIDs)
        }
        guard SwitchPreferences.shared.showThumbnails, #available(macOS 14.0, *) else { return }
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

    func selectIndex(_ index: Int) {
        let list = filteredWindows
        guard list.indices.contains(index) else { return }
        selected = index
    }

    func closeSelectedApp() {
        guard mode != .spaces else { return }
        let list = filteredWindows
        guard list.indices.contains(selected) else { return }
        AppCloser.close(list[selected])
        cancelAndDismiss?()
    }

    func hideSelected() {
        guard mode != .spaces else { return }
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
        guard SwitchPreferences.shared.showThumbnails else {
            thumbnails = [:]
            return
        }
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
