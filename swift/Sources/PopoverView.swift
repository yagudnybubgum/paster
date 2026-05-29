import SwiftUI
import AppKit
import PDFKit

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum ListItem: Identifiable {
    case clip(Clip)
    case hotkeyHint(Int)

    var id: String {
        switch self {
        case .clip(let c): return "clip-\(c.id)"
        case .hotkeyHint(let i): return "hint-\(i)"
        }
    }
}

struct PopoverView: View {
    @State private var query: String = ""
    @State private var clips: [Clip] = []
    @State private var loginAtStart: Bool = LoginItem.isEnabled
    @FocusState private var searchFocused: Bool
    @AppStorage("hotkey_hint_dismissed") private var hintDismissCount: Int = 0
    @State private var dismissedThisSession: Set<Int> = []

    @AppStorage("hotkey.keyCode") private var hotkeyKeyCode: Int = 9 // V
    @AppStorage("hotkey.modifiers") private var hotkeyModifiers: Int = Int(
        NSEvent.ModifierFlags([.command, .shift]).rawValue
    )
    @AppStorage("hotkey.character") private var hotkeyCharacter: String = "V"
    @State private var recordingHotkey: Bool = false

    let onDismiss: () -> Void

    private var items: [ListItem] {
        let showHints = query.isEmpty && hintDismissCount < 6
        guard showHints else { return clips.map { .clip($0) } }
        var out: [ListItem] = []
        for (i, clip) in clips.enumerated() {
            if i > 0 && i % 12 == 0 && !dismissedThisSession.contains(i) {
                out.append(.hotkeyHint(i))
            }
            out.append(.clip(clip))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 390, height: 480)
        .background(VisualEffect())
        .onAppear {
            dismissedThisSession.removeAll()
            recordingHotkey = false
            reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDidChange)) { _ in
            reload()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search clipboard", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 13))
                .onChange(of: query) { _ in reload() }
                .onSubmit {
                    if let first = clips.first { paste(first) }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if clips.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(query.isEmpty ? "Nothing copied yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                if query.isEmpty {
                    Text("Copy text or an image to get started")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    Text("Press ⌘⇧V from anywhere to open")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                        .padding(.top, 2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        switch item {
                        case .clip(let clip):
                            ClipRow(clip: clip) { paste(clip) }
                        case .hotkeyHint(let position):
                            HotkeyHintRow {
                                dismissedThisSession.insert(position)
                                hintDismissCount += 1
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if recordingHotkey {
                recordingFooter
            } else {
                normalFooter
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onChange(of: recordingHotkey) { _ in
            if recordingHotkey {
                HotkeyRecorder.shared.start(
                    onCapture: { kc, mods, char in
                        hotkeyKeyCode = kc
                        hotkeyModifiers = Int(mods.rawValue)
                        hotkeyCharacter = char
                        recordingHotkey = false
                        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                    },
                    onCancel: { recordingHotkey = false }
                )
            } else {
                HotkeyRecorder.shared.stop()
            }
        }
    }

    private var normalFooter: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { loginAtStart },
                set: { newValue in
                    do {
                        if newValue { try LoginItem.enable() } else { try LoginItem.disable() }
                        loginAtStart = LoginItem.isEnabled
                    } catch {
                        NSLog("Paster: login item toggle failed: \(error)")
                    }
                }
            )) {
                Text("Launch at login")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            Spacer()

            hotkeyBadge

            Button("Clear") {
                Storage.shared.clear()
                reload()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
    }

    private var hotkeyBadge: some View {
        Button {
            recordingHotkey = true
        } label: {
            HStack(spacing: 4) {
                Text(hotkeyDisplay)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change shortcut")
    }

    private var recordingFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Press shortcut…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Esc to cancel")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var hotkeyDisplay: String {
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option)  { out += "⌥" }
        if mods.contains(.shift)   { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        out += hotkeyCharacter.uppercased()
        return out
    }

    private func reload() {
        clips = query.isEmpty
            ? Storage.shared.recent(limit: 50)
            : Storage.shared.search(query, limit: 100)
    }

    private func paste(_ clip: Clip) {
        switch clip.kind {
        case .text:
            if let content = clip.content {
                ClipboardMonitor.write(content)
                Storage.shared.add(content)
            }
        case .image:
            if let data = Storage.shared.loadBlobData(for: clip) {
                ClipboardMonitor.writeImage(data)
                Storage.shared.addImage(data, name: clip.content)
            }
        case .pdf:
            if let data = Storage.shared.loadBlobData(for: clip) {
                ClipboardMonitor.writePDF(data)
                Storage.shared.addPDF(data, name: clip.content)
            }
        }
        reload()
        onDismiss()
    }
}

struct ClipRow: View {
    let clip: Clip
    let onSelect: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                if clip.kind == .image || clip.kind == .pdf {
                    imageThumb
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("\(kindLabel) · \(formatBytes(clip.byteSize)) · \(timeAgo)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preview)
                            .lineLimit(2)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(timeAgo)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .task(id: clip.id) {
            guard clip.kind != .text, thumbnail == nil else { return }
            let img = await Self.loadThumbnail(clip: clip)
            await MainActor.run { thumbnail = img }
        }
    }

    private var imageThumb: some View {
        Group {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 52, height: 38)
                    .overlay(
                        Image(systemName: clip.kind == .pdf ? "doc.text" : "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    private var kindLabel: String {
        switch clip.kind {
        case .image: return String(localized: "Image")
        case .pdf:   return String(localized: "PDF")
        case .text:  return ""
        }
    }

    private var displayName: String {
        if let name = clip.content, !name.isEmpty {
            return name
        }
        return kindLabel
    }

    private static func loadThumbnail(clip: Clip) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = Storage.shared.loadBlobData(for: clip) else { return nil as NSImage? }
            switch clip.kind {
            case .image:
                return NSImage(data: data)
            case .pdf:
                guard let pdf = PDFDocument(data: data),
                      let page = pdf.page(at: 0) else { return nil }
                return page.thumbnail(of: CGSize(width: 200, height: 150), for: .mediaBox)
            case .text:
                return nil
            }
        }.value
    }

    private static let sqlFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f
    }()

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var preview: String {
        let raw = clip.content ?? ""
        let flat = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(160))
    }

    private var timeAgo: String {
        guard let date = Self.sqlFormatter.date(from: clip.createdAt) else {
            return clip.createdAt
        }
        return Self.relative.localizedString(for: date, relativeTo: Date())
    }

    private func formatBytes(_ size: Int64) -> String {
        Self.bytes.string(fromByteCount: size)
    }
}

struct HotkeyHintRow: View {
    let onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 52, height: 38)
                .overlay(
                    Image(systemName: "command")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Press ⌘⇧V from anywhere")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Open Paster instantly")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(hovering ? 0.10 : 0.06))
        )
        .onHover { hovering = $0 }
    }
}
