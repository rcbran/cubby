import SwiftUI

struct CardView: View {
    static let size: CGFloat = 230

    let item: ClipItem
    /// The ⌘1–9 number, hidden while searching since results reorder as you type.
    let quickNumber: Int?
    let selected: Bool
    /// Gray outline instead of the accent color while typing goes to the search field.
    let muted: Bool
    let store: HistoryStore
    @ObservedObject var previews: LinkPreviews

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: Self.size, height: Self.size)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(muted ? Color.secondary.opacity(0.7) : Color.accentColor, lineWidth: 4)
                    .padding(-5)
            }
        }
        .contentShape(.rect(cornerRadius: 14))
        .onAppear { if item.kind == .link, let link = item.text { previews.load(link) } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.title)
                    .font(.system(size: 14, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(of: item.created, now: context.date))
                        .font(.system(size: 11))
                        .opacity(0.85)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if let icon = AppInfo.icon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .help(item.sourceName ?? "")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(height: 50)
        .foregroundStyle(.white)
        .background(Color(nsColor: AppInfo.color(for: item.sourceBundleID)))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            textBody(font: .system(size: 12.5))
        case .code:
            textBody(font: .system(size: 11.5, design: .monospaced))
        case .link:
            linkBody
        case .image:
            imageBody
        case .color:
            colorBody
        case .file:
            fileBody
        }
    }

    private func textBody(font: Font) -> some View {
        Text(String((item.text ?? "").prefix(700)))
            .font(font)
            .lineSpacing(2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            // Fade the last lines out instead of cutting text off mid-line.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var linkBody: some View {
        if let image = previews.previews[item.text ?? ""]?.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                LinearGradient(colors: [Color(nsColor: AppInfo.color(for: item.sourceBundleID)).opacity(0.35),
                                        Color(nsColor: AppInfo.color(for: item.sourceBundleID)).opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "link")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var imageBody: some View {
        if let url = store.imageURL(for: item), let image = Thumbnails.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 4))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.5))
        } else {
            Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var colorBody: some View {
        let color = Self.parseColor(item.text ?? "")
        return ZStack(alignment: .bottomLeading) {
            Rectangle().fill(color.map { Color(nsColor: $0) } ?? Color.secondary.opacity(0.2))
            Text(item.text ?? "")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.map { $0.brightnessComponent > 0.6 && $0.saturationComponent < 0.6 } == true
                                 ? Color.black.opacity(0.75) : Color.white)
                .padding(12)
        }
    }

    private var fileBody: some View {
        let urls = item.fileURLs
        return VStack(spacing: 8) {
            if let first = urls.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) and \(urls.count - 1) more")
                    .font(.system(size: 12.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if item.kind == .link {
                VStack(alignment: .leading, spacing: 1) {
                    Text(previews.previews[item.text ?? ""]?.title ?? host)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(info)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let quickNumber {
                Text("⌘\(quickNumber)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(.quaternary, in: .capsule)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: item.kind == .link ? 44 : 28)
    }

    private var host: String {
        guard let link = item.text, let url = URL(string: link), let host = url.host() else { return item.text ?? "" }
        let path = url.path()
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + (path == "/" ? "" : path)
    }

    private var info: String {
        switch item.kind {
        case .text, .code:
            let n = item.text?.count ?? 0
            return "\(n.formatted()) character\(n == 1 ? "" : "s")"
        case .image:
            guard let url = store.imageURL(for: item), let size = Thumbnails.pixelSize(at: url) else { return "Image" }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .file:
            let urls = item.fileURLs
            if urls.count == 1, let bytes = try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            }
            return "\(urls.count) files"
        case .color:
            return "Color"
        case .link:
            return host
        }
    }

    // MARK: Helpers

    static func age(of date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 45 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func parseColor(_ s: String) -> NSColor? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
