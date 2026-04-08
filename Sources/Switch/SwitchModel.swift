import Foundation
import Combine

final class SwitchModel: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published var selected: Int = 0
    @Published var filter: String = "" {
        didSet { applyFilter() }
    }

    private var allWindows: [WindowInfo] = []

    func refresh() {
        allWindows = WindowEnumerator.list()
        applyFilter()
    }

    private func applyFilter() {
        if filter.isEmpty {
            windows = allWindows
        } else {
            let q = filter.lowercased()
            windows = allWindows.filter {
                $0.title.lowercased().contains(q) || $0.ownerName.lowercased().contains(q)
            }
        }
        if selected >= windows.count { selected = 0 }
    }

    func advance() {
        guard !windows.isEmpty else { return }
        selected = (selected + 1) % windows.count
    }

    func back() {
        guard !windows.isEmpty else { return }
        selected = (selected - 1 + windows.count) % windows.count
    }

    func type(_ char: Character) {
        filter.append(char)
    }

    func backspace() {
        if !filter.isEmpty { filter.removeLast() }
    }
}
