import SwiftUI

struct SwitchView: View {
    @EnvironmentObject var model: SwitchModel
    @ObservedObject private var prefs = SwitchPreferences.shared
    @Namespace private var selectionNS
    @State private var hoveredID: CGWindowID?
    @State private var openMouseLocation: CGPoint = .zero
    @State private var hasMouseMovedSinceOpen = false
    @State private var lastSelectionFromMouse = false

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
            hintStrip
        }
        .background(
            VisualEffectBackdrop(material: .hudWindow, blendingMode: .behindWindow)
        )
        .frame(width: prefs.verticalList ? 520 : 880, height: 560)
        .scaleEffect(model.visible ? 1.0 : 0.97)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.18, dampingFraction: 0.86), value: model.visible)
        .onChange(of: model.visible) { _, isVisible in
            if isVisible {
                openMouseLocation = NSEvent.mouseLocation
                hasMouseMovedSinceOpen = false
                lastSelectionFromMouse = false
                hoveredID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.filterText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.filterText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Spacer()
            if !model.filteredWindows.isEmpty {
                Text("\(model.filteredWindows.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 26)
    }

    private var grid: some View {
        ZStack {
            let list = model.filteredWindows
            if list.isEmpty {
                Text(model.filterText.isEmpty ? "No windows" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        if prefs.verticalList {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { idx, w in
                                    listRow(window: w, index: idx)
                                        .id(w.id)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { idx, w in
                                    tile(window: w, index: idx, list: list)
                                        .id(w.id)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 0)
                            .padding(.bottom, 12)
                        }
                    }
                    .onChange(of: model.selected) { _, new in
                        // Skip auto-scroll when selection came from mouse hover —
                        // user is already looking at where they're pointing.
                        if lastSelectionFromMouse {
                            lastSelectionFromMouse = false
                            return
                        }
                        let cur = model.filteredWindows
                        guard cur.indices.contains(new) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(cur[new].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hintStrip: some View {
        HStack(spacing: 14) {
            hint("↵", "switch")
            if prefs.verticalList {
                hint("↑↓", "navigate")
            } else {
                hint("←↑↓→", "navigate")
                hint("1-9", "pick")
            }
            hint("⌘Q", "quit")
            hint("⌘H", "hide")
            hint("type", "filter")
            hint("esc", "cancel")
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
    }

    private func stoplights(for window: WindowInfo) -> some View {
        HStack(spacing: 4) {
            stoplight(color: Color(red: 1.0, green: 0.36, blue: 0.34), symbol: "xmark") {
                model.close(window)
            }
            stoplight(color: Color(red: 1.0, green: 0.74, blue: 0.20), symbol: "minus") {
                WindowMinimizer.minimize(window)
            }
            stoplight(color: Color(red: 0.30, green: 0.78, blue: 0.34), symbol: "plus") {
                WindowZoomer.zoom(window)
            }
        }
        .opacity(prefs.disableMouse ? 0 : 1)
        .allowsHitTesting(!prefs.disableMouse)
    }

    private func stoplight(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    }

    private func tile(window: WindowInfo, index: Int, list: [WindowInfo]) -> some View {
        let selected = index == model.selected
        let hovered = hoveredID == window.id
        let icon = appIcon(for: window.pid)

        return VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    Color.black.opacity(0.22)
                    if let img = model.thumbnails[window.id] {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .opacity(0.55)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    stoplights(for: window).padding(7)
                }
                .animation(.easeOut(duration: 0.18), value: model.thumbnails[window.id] != nil)

                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                        .padding(7)
                }

                if window.isMinimized || window.isCrossSpace {
                    HStack(spacing: 0) {
                        Spacer()
                        VStack {
                            Spacer()
                            Text(window.isMinimized ? "MINIMIZED" : (window.spaceLabel?.uppercased() ?? "OTHER SPACE"))
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(7)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text(window.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !window.title.isEmpty {
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(window.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
        }
        .padding(9)
        .background(
            ZStack {
                if hovered && !selected {
                    Color.white.opacity(0.06)
                }
                if selected {
                    SwitchPreferences.shared.accent.color.opacity(0.22)
                        .matchedGeometryEffect(id: "selectionBG", in: selectionNS)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SwitchPreferences.shared.accent.color.opacity(0.7), lineWidth: 1)
                        .matchedGeometryEffect(id: "selectionRing", in: selectionNS)
                }
            }
        )
        .shadow(color: .black.opacity(selected ? 0.22 : 0), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: model.selected)
        .animation(.easeOut(duration: 0.10), value: hoveredID)
        .contentShape(Rectangle())
        .onHover { isHovering in
            guard !SwitchPreferences.shared.disableMouse else { return }
            if isHovering {
                // Ignore hover until cursor has actually moved 10pt+ since panel opened.
                // Otherwise a static cursor parked over a tile hijacks the default selection.
                if !hasMouseMovedSinceOpen {
                    let loc = NSEvent.mouseLocation
                    let dx = loc.x - openMouseLocation.x
                    let dy = loc.y - openMouseLocation.y
                    if hypot(dx, dy) < 10 { return }
                    hasMouseMovedSinceOpen = true
                }
                hoveredID = window.id
                if model.selected != index {
                    lastSelectionFromMouse = true
                    model.selected = index
                }
            } else if hoveredID == window.id {
                hoveredID = nil
            }
        }
        .onTapGesture {
            guard !SwitchPreferences.shared.disableMouse else { return }
            lastSelectionFromMouse = true
            model.selected = index
            model.commitAndDismiss?()
        }
    }

    private func listRow(window: WindowInfo, index: Int) -> some View {
        let selected = index == model.selected
        let hovered = hoveredID == window.id
        let icon = appIcon(for: window.pid)
        let accent = prefs.accent.color

        return HStack(spacing: 11) {
            ZStack {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(window.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !window.title.isEmpty {
                    Text(window.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            stoplights(for: window)
                .opacity(hovered ? 1 : 0.45)
            if window.isMinimized || window.isCrossSpace {
                Text(window.isMinimized ? "MINIMIZED" : (window.spaceLabel?.uppercased() ?? "OTHER SPACE"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            Group {
                if let img = model.thumbnails[window.id] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 50)
                } else {
                    Color.black.opacity(0.22)
                        .frame(width: 88, height: 50)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                if hovered && !selected {
                    Color.white.opacity(0.06)
                }
                if selected {
                    accent.opacity(0.22)
                        .matchedGeometryEffect(id: "selectionBG", in: selectionNS)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.7), lineWidth: 1)
                        .matchedGeometryEffect(id: "selectionRing", in: selectionNS)
                }
            }
        )
        .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 8, x: 0, y: 3)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: model.selected)
        .animation(.easeOut(duration: 0.10), value: hoveredID)
        .contentShape(Rectangle())
        .onHover { isHovering in
            guard !prefs.disableMouse else { return }
            if isHovering {
                if !hasMouseMovedSinceOpen {
                    let loc = NSEvent.mouseLocation
                    let dx = loc.x - openMouseLocation.x
                    let dy = loc.y - openMouseLocation.y
                    if hypot(dx, dy) < 10 { return }
                    hasMouseMovedSinceOpen = true
                }
                hoveredID = window.id
                if model.selected != index {
                    lastSelectionFromMouse = true
                    model.selected = index
                }
            } else if hoveredID == window.id {
                hoveredID = nil
            }
        }
        .onTapGesture {
            guard !prefs.disableMouse else { return }
            lastSelectionFromMouse = true
            model.selected = index
            model.commitAndDismiss?()
        }
    }

    private func appIcon(for pid: pid_t) -> NSImage? {
        if let cached = Self.iconCache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        Self.iconCache[pid] = icon
        return icon
    }

    private static var iconCache: [pid_t: NSImage] = [:]
}
