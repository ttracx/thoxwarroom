import Darwin
import Foundation
import WarRoomCore

/// Redacted failures from app-container ciphertext persistence.
public enum EncryptedWorkspaceFileStoreError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case applicationSupportUnavailable
    case unsafePath
    case symbolicLinkEncountered
    case encodedRecordTooLarge(limit: Int, actual: Int)
    case corruptRecord
    case inputOutputFailure

    public var description: String { "Encrypted workspace storage is unavailable." }
    public var debugDescription: String { "EncryptedWorkspaceFileStoreError(<redacted>)" }
}

protocol AtomicWorkspaceFileSystem: Sendable {
    func ensurePrivateDirectory(at url: URL) throws
    func directoryEntries(at url: URL) throws -> [URL]
    func readBoundedFile(at url: URL, maximumBytes: Int) throws -> Data?
    func writeAtomically(_ data: Data, to url: URL) throws
    func removeFileIfPresent(at url: URL) throws
    func removeDirectoryIfPresent(at url: URL) throws
}

/// App-container implementation of the Core encrypted-record persistence boundary.
public actor EncryptedWorkspaceFileDataStore: EncryptedWorkspaceDataStore {
    /// JSON/base64 envelope bound for a 16 MiB Core ciphertext record.
    public static let maximumEncodedRecordBytes = 24 * 1_024 * 1_024

    private static let recordSuffix = ".thoxenc"
    private let rootURL: URL
    private let fileSystem: any AtomicWorkspaceFileSystem
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store in the current app container's Application Support directory.
    public init() throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw EncryptedWorkspaceFileStoreError.applicationSupportUnavailable
        }
        let root = applicationSupport
            .appendingPathComponent("ai.thox.warroom", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
        let system = SystemAtomicWorkspaceFileSystem()
        try system.ensurePrivateDirectory(at: root)
        rootURL = root.standardizedFileURL
        fileSystem = system
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    init(rootURL: URL, fileSystem: any AtomicWorkspaceFileSystem) throws {
        let standardizedRoot = rootURL.standardizedFileURL
        try fileSystem.ensurePrivateDirectory(at: standardizedRoot)
        self.rootURL = standardizedRoot
        self.fileSystem = fileSystem
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    public func record(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws -> EncryptedWorkspaceRecord? {
        let candidates = try await records(
            in: workspaceID,
            collection: nil,
            limit: nil,
            matching: id
        )
        guard candidates.count <= 1 else {
            throw EncryptedWorkspaceFileStoreError.corruptRecord
        }
        return candidates.first
    }

    public func records(
        in workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        limit: WorkspaceDataPageLimit
    ) async throws -> [EncryptedWorkspaceRecord] {
        try await records(
            in: workspaceID,
            collection: collection,
            limit: limit.rawValue,
            matching: nil
        )
    }

    public func save(_ record: EncryptedWorkspaceRecord) async throws {
        try Task.checkCancellation()
        let directory = try collectionDirectory(
            workspaceID: record.workspaceID,
            collection: record.collection
        )
        try fileSystem.ensurePrivateDirectory(at: directory)
        let destination = try recordURL(
            id: record.id,
            workspaceID: record.workspaceID,
            collection: record.collection
        )
        let encoded: Data
        do {
            encoded = try encoder.encode(record)
        } catch {
            throw EncryptedWorkspaceFileStoreError.corruptRecord
        }
        guard encoded.count <= Self.maximumEncodedRecordBytes else {
            throw EncryptedWorkspaceFileStoreError.encodedRecordTooLarge(
                limit: Self.maximumEncodedRecordBytes,
                actual: encoded.count
            )
        }
        try Task.checkCancellation()
        do {
            try fileSystem.writeAtomically(encoded, to: destination)
        } catch let error as EncryptedWorkspaceFileStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }

    public func deleteRecord(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws {
        try Task.checkCancellation()
        // Record IDs are not globally unique across collections, so delete only exact
        // matches discovered beneath the explicitly scoped workspace directory.
        let workspace = try workspaceDirectory(workspaceID)
        guard let collections = try directoryEntriesIfPresent(at: workspace) else { return }
        for candidate in collections {
            try Task.checkCancellation()
            guard let collection = WorkspaceDataCollection(rawValue: candidate.lastPathComponent),
                  try isContained(candidate, by: workspace) else { continue }
            let target = try recordURL(id: id, workspaceID: workspaceID, collection: collection)
            do {
                try fileSystem.removeFileIfPresent(at: target)
            } catch let error as EncryptedWorkspaceFileStoreError {
                throw error
            } catch {
                throw EncryptedWorkspaceFileStoreError.inputOutputFailure
            }
        }
    }

    /// Returns canonical workspace IDs represented by private workspace directories.
    public func workspaceIDs() async throws -> [WorkspaceID] {
        try Task.checkCancellation()
        let entries: [URL]
        do {
            entries = try fileSystem.directoryEntries(at: rootURL)
        } catch let error as EncryptedWorkspaceFileStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        return try entries.compactMap { candidate in
            try Task.checkCancellation()
            let component = candidate.lastPathComponent
            guard component == component.lowercased(),
                  let uuid = UUID(uuidString: component),
                  try isContained(candidate, by: rootURL) else { return nil }
            return WorkspaceID(rawValue: uuid)
        }.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
    }

    /// Removes every ciphertext record for exactly one workspace.
    public func deleteWorkspace(id workspaceID: WorkspaceID) async throws {
        try Task.checkCancellation()
        do {
            try fileSystem.removeDirectoryIfPresent(at: workspaceDirectory(workspaceID))
        } catch let error as EncryptedWorkspaceFileStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }

    private func records(
        in workspaceID: WorkspaceID,
        collection requestedCollection: WorkspaceDataCollection?,
        limit: Int?,
        matching requestedID: EncryptedWorkspaceRecordID?
    ) async throws -> [EncryptedWorkspaceRecord] {
        try Task.checkCancellation()
        let workspace = try workspaceDirectory(workspaceID)
        guard let collectionURLs = try directoryEntriesIfPresent(at: workspace) else { return [] }
        var result: [EncryptedWorkspaceRecord] = []
        for collectionURL in collectionURLs {
            try Task.checkCancellation()
            guard let collection = WorkspaceDataCollection(rawValue: collectionURL.lastPathComponent),
                  requestedCollection == nil || requestedCollection == collection,
                  try isContained(collectionURL, by: workspace) else { continue }
            let entries: [URL]
            do {
                entries = try fileSystem.directoryEntries(at: collectionURL)
            } catch let error as EncryptedWorkspaceFileStoreError {
                throw error
            } catch {
                throw EncryptedWorkspaceFileStoreError.inputOutputFailure
            }
            for url in entries where url.pathExtension == String(Self.recordSuffix.dropFirst()) {
                try Task.checkCancellation()
                let identifierText = url.deletingPathExtension().lastPathComponent
                guard identifierText == identifierText.lowercased(),
                      let uuid = UUID(uuidString: identifierText),
                      requestedID == nil || requestedID?.rawValue == uuid else { continue }
                let data: Data?
                do {
                    data = try fileSystem.readBoundedFile(
                        at: url,
                        maximumBytes: Self.maximumEncodedRecordBytes
                    )
                } catch let error as EncryptedWorkspaceFileStoreError {
                    throw error
                } catch {
                    throw EncryptedWorkspaceFileStoreError.inputOutputFailure
                }
                guard let data else { continue }
                let record: EncryptedWorkspaceRecord
                do {
                    record = try decoder.decode(EncryptedWorkspaceRecord.self, from: data)
                } catch {
                    throw EncryptedWorkspaceFileStoreError.corruptRecord
                }
                guard record.workspaceID == workspaceID,
                      record.collection == collection,
                      record.id.rawValue == uuid else {
                    throw EncryptedWorkspaceFileStoreError.corruptRecord
                }
                result.append(record)
            }
        }
        let sorted = result.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            return $0.updatedAt < $1.updatedAt
        }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    private func workspaceDirectory(_ workspaceID: WorkspaceID) throws -> URL {
        let url = rootURL.appendingPathComponent(
            workspaceID.rawValue.uuidString.lowercased(),
            isDirectory: true
        )
        guard try isContained(url, by: rootURL) else {
            throw EncryptedWorkspaceFileStoreError.unsafePath
        }
        return url
    }

    private func directoryEntriesIfPresent(at url: URL) throws -> [URL]? {
        do {
            return try fileSystem.directoryEntries(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return nil
        } catch let error as EncryptedWorkspaceFileStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }

    private func collectionDirectory(
        workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection
    ) throws -> URL {
        let workspace = try workspaceDirectory(workspaceID)
        let url = workspace.appendingPathComponent(collection.rawValue, isDirectory: true)
        guard try isContained(url, by: workspace) else {
            throw EncryptedWorkspaceFileStoreError.unsafePath
        }
        return url
    }

    private func recordURL(
        id: EncryptedWorkspaceRecordID,
        workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection
    ) throws -> URL {
        let directory = try collectionDirectory(workspaceID: workspaceID, collection: collection)
        let filename = id.rawValue.uuidString.lowercased() + Self.recordSuffix
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        guard try isContained(url, by: directory) else {
            throw EncryptedWorkspaceFileStoreError.unsafePath
        }
        return url
    }

    private func isContained(_ candidate: URL, by directory: URL) throws -> Bool {
        let parent = directory.standardizedFileURL.path
        let child = candidate.standardizedFileURL.path
        return child.hasPrefix(parent + "/") && child != parent
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

struct SystemAtomicWorkspaceFileSystem: AtomicWorkspaceFileSystem, @unchecked Sendable {
    private let fileManager = FileManager.default

    func ensurePrivateDirectory(at url: URL) throws {
        let standardized = url.standardizedFileURL
        try fileManager.createDirectory(
            at: standardized,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard standardized.resolvingSymlinksInPath() == standardized else {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: standardized.path
        )
        try excludeFromBackup(standardized)
    }

    func directoryEntries(at url: URL) throws -> [URL] {
        let standardized = url.standardizedFileURL
        guard standardized.resolvingSymlinksInPath() == standardized else {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        return try fileManager.contentsOfDirectory(
            at: standardized,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    func readBoundedFile(at url: URL, maximumBytes: Int) throws -> Data? {
        guard maximumBytes > 0 && maximumBytes < Int.max else {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        let path = url.standardizedFileURL.path
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered }
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var result = Data()
        while result.count <= maximumBytes {
            let remaining = maximumBytes - result.count + 1
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
                  !chunk.isEmpty else { return result }
            result.append(chunk)
        }
        throw EncryptedWorkspaceFileStoreError.encodedRecordTooLarge(
            limit: maximumBytes,
            actual: result.count
        )
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let destination = url.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        guard directory.resolvingSymlinksInPath() == directory else {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).tmp"
        )
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var committed = false
        defer {
            try? handle.close()
            if !committed { try? fileManager.removeItem(at: temporary) }
        }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try fileManager.setAttributes(fileAttributes, ofItemAtPath: temporary.path)
            try excludeFromBackup(temporary)
            try handle.close()
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        committed = true
        try excludeFromBackup(destination)
        try synchronizeDirectory(directory)
    }

    func removeFileIfPresent(at url: URL) throws {
        let standardized = url.standardizedFileURL
        if (try? fileManager.destinationOfSymbolicLink(atPath: standardized.path)) != nil {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        let result = Darwin.unlink(standardized.path)
        guard result == 0 || errno == ENOENT else {
            if errno == EISDIR || errno == EPERM {
                throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
            }
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }

    func removeDirectoryIfPresent(at url: URL) throws {
        let standardized = url.standardizedFileURL
        if (try? fileManager.destinationOfSymbolicLink(atPath: standardized.path)) != nil {
            throw EncryptedWorkspaceFileStoreError.symbolicLinkEncountered
        }
        do {
            try fileManager.removeItem(at: standardized)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }

    private var fileAttributes: [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        return attributes
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw EncryptedWorkspaceFileStoreError.inputOutputFailure
        }
    }
}
