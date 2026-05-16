import AppKit
import SwiftUI
import Combine

@MainActor
final class SwitchPreferences: ObservableObject {
    static let shared = SwitchPreferences()

    enum AccentChoice: String, CaseIterable, Identifiable {
        case system, rose, blue, mint, peach, lavender, monochrome
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .rose: return "Rose"
            case .blue: return "Blue"
            case .mint: return "Mint"
            case .peach: return "Peach"
            case .lavender: return "Lavender"
            case .monochrome: return "Mono"
            }
        }
        var color: Color {
            switch self {
            case .system: return Color.accentColor
            case .rose: return Color(red: 0.741, green: 0.514, blue: 0.467)
            case .blue: return Color(red: 0.40, green: 0.62, blue: 0.92)
            case .mint: return Color(red: 0.42, green: 0.80, blue: 0.69)
            case .peach: return Color(red: 0.98, green: 0.69, blue: 0.49)
            case .lavender: return Color(red: 0.66, green: 0.58, blue: 0.86)
            case .monochrome: return Color(white: 0.86)
            }
        }
    }

    @Published var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: accentKey) }
    }

    @Published var showCrossSpace: Bool {
        didSet { UserDefaults.standard.set(showCrossSpace, forKey: crossSpaceKey) }
    }

    @Published var stickyMode: Bool {
        didSet { UserDefaults.standard.set(stickyMode, forKey: SwitchPreferences.stickyModeKey) }
    }

    @Published var disableMouse: Bool {
        didSet { UserDefaults.standard.set(disableMouse, forKey: disableMouseKey) }
    }

    @Published var verticalList: Bool {
        didSet { UserDefaults.standard.set(verticalList, forKey: SwitchPreferences.verticalListKey) }
    }

    @Published var blacklist: Set<String> {
        didSet { UserDefaults.standard.set(Array(blacklist), forKey: SwitchPreferences.blacklistKey) }
    }

    @Published var mruMixSpaces: Bool {
        didSet { UserDefaults.standard.set(mruMixSpaces, forKey: mruMixSpacesKey) }
    }

    @Published var staticOrder: Bool {
        didSet { UserDefaults.standard.set(staticOrder, forKey: SwitchPreferences.staticOrderKey) }
    }

    @Published var appOrder: [String] {
        didSet { UserDefaults.standard.set(appOrder, forKey: SwitchPreferences.appOrderKey) }
    }

    @Published var includeWindowlessApps: Bool {
        didSet { UserDefaults.standard.set(includeWindowlessApps, forKey: SwitchPreferences.includeWindowlessKey) }
    }

    private let accentKey = "switch.accent"
    private let crossSpaceKey = "switch.showCrossSpace"
    nonisolated static let stickyModeKey = "switch.stickyMode"
    private let disableMouseKey = "switch.disableMouse"
    nonisolated static let verticalListKey = "switch.verticalList"
    nonisolated static let blacklistKey = "switch.blacklist"
    private let mruMixSpacesKey = "switch.mruMixSpaces"
    nonisolated static let staticOrderKey = "switch.staticOrder"
    nonisolated static let appOrderKey = "switch.appOrder"
    nonisolated static let includeWindowlessKey = "switch.includeWindowlessApps"

    private init() {
        accent = AccentChoice(rawValue: UserDefaults.standard.string(forKey: accentKey) ?? "") ?? .system
        showCrossSpace = (UserDefaults.standard.object(forKey: crossSpaceKey) as? Bool) ?? true
        stickyMode = UserDefaults.standard.bool(forKey: SwitchPreferences.stickyModeKey)
        disableMouse = UserDefaults.standard.bool(forKey: "switch.disableMouse")
        verticalList = UserDefaults.standard.bool(forKey: SwitchPreferences.verticalListKey)
        blacklist = Set(UserDefaults.standard.stringArray(forKey: SwitchPreferences.blacklistKey) ?? [])
        mruMixSpaces = (UserDefaults.standard.object(forKey: "switch.mruMixSpaces") as? Bool) ?? true
        staticOrder = UserDefaults.standard.bool(forKey: SwitchPreferences.staticOrderKey)
        appOrder = UserDefaults.standard.stringArray(forKey: SwitchPreferences.appOrderKey) ?? []
        includeWindowlessApps = UserDefaults.standard.bool(forKey: SwitchPreferences.includeWindowlessKey)
    }
}
