import AppKit
import Carbon.HIToolbox
import SwiftUI

/// State the drawer's views share with the controller.
@MainActor
final class DrawerModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var searching = false
    /// True while typing goes to the search field; the selected card's outline turns gray.
    @Published var searchFocused = false
    @Published var selection = 0
    @Published var targetAppName: String?

    var paste: (ClipItem, _ plain: Bool) -> Void = { _, _ in }
    var copy: (ClipItem) -> Void = { _ in }
    var delete: (ClipItem) -> Void = { _ in }
    var clearHistory: () -> Void = {}

    func results(from items: [ClipItem]) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard searching, !q.isEmpty else { return items }
        return items.filter { item in
            [item.text, item.sourceName, item.kind.title].contains {
                $0?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    func beginSearch(typing text: String = "") {
        searching = true
        query += text
        searchFocused = true
    }

    func endSearch() {
        searching = false
        searchFocused = false
        query = ""
    }
}

/// A floating panel that can take keyboard focus without activating Ditto,
/// so the app you were in stays in front and receives the paste.
final class DrawerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar  // above the Dock, which the drawer covers
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DrawerController: NSObject, NSWindowDelegate {
    static let height: CGFloat = 330
    static let inset: CGFloat = 8

    let model = DrawerModel()
    private let panel = DrawerPanel()
    private let store: HistoryStore
    private let watcher: ClipboardWatcher
    private var target: NSRunningApplication?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    init(store: HistoryStore, watcher: ClipboardWatcher, previews: LinkPreviews) {
        self.store = store
        self.watcher = watcher
        super.init()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: DrawerView(store: store, model: model, previews: previews))

        model.paste = { [weak self] item, plain in self?.paste(item, plain: plain) }
        model.copy = { [weak self] item in self?.copy(item) }
        model.delete = { [weak self] item in self?.store.delete(item) }
        model.clearHistory = { [weak self] in self?.store.clearUnpinned() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        target = NSWorkspace.shared.frontmostApplication
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier { target = nil }
        model.targetAppName = target?.localizedName
        model.endSearch()
        model.selection = 0

        // Open on the screen the pointer is on, full width, over the Dock.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let f = screen.frame
        let frame = NSRect(x: f.minX + Self.inset, y: f.minY + Self.inset,
                           width: f.width - Self.inset * 2, height: Self.height)

        panel.setFrame(frame.offsetBy(dx: 0, dy: -28), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)  // quick out, soft landing
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func hide(animated: Bool = true, then completion: (() -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animated ? 0.16 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: -20), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                completion?()
            }
        })
    }

    func snapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()  // another app or window took focus
    }

    // MARK: Actions

    private var results: [ClipItem] { model.results(from: store.items) }

    private var selected: ClipItem? {
        results.indices.contains(model.selection) ? results[model.selection] : nil
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        Paster.write(item, plain: plain, store: store)
        watcher.skipCurrentContents()
        store.touch(item)
        let target = self.target
        hide(animated: false) {
            guard let target else { return }
            guard Paster.canPaste else {
                Paster.requestPermission()  // the item is on the clipboard either way; ⌘V still works
                return
            }
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Paster.pressCommandV() }
        }
    }

    private func copy(_ item: ClipItem) {
        Paster.write(item, plain: false, store: store)
        watcher.skipCurrentContents()
        store.touch(item)
        hide()
    }

    // MARK: Keyboard and clicks

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
        // Clicks in other apps' windows close the drawer.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    /// Returns true when the key was handled here; false lets it reach the search field.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let chars = event.charactersIgnoringModifiers ?? ""
        let count = results.count

        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.searching { model.endSearch() } else { hide() }
            return true
        case kVK_LeftArrow:
            if model.searchFocused, !model.query.isEmpty, !command { return false }  // move the text cursor
            model.selection = max(model.selection - 1, 0)
            return true
        case kVK_RightArrow:
            if model.searchFocused, !model.query.isEmpty, !command { return false }
            model.selection = min(model.selection + 1, max(count - 1, 0))
            return true
        case kVK_DownArrow:
            if model.searchFocused { model.searchFocused = false; return true }
            return false
        case kVK_UpArrow:
            if model.searching, !model.searchFocused { model.searchFocused = true; moveCursorToEnd(); return true }
            return false
        case kVK_Tab:
            if model.searching { model.searchFocused.toggle() } else { model.beginSearch() }
            if model.searchFocused { moveCursorToEnd() }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let selected { paste(selected, plain: flags.contains(.shift)) }
            return true
        case kVK_Delete, kVK_ForwardDelete:
            if model.searchFocused { return false }
            if let selected { store.delete(selected); model.selection = min(model.selection, max(results.count - 1, 0)) }
            return true
        default:
            break
        }

        if command {
            if let n = Int(chars), (1...9).contains(n), !model.searching {
                if results.indices.contains(n - 1) { paste(results[n - 1], plain: flags.contains(.shift)) }
                return true
            }
            switch chars {
            case "f": model.beginSearch(); moveCursorToEnd(); return true
            case "c" where !model.searchFocused: if let selected { copy(selected) }; return true
            case "o" where selected?.kind == .link:
                if let link = selected?.text, let url = URL(string: link) { NSWorkspace.shared.open(url); hide() }
                return true
            default: return false
            }
        }

        // Typing anywhere starts a search, the way Spotlight does.
        if !model.searchFocused, let typed = event.characters, typed.count == 1,
           typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           flags.subtracting([.shift, .capsLock]).isEmpty {
            model.beginSearch(typing: typed)
            moveCursorToEnd()
            return true
        }
        return false
    }

    /// Focusing a text field selects its text, so the next keystroke would replace the first letter typed.
    private func moveCursorToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let editor = self?.panel.fieldEditor(false, for: nil) as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }
}
