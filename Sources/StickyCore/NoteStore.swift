import Foundation

/// Everything StickyTop persists: live notes plus recently deleted ones.
public struct NotesDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let trashLimit = 30

    public var version: Int
    public var notes: [Note]
    /// Recently deleted notes, most recent first.
    public var trash: [Note]

    public init(notes: [Note] = [], trash: [Note] = []) {
        self.version = Self.currentVersion
        self.notes = notes
        self.trash = trash
    }

    private enum CodingKeys: String, CodingKey { case version, notes, trash }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        trash = try c.decodeIfPresent([Note].self, forKey: .trash) ?? []
    }

    /// Removes the note from the live list and puts it at the front of the trash.
    public mutating func moveToTrash(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        trash.removeAll { $0.id == note.id }
        trash.insert(note, at: 0)
        if trash.count > Self.trashLimit {
            trash.removeLast(trash.count - Self.trashLimit)
        }
    }

    /// Removes a note from the trash and returns it, or nil if it isn't there.
    public mutating func takeFromTrash(id: UUID) -> Note? {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return nil }
        return trash.remove(at: index)
    }
}

/// Reads and writes `notes.json` atomically, keeping a one-generation backup and
/// never silently discarding a file it can't parse.
public final class NoteStore {
    public enum LoadStatus: Equatable, Sendable {
        /// No data on disk — first launch.
        case fresh
        case loaded
        /// Main file missing or unreadable; the backup was used instead.
        case recoveredFromBackup
        /// Main file unreadable and no usable backup. It was moved aside, not deleted.
        case corrupt
    }

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("notes.json") }
    public var backupURL: URL { directory.appendingPathComponent("notes.backup.json") }

    private let fileManager = FileManager.default
    private var hasBackedUpThisSession = false

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("StickyTop", isDirectory: true)
    }

    public init(directory: URL = NoteStore.defaultDirectory) {
        self.directory = directory
    }

    public func load() -> (document: NotesDocument, status: LoadStatus) {
        if fileManager.fileExists(atPath: fileURL.path) {
            if let document = decode(fileURL) { return (document, .loaded) }
            quarantineCorruptFile()
            if let document = decode(backupURL) { return (document, .recoveredFromBackup) }
            return (NotesDocument(), .corrupt)
        }
        if let document = decode(backupURL) { return (document, .recoveredFromBackup) }
        return (NotesDocument(), .fresh)
    }

    public func save(_ document: NotesDocument) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Snapshot the previous session's file once, before the first overwrite.
        if !hasBackedUpThisSession {
            hasBackedUpThisSession = true
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: fileURL, to: backupURL)
            }
        }
        let data = try Self.encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private func decode(_ url: URL) -> NotesDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(NotesDocument.self, from: data)
    }

    private func quarantineCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = directory.appendingPathComponent("notes.corrupt-\(stamp).json")
        try? fileManager.moveItem(at: fileURL, to: destination)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
