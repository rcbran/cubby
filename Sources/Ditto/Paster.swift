import AppKit
import Carbon.HIToolbox

/// Puts an item back on the clipboard and, with the Accessibility permission, presses ⌘V in the front app.
@MainActor
enum Paster {
    static func write(_ item: ClipItem, plain: Bool, store: HistoryStore) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                pb.writeObjects([image])
            }
        case .file:
            pb.writeObjects(item.fileURLs as [NSURL])
        default:
            if !plain, let rtf = item.rtf { pb.setData(rtf, forType: .rtf) }
            pb.setString(item.text ?? "", forType: .string)
        }
    }

    /// Simulating a keystroke in another app needs the Accessibility permission.
    static var canPaste: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
