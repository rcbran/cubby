import AppKit
import SQLite3

/// Clipboard history in a local SQLite database, with images as files beside it.
/// Everything lives in ~/Library/Application Support/Ditto and never leaves the Mac.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Unpinned items beyond this are dropped, oldest first.
    var limit = 500

    let folder: URL
    let imagesFolder: URL
    private var db: OpaquePointer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Ditto", isDirectory: true)
        imagesFolder = folder.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        guard sqlite3_open(folder.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK else {
            NSLog("Ditto: could not open history database")
            return
        }
        exec("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT,
                rtf BLOB,
                image TEXT,
                source_id TEXT,
                source_name TEXT,
                created REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                hash TEXT NOT NULL UNIQUE
            )
            """)
        load()
    }

    // MARK: Changes

    /// Adds a copy, or moves an identical earlier copy to the front.
    func add(kind: ClipKind, text: String?, rtf: Data?, imageFile: String?,
             sourceBundleID: String?, sourceName: String?, hash: String) {
        if let existing = items.first(where: { $0.hash == hash }) {
            // Keep the old row (and its image file) but treat it as new.
            if let imageFile, imageFile != existing.imageFile { removeImage(imageFile) }
            run("UPDATE items SET created = ?, source_id = ?, source_name = ? WHERE id = ?",
                [Date().timeIntervalSince1970, sourceBundleID, sourceName, existing.id])
        } else {
            run("""
                INSERT INTO items (kind, text, rtf, image, source_id, source_name, created, hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [kind.rawValue, text, rtf, imageFile, sourceBundleID, sourceName,
                 Date().timeIntervalSince1970, hash])
        }
        trim()
        load()
    }

    /// Moves an item to the front, as when it's pasted from the drawer.
    func touch(_ item: ClipItem) {
        run("UPDATE items SET created = ? WHERE id = ?", [Date().timeIntervalSince1970, item.id])
        load()
    }

    func delete(_ item: ClipItem) {
        if let file = item.imageFile { removeImage(file) }
        run("DELETE FROM items WHERE id = ?", [item.id])
        load()
    }

    func clearUnpinned() {
        for item in items where !item.pinned { if let f = item.imageFile { removeImage(f) } }
        run("DELETE FROM items WHERE pinned = 0", [])
        load()
    }

    func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesFolder.appendingPathComponent($0) }
    }

    // MARK: Internals

    private func trim() {
        let unpinned = items.filter { !$0.pinned }
        guard unpinned.count >= limit else { return }
        for item in unpinned.dropFirst(limit - 1) { delete(item) }
    }

    private func removeImage(_ file: String) {
        try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(file))
    }

    private func load() {
        var stmt: OpaquePointer?
        let sql = "SELECT id, kind, text, rtf, image, source_id, source_name, created, pinned, hash FROM items ORDER BY created DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var loaded: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            loaded.append(ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ClipKind(rawValue: string(stmt, 1) ?? "") ?? .text,
                text: string(stmt, 2),
                rtf: data(stmt, 3),
                imageFile: string(stmt, 4),
                sourceBundleID: string(stmt, 5),
                sourceName: string(stmt, 6),
                created: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                pinned: sqlite3_column_int(stmt, 8) != 0,
                hash: string(stmt, 9) ?? ""
            ))
        }
        items = loaded
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("Ditto SQL error: %@", String(cString: sqlite3_errmsg(db)))
        }
    }

    private func run(_ sql: String, _ args: [Any?]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Ditto SQL error: %@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let n = Int32(i + 1)
            switch arg {
            case let v as String: sqlite3_bind_text(stmt, n, v, -1, transient)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(v.count), transient) }
            case let v as Double: sqlite3_bind_double(stmt, n, v)
            case let v as Int64: sqlite3_bind_int64(stmt, n, v)
            case let v as Int: sqlite3_bind_int64(stmt, n, Int64(v))
            default: sqlite3_bind_null(stmt, n)
            }
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("Ditto SQL error: %@", String(cString: sqlite3_errmsg(db)))
        }
    }

    private func string(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }

    private func data(_ stmt: OpaquePointer?, _ col: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, col) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, col)))
    }
}

/// Tells SQLite to copy bound values, since Swift may free them right after binding.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
