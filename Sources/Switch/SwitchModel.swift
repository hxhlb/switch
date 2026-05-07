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
        // Trust the OS's z-order for active-Space windows — that already reflects focus history,
        // including focus changes made outside Switch. Only the cross-Space half needs MRU sorting,
        // since CGWindowList's order across Spaces is unreliable.
        let enumeration = WindowEnumerator.enumerate(scope: mode, frontmostPID: frontmostPID)
        let crossSorted = WindowMRU.sorted(enumeration.crossSpace, frontmost: nil)
        let ws = enumeration.activeSpace + crossSorted
        WindowMRU.purge(keeping: Set(ws.map { $0.id }))
        windows = ws
        selected = ws.count > 1 ? 1 : 0
        visible = true
        let liveIDs = Set(ws.map { $0.id })
        Task {
            if #available(macOS 14.0, *) {
                // Don't full-purge — pre-warmed thumbs are valid as long as the window still exists.
                await WindowSnapshotter.shared.purge(keeping: liveIDs)
            }
            await fetchThumbnails(for: ws, force: false)
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
        let target = list[selected]
        WindowCloser.close(target)
        // The actual close is async on the target app's side; remove optimistically and let
        // a short delay pass before re-enumerating so the AX cache catches up.
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

    /// Cols hardcoded to match SwitchView's 4-col grid.
    func navigate(direction: HotkeyManager.Direction) {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        let n = list.count
        let cols = 4
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
