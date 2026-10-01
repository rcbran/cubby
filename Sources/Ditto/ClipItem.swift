import Foundation

enum ClipKind: String {
    case text, code, link, image, file, color

    var title: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var kind: ClipKind
    /// Plain text for text, code, links and colors; newline-separated paths for files.
    var text: String?
    /// Rich text as copied, so a normal paste keeps formatting.
    var rtf: Data?
    /// File name inside the images folder.
    var imageFile: String?
    var sourceBundleID: String?
    var sourceName: String?
    var created: Date
    var pinned: Bool
    /// Identifies identical copies, so copying something again moves it to the front.
    var hash: String

    var fileURLs: [URL] {
        guard kind == .file, let text else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
}
