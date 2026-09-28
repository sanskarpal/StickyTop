import Foundation
import Testing
@testable import StickyCore

@Suite struct NoteStoreTests {
    let directory: URL
    let store: NoteStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyTopTests-\(UUID().uuidString)", isDirectory: true)
        store = NoteStore(directory: directory)
    }

    private func sampleNote(_ text: String = "Buy milk") -> Note {
        Note(
            richText: Data([1, 2, 3]),
            plainText: text,
            frame: CGRect(x: 100, y: 200, width: 260, height: 220),
            color: .pink,
            opacity: 0.7,
            isCollapsed: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
    }

    @Test func freshWhenNothingOnDisk() {
        let (document, status) = store.load()
        #expect(status == .fresh)
        #expect(document.notes.isEmpty)
    }

    @Test func roundTripsEveryField() throws {
        let document = NotesDocument(notes: [sampleNote()], trash: [sampleNote("old")])
        try store.save(document)
        let (loaded, status) = store.load()
        #expect(status == .loaded)
        #expect(loaded == document)
    }

    @Test func createsDirectoryOnSave() throws {
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try store.save(NotesDocument())
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func backsUpPreviousSessionOnFirstSave() throws {
        try store.save(NotesDocument(notes: [sampleNote("session 1")]))

        let nextSession = NoteStore(directory: directory)
        try nextSession.save(NotesDocument(notes: [sampleNote("session 2, edit 1")]))
        try nextSession.save(NotesDocument(notes: [sampleNote("session 2, edit 2")]))

        let backup = try NoteStore.decoder.decode(NotesDocument.self, from: Data(contentsOf: nextSession.backupURL))
        #expect(backup.notes.first?.plainText == "session 1")
    }

    @Test func corruptFileIsQuarantinedAndBackupUsed() throws {
        try store.save(NotesDocument(notes: [sampleNote("good")]))
        let nextSession = NoteStore(directory: directory)
        try nextSession.save(NotesDocument(notes: [sampleNote("newer")])) // backup now holds "good"
        try Data("{ not json".utf8).write(to: store.fileURL)

        let (document, status) = NoteStore(directory: directory).load()
        #expect(status == .recoveredFromBackup)
        #expect(document.notes.first?.plainText == "good")

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("notes.corrupt-") })
        #expect(!files.contains("notes.json"))
    }

    @Test func corruptFileWithoutBackupReportsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.fileURL)
        let (document, status) = store.load()
        #expect(status == .corrupt)
        #expect(document.notes.isEmpty)
        // The unreadable file is kept, never deleted.
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("notes.corrupt-") })
    }

    @Test func trashIsMostRecentFirstAndCapped() {
        var document = NotesDocument()
        let notes = (0..<(NotesDocument.trashLimit + 5)).map { Note(plainText: "note \($0)") }
        document.notes = notes
        for note in notes { document.moveToTrash(note) }

        #expect(document.notes.isEmpty)
        #expect(document.trash.count == NotesDocument.trashLimit)
        #expect(document.trash.first?.plainText == "note \(notes.count - 1)")
    }

    @Test func restoreTakesNoteOutOfTrash() {
        var document = NotesDocument()
        let note = Note(plainText: "keep me")
        document.moveToTrash(note)
        #expect(document.takeFromTrash(id: note.id)?.plainText == "keep me")
        #expect(document.trash.isEmpty)
        #expect(document.takeFromTrash(id: note.id) == nil)
    }

    @Test func documentDecodesWithMissingKeys() throws {
        let document = try NoteStore.decoder.decode(NotesDocument.self, from: Data("{}".utf8))
        #expect(document.version == NotesDocument.currentVersion)
        #expect(document.notes.isEmpty && document.trash.isEmpty)
    }
}
