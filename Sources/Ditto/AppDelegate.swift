import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private let previews = LinkPreviews()
    private lazy var watcher = ClipboardWatcher(store: store)
    private lazy var drawer = DrawerController(store: store, watcher: watcher, previews: previews)
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        // For checking both themes without changing the system setting: --appearance light|dark
        if let i = args.firstIndex(of: "--appearance"), args.indices.contains(i + 1) {
            NSApp.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
        }

        watcher.start()
        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in self?.drawer.toggle() }
        setUpStatusItem()

        if args.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.drawer.show() }
        }
        // For checking layout without Screen Recording permission: --snapshot <path.png>
        // (macOS adds the glass when compositing the screen, so the picture shows layout, not glass)
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.drawer.show() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.drawer.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Ditto")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Ditto", action: #selector(openDrawer), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ditto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func openDrawer() { drawer.show() }

    @objc private func clearHistory() { store.clearUnpinned() }
}
