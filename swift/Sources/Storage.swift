import Foundation
import SQLite3
import CryptoKit
import AppKit

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Clip: Identifiable, Hashable {
    enum Kind: String {
        case text
        case image
        case pdf
    }
    let id: Int64
    let kind: Kind
    let content: String?
    let imagePath: String?
    let byteSize: Int64
    let createdAt: String

    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class Storage {
    static let shared = Storage()

    private var db: OpaquePointer?
    private let dbPath: URL
    private let imagesDir: URL

    private let retentionDays = 14
    private let textCap: Int64 = 30 * 1024 * 1024
    private let blobsCap: Int64 = 300 * 1024 * 1024  // images + pdfs combined
    let perImageLimit: Int64 = 10 * 1024 * 1024
    let perPDFLimit: Int64 = 25 * 1024 * 1024

    private let queue = DispatchQueue(label: "paster.storage")

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".paster")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("history.db")
        imagesDir = dir.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func initialize() throws {
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed"])
        }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS clips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """, nil, nil, nil)

        // Schema migration — ignore "duplicate column" errors silently
        for sql in [
            "ALTER TABLE clips ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'",
            "ALTER TABLE clips ADD COLUMN image_path TEXT",
            "ALTER TABLE clips ADD COLUMN hash TEXT",
            "ALTER TABLE clips ADD COLUMN byte_size INTEGER NOT NULL DEFAULT 0",
        ] {
            sqlite3_exec(db, sql, nil, nil, nil)
        }

        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_clips_created ON clips(created_at DESC)", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(hash)", nil, nil, nil)
        prune()
    }

    // MARK: - Add text

    func add(_ text: String) {
        guard !text.isEmpty else { return }
        guard let token = Crypto.shared.encrypt(text) else { return }
        queue.sync {
            self.dedupeRecentText(matching: text)
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO clips (kind, content, byte_size) VALUES ('text', ?, ?)", -1, &stmt, nil) == SQLITE_OK {
                _ = token.withCString { cstr in
                    sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int64(stmt, 2, Int64(text.utf8.count))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            self.pruneInternal()
        }
    }

    // MARK: - Add image

    @discardableResult
    func addImage(_ pngData: Data, name: String? = nil) -> Bool {
        addBlob(kind: .image, data: pngData, name: name, sizeLimit: perImageLimit)
    }

    @discardableResult
    func addPDF(_ pdfData: Data, name: String? = nil) -> Bool {
        addBlob(kind: .pdf, data: pdfData, name: name, sizeLimit: perPDFLimit)
    }

    @discardableResult
    private func addBlob(kind: Clip.Kind, data: Data, name: String?, sizeLimit: Int64) -> Bool {
        guard !data.isEmpty else { return false }
        guard Int64(data.count) <= sizeLimit else { return false }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        guard let encrypted = Crypto.shared.encryptData(data) else { return false }
        let filename = "\(hash).bin"
        let fileURL = imagesDir.appendingPathComponent(filename)
        do {
            try encrypted.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }

        let nameToken: String = {
            if let name, !name.isEmpty {
                return Crypto.shared.encrypt(name) ?? ""
            }
            return ""
        }()

        let kindRaw = kind.rawValue
        let dataSize = Int64(data.count)

        queue.sync {
            self.dedupeBlob(hash: hash)
            var stmt: OpaquePointer?
            let sql = "INSERT INTO clips (kind, content, image_path, hash, byte_size) VALUES (?, ?, ?, ?, ?)"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                _ = kindRaw.withCString { cstr in sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT) }
                _ = nameToken.withCString { cstr in sqlite3_bind_text(stmt, 2, cstr, -1, SQLITE_TRANSIENT) }
                _ = filename.withCString { cstr in sqlite3_bind_text(stmt, 3, cstr, -1, SQLITE_TRANSIENT) }
                _ = hash.withCString { cstr in sqlite3_bind_text(stmt, 4, cstr, -1, SQLITE_TRANSIENT) }
                sqlite3_bind_int64(stmt, 5, dataSize)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            self.pruneInternal()
        }
        return true
    }

    // MARK: - Reading

    func recent(limit: Int = 50) -> [Clip] {
        return queue.sync {
            var clips: [Clip] = []
            var stmt: OpaquePointer?
            let sql = "SELECT id, kind, content, image_path, byte_size, created_at FROM clips ORDER BY id DESC LIMIT ?"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let clip = self.readRow(stmt: stmt) { clips.append(clip) }
                }
            }
            sqlite3_finalize(stmt)
            return clips
        }
    }

    func search(_ query: String, limit: Int = 100) -> [Clip] {
        let q = query.lowercased()
        guard !q.isEmpty else { return recent(limit: limit) }
        return queue.sync {
            var clips: [Clip] = []
            var stmt: OpaquePointer?
            let sql = "SELECT id, kind, content, image_path, byte_size, created_at FROM clips WHERE kind='text' ORDER BY id DESC"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let clip = self.readRow(stmt: stmt) else { continue }
                    if let content = clip.content, content.lowercased().contains(q) {
                        clips.append(clip)
                        if clips.count >= limit { break }
                    }
                }
            }
            sqlite3_finalize(stmt)
            return clips
        }
    }

    func loadBlobData(for clip: Clip) -> Data? {
        guard clip.kind != .text, let path = clip.imagePath else { return nil }
        let fullPath = imagesDir.appendingPathComponent(path)
        guard let encrypted = try? Data(contentsOf: fullPath) else { return nil }
        return Crypto.shared.decryptData(encrypted)
    }

    func clear() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM clips", nil, nil, nil)
            if let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
                for f in files {
                    try? FileManager.default.removeItem(at: f)
                }
            }
        }
    }

    func prune() {
        queue.sync { self.pruneInternal() }
    }

    // MARK: - Internals

    private func readRow(stmt: OpaquePointer?) -> Clip? {
        let id = sqlite3_column_int64(stmt, 0)
        guard let kindCstr = sqlite3_column_text(stmt, 1) else { return nil }
        guard let kind = Clip.Kind(rawValue: String(cString: kindCstr)) else { return nil }
        let byteSize = sqlite3_column_int64(stmt, 4)
        let createdAt: String
        if let cd = sqlite3_column_text(stmt, 5) { createdAt = String(cString: cd) } else { createdAt = "" }

        switch kind {
        case .text:
            guard let cstr = sqlite3_column_text(stmt, 2) else { return nil }
            guard let plain = Crypto.shared.decrypt(String(cString: cstr)) else { return nil }
            return Clip(id: id, kind: .text, content: plain, imagePath: nil, byteSize: byteSize, createdAt: createdAt)
        case .image, .pdf:
            guard let pathCstr = sqlite3_column_text(stmt, 3) else { return nil }
            var name: String? = nil
            if let cstr = sqlite3_column_text(stmt, 2) {
                let token = String(cString: cstr)
                if !token.isEmpty {
                    name = Crypto.shared.decrypt(token)
                }
            }
            return Clip(id: id, kind: kind, content: name, imagePath: String(cString: pathCstr), byteSize: byteSize, createdAt: createdAt)
        }
    }

    private func dedupeRecentText(matching text: String) {
        var stmt: OpaquePointer?
        var idsToDelete: [Int64] = []
        if sqlite3_prepare_v2(db, "SELECT id, content FROM clips WHERE kind='text' ORDER BY id DESC LIMIT 200", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard let cstr = sqlite3_column_text(stmt, 1) else { continue }
                if Crypto.shared.decrypt(String(cString: cstr)) == text {
                    idsToDelete.append(id)
                }
            }
        }
        sqlite3_finalize(stmt)
        for id in idsToDelete {
            deleteRow(id: id, imagePath: nil)
        }
    }

    private func dedupeBlob(hash: String) {
        var stmt: OpaquePointer?
        var ids: [Int64] = []
        if sqlite3_prepare_v2(db, "SELECT id FROM clips WHERE kind IN ('image','pdf') AND hash=?", -1, &stmt, nil) == SQLITE_OK {
            _ = hash.withCString { cstr in sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        // Delete DB rows but keep the file (same hash → same content, will be re-referenced by new row)
        for id in ids {
            var del: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?", -1, &del, nil) == SQLITE_OK {
                sqlite3_bind_int64(del, 1, id)
                sqlite3_step(del)
            }
            sqlite3_finalize(del)
        }
    }

    private func deleteRow(id: Int64, imagePath: String?) {
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_int64(del, 1, id)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)

        if let path = imagePath {
            var stmt: OpaquePointer?
            var refs = 0
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clips WHERE kind IN ('image','pdf') AND image_path = ?", -1, &stmt, nil) == SQLITE_OK {
                _ = path.withCString { cstr in sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    refs = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
            if refs == 0 {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(path))
            }
        }
    }

    private func pruneInternal() {
        // 1. Age-based delete
        let ageSQL = "SELECT id, kind, image_path FROM clips WHERE created_at < datetime('now', '-\(retentionDays) days')"
        var stmt: OpaquePointer?
        var aged: [(Int64, String?)] = []
        if sqlite3_prepare_v2(db, ageSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "text"
                let path = (kind == "image" || kind == "pdf") ? sqlite3_column_text(stmt, 2).map { String(cString: $0) } : nil
                aged.append((id, path))
            }
        }
        sqlite3_finalize(stmt)
        for (id, path) in aged {
            deleteRow(id: id, imagePath: path)
        }

        // 2. Text size cap
        var totalText: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(LENGTH(content)), 0) FROM clips WHERE kind='text'", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { totalText = sqlite3_column_int64(stmt, 0) }
        }
        sqlite3_finalize(stmt)
        if totalText > textCap {
            var pairs: [(Int64, Int64)] = []
            if sqlite3_prepare_v2(db, "SELECT id, LENGTH(content) FROM clips WHERE kind='text' ORDER BY id ASC", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    pairs.append((sqlite3_column_int64(stmt, 0), sqlite3_column_int64(stmt, 1)))
                }
            }
            sqlite3_finalize(stmt)
            for (id, sz) in pairs {
                if totalText <= textCap { break }
                deleteRow(id: id, imagePath: nil)
                totalText -= sz
            }
        }

        // 3. Blobs (images + pdfs) size cap
        var totalBlobs: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(byte_size), 0) FROM clips WHERE kind IN ('image','pdf')", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { totalBlobs = sqlite3_column_int64(stmt, 0) }
        }
        sqlite3_finalize(stmt)
        if totalBlobs > blobsCap {
            var rows: [(Int64, Int64, String?)] = []
            if sqlite3_prepare_v2(db, "SELECT id, byte_size, image_path FROM clips WHERE kind IN ('image','pdf') ORDER BY id ASC", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let sz = sqlite3_column_int64(stmt, 1)
                    let path = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    rows.append((id, sz, path))
                }
            }
            sqlite3_finalize(stmt)
            for (id, sz, path) in rows {
                if totalBlobs <= blobsCap { break }
                deleteRow(id: id, imagePath: path)
                totalBlobs -= sz
            }
        }

        // 4. Cleanup orphaned blob files
        var referenced = Set<String>()
        if sqlite3_prepare_v2(db, "SELECT image_path FROM clips WHERE kind IN ('image','pdf') AND image_path IS NOT NULL", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    referenced.insert(String(cString: cstr))
                }
            }
        }
        sqlite3_finalize(stmt)
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
            for f in files where !referenced.contains(f.lastPathComponent) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}
