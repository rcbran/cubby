import AppKit
import LinkPresentation

/// Titles and preview images for copied links, fetched with Apple's LinkPresentation (the same
/// previews Messages shows). Fetching contacts the linked site; nothing else leaves the Mac.
@MainActor
final class LinkPreviews: ObservableObject {
    struct Preview {
        var title: String?
        var image: NSImage?
    }

    @Published private(set) var previews: [String: Preview] = [:]
    private var started: Set<String> = []

    func load(_ link: String) {
        guard !started.contains(link), let url = URL(string: link) else { return }
        started.insert(link)
        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { metadata, _ in
            let title = metadata?.title
            let imageProvider = metadata?.imageProvider ?? metadata?.iconProvider
            Task { @MainActor in
                self.previews[link] = Preview(title: title)
            }
            imageProvider?.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in
                    self.previews[link, default: Preview(title: title)].image = image
                }
            }
        }
    }
}
