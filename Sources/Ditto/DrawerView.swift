import SwiftUI

struct DrawerView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var model: DrawerModel
    @ObservedObject var previews: LinkPreviews
    @Namespace private var toolbarSpace
    @FocusState private var fieldFocused: Bool

    private var results: [ClipItem] { model.results(from: store.items) }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            cards
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The drawer is the floating control layer, so it's glass; cards are content, so they're solid.
        // The glass sits behind the content rather than wrapping it, so card text isn't drawn as glass text.
        .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 28)) }
        .onChange(of: model.searchFocused) { _, focused in fieldFocused = focused }
        .onChange(of: fieldFocused) { _, focused in model.searchFocused = focused }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ZStack {
            HStack(spacing: 8) {
                if model.searching {
                    searchField
                    tabIcon
                } else {
                    searchButton
                    clipboardTab
                }
            }
            .animation(.smooth(duration: 0.32), value: model.searching)

            HStack {
                Spacer()
                Menu {
                    Button("Clear History") { model.clearHistory() }
                    Divider()
                    Button("Quit Ditto") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
            .padding(.trailing, 18)
        }
        .frame(height: 34)
    }

    // The search button and the search field share one capsule background that stretches between
    // them, and the Clipboard tab shrinks to its icon, so search opens in place instead of swapping views.

    private var searchButton: some View {
        Button { model.beginSearch() } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 32)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Capsule().fill(.clear).matchedGeometryEffect(id: "search", in: toolbarSpace))
        .help("Search (⌘F, or just start typing)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(width: 380, height: 32)
        .background(Capsule().fill(.quaternary).matchedGeometryEffect(id: "search", in: toolbarSpace))
        .overlay(Capsule().strokeBorder(fieldFocused ? Color.accentColor : .clear, lineWidth: 2.5).padding(-1.5))
        .onTapGesture { model.searchFocused = true }
    }

    private var clipboardTab: some View {
        Label("Clipboard", systemImage: "clock.arrow.circlepath")
            .font(.system(size: 13.5, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(.quaternary).matchedGeometryEffect(id: "tab", in: toolbarSpace))
    }

    private var tabIcon: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 32, height: 32)
            .foregroundStyle(.secondary)
            .background(Capsule().fill(.clear).matchedGeometryEffect(id: "tab", in: toolbarSpace))
            .help("Clipboard history")
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item,
                                 quickNumber: !model.searching && index < 9 ? index + 1 : nil,
                                 selected: index == model.selection,
                                 muted: model.searchFocused,
                                 store: store,
                                 previews: previews)
                            .id(item.id)
                            .onTapGesture(count: 2) { model.paste(item, false) }
                            .onTapGesture {
                                model.selection = index
                                model.searchFocused = false
                            }
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .onChange(of: model.selection) { _, selection in
                guard results.indices.contains(selection) else { return }
                withAnimation(.smooth(duration: 0.22)) { proxy.scrollTo(results[selection].id) }
            }
            .overlay {
                if results.isEmpty { emptyState }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
            Text(model.searching ? "No matches" : "Copy something and it shows up here")
                .font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("Paste to \(model.targetAppName ?? "Front App")") { model.paste(item, false) }
        if [.text, .code, .link].contains(item.kind) {
            Button("Paste as Plain Text") { model.paste(item, true) }
        }
        Button("Copy") { model.copy(item) }
        if item.kind == .link, let link = item.text, let url = URL(string: link) {
            Divider()
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if item.kind == .file, !item.fileURLs.isEmpty {
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }
}
