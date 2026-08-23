import Darwin
import Foundation

public struct WorkspaceBrowserLimits: Equatable, Sendable {
    public let maximumEntriesPerDirectory: Int
    public let maximumPreviewBytes: Int
    public let maximumPathDepth: Int

    public init(
        maximumEntriesPerDirectory: Int = 500,
        maximumPreviewBytes: Int = 256 * 1_024,
        maximumPathDepth: Int = 32
    ) throws {
        guard (1...5_000).contains(maximumEntriesPerDirectory),
              (1...2 * 1_024 * 1_024).contains(maximumPreviewBytes),
              (1...128).contains(maximumPathDepth) else {
            throw WorkspaceBrowserError.invalidLimits
        }
        self.maximumEntriesPerDirectory = maximumEntriesPerDirectory
        self.maximumPreviewBytes = maximumPreviewBytes
        self.maximumPathDepth = maximumPathDepth
    }

    public static let secureDefault = WorkspaceBrowserLimits(
        validatedMaximumEntriesPerDirectory: 500,
        maximumPreviewBytes: 256 * 1_024,
        maximumPathDepth: 32
    )

    private init(
        validatedMaximumEntriesPerDirectory: Int,
        maximumPreviewBytes: Int,
        maximumPathDepth: Int
    ) {
        self.maximumEntriesPerDirectory = validatedMaximumEntriesPerDirectory
        self.maximumPreviewBytes = maximumPreviewBytes
        self.maximumPathDepth = maximumPathDepth
    }
}

public enum WorkspaceBrowserEntryKind: Equatable, Sendable {
    case directory
    case file
    case symbolicLinkBlocked
    case unsupported
}

public struct WorkspaceBrowserEntry: Equatable, Sendable, Identifiable {
    public var id: String { relativePath }
    public let name: String
    public let relativePath: String
    public let kind: WorkspaceBrowserEntryKind
    public let byteCount: Int64?

    public init(
        name: String,
        relativePath: String,
        kind: WorkspaceBrowserEntryKind,
        byteCount: Int64?
    ) {
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = byteCount
    }
}

public struct WorkspaceBrowserDirectory: Equatable, Sendable {
    public let rootDisplayPath: String
    public let relativePath: String
    public let entries: [WorkspaceBrowserEntry]
    public let isTruncated: Bool

    public init(
        rootDisplayPath: String,
        relativePath: String,
        entries: [WorkspaceBrowserEntry],
        isTruncated: Bool
    ) {
        self.rootDisplayPath = rootDisplayPath
        self.relativePath = relativePath
        self.entries = entries
        self.isTruncated = isTruncated
    }
}

public struct WorkspaceTextPreview: Equatable, Sendable {
    public let rootDisplayPath: String
    public let relativePath: String
    public let text: String
    public let byteCount: Int

    public init(rootDisplayPath: String, relativePath: String, text: String, byteCount: Int) {
        self.rootDisplayPath = rootDisplayPath
        self.relativePath = relativePath
        self.text = text
        self.byteCount = byteCount
    }
}

public enum WorkspaceBrowserError: Error, Equatable, Sendable {
    case invalidLimits
    case invalidRoot
    case invalidRelativePath
    case itemUnavailable
    case symbolicLinkBlocked
    case notDirectory
    case notRegularFile
    case previewTooLarge(limit: Int)
    case notText
    case readFailed
}

/// A read-only filesystem capability rooted at one directory selected by the operator.
/// Child access is descriptor-relative and rejects symbolic links at every component.
public final class ConfinedWorkspaceBrowser: @unchecked Sendable {
    private let selectedRootURL: URL
    private let canonicalRootURL: URL
    private let limits: WorkspaceBrowserLimits
    private let rootFileDescriptor: Int32
    private let didStartSecurityScopedAccess: Bool

    public init(
        rootURL: URL,
        limits: WorkspaceBrowserLimits = .secureDefault
    ) throws {
        guard rootURL.isFileURL else { throw WorkspaceBrowserError.invalidRoot }
        let selected = rootURL.standardizedFileURL
        let accessed = selected.startAccessingSecurityScopedResource()
        var shouldStopAccess = accessed
        defer {
            if shouldStopAccess { selected.stopAccessingSecurityScopedResource() }
        }
        var selectedStatus = stat()
        guard lstat(selected.path, &selectedStatus) == 0,
              selectedStatus.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceBrowserError.invalidRoot
        }
        let canonical = selected.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceBrowserError.invalidRoot
        }
        let rootFileDescriptor = Darwin.open(
            canonical.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootFileDescriptor >= 0 else { throw WorkspaceBrowserError.invalidRoot }
        self.selectedRootURL = selected
        self.canonicalRootURL = canonical
        self.limits = limits
        self.rootFileDescriptor = rootFileDescriptor
        self.didStartSecurityScopedAccess = accessed
        shouldStopAccess = false
    }

    deinit {
        Darwin.close(rootFileDescriptor)
        if didStartSecurityScopedAccess {
            selectedRootURL.stopAccessingSecurityScopedResource()
        }
    }

    public var rootDisplayPath: String { canonicalRootURL.path }

    public func list(relativePath: String = "") throws -> WorkspaceBrowserDirectory {
        try withPinnedRoot {
            let components = try validatedComponents(relativePath, allowRoot: true)
            let directoryFD = try openDirectory(components: components)
            defer { Darwin.close(directoryFD) }
            let duplicateFD = Darwin.dup(directoryFD)
            guard duplicateFD >= 0, let directory = fdopendir(duplicateFD) else {
                if duplicateFD >= 0 { Darwin.close(duplicateFD) }
                throw WorkspaceBrowserError.readFailed
            }
            defer { closedir(directory) }

            var entries: [WorkspaceBrowserEntry] = []
            var isTruncated = false
            while let pointer = readdir(directory) {
                let name = withUnsafePointer(to: pointer.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                        String(cString: $0)
                    }
                }
                guard name != ".", name != ".." else { continue }
                guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
                    continue
                }
                if entries.count == limits.maximumEntriesPerDirectory {
                    isTruncated = true
                    break
                }

                var status = stat()
                guard fstatat(directoryFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
                    continue
                }
                let kind: WorkspaceBrowserEntryKind
                let byteCount: Int64?
                switch status.st_mode & S_IFMT {
                case S_IFDIR:
                    kind = .directory
                    byteCount = nil
                case S_IFREG:
                    kind = .file
                    byteCount = status.st_size >= 0 ? Int64(status.st_size) : nil
                case S_IFLNK:
                    kind = .symbolicLinkBlocked
                    byteCount = nil
                default:
                    kind = .unsupported
                    byteCount = nil
                }
                let childPath = (components + [name]).joined(separator: "/")
                entries.append(WorkspaceBrowserEntry(
                    name: name,
                    relativePath: childPath,
                    kind: kind,
                    byteCount: byteCount
                ))
            }
            entries.sort {
                if $0.kind == .directory, $1.kind != .directory { return true }
                if $0.kind != .directory, $1.kind == .directory { return false }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return WorkspaceBrowserDirectory(
                rootDisplayPath: rootDisplayPath,
                relativePath: components.joined(separator: "/"),
                entries: entries,
                isTruncated: isTruncated
            )
        }
    }

    public func preview(relativePath: String) throws -> WorkspaceTextPreview {
        try withPinnedRoot {
            let components = try validatedComponents(relativePath, allowRoot: false)
            let parentFD = try openDirectory(components: Array(components.dropLast()))
            defer { Darwin.close(parentFD) }
            let fileName = components[components.count - 1]
            let fileFD = openat(parentFD, fileName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard fileFD >= 0 else {
                if errno == ELOOP { throw WorkspaceBrowserError.symbolicLinkBlocked }
                throw WorkspaceBrowserError.itemUnavailable
            }
            defer { Darwin.close(fileFD) }

            var status = stat()
            guard fstat(fileFD, &status) == 0 else { throw WorkspaceBrowserError.readFailed }
            guard status.st_mode & S_IFMT == S_IFREG else { throw WorkspaceBrowserError.notRegularFile }
            guard status.st_size >= 0, status.st_size <= off_t(limits.maximumPreviewBytes) else {
                throw WorkspaceBrowserError.previewTooLarge(limit: limits.maximumPreviewBytes)
            }

            var data = Data()
            data.reserveCapacity(limits.maximumPreviewBytes + 1)
            var buffer = [UInt8](repeating: 0, count: min(16 * 1_024, limits.maximumPreviewBytes + 1))
            while data.count <= limits.maximumPreviewBytes {
                let allowance = min(buffer.count, limits.maximumPreviewBytes + 1 - data.count)
                let bytesRead = Darwin.read(fileFD, &buffer, allowance)
                if bytesRead == 0 { break }
                if bytesRead < 0 {
                    if errno == EINTR { continue }
                    throw WorkspaceBrowserError.readFailed
                }
                data.append(contentsOf: buffer.prefix(bytesRead))
            }
            guard data.count <= limits.maximumPreviewBytes else {
                throw WorkspaceBrowserError.previewTooLarge(limit: limits.maximumPreviewBytes)
            }
            guard let text = String(data: data, encoding: .utf8), Self.isSafeText(text) else {
                throw WorkspaceBrowserError.notText
            }
            return WorkspaceTextPreview(
                rootDisplayPath: rootDisplayPath,
                relativePath: components.joined(separator: "/"),
                text: text,
                byteCount: data.count
            )
        }
    }

    private func withPinnedRoot<T>(_ operation: () throws -> T) throws -> T {
        guard fcntl(rootFileDescriptor, F_GETFD) >= 0 else {
            throw WorkspaceBrowserError.invalidRoot
        }
        return try operation()
    }

    private func validatedComponents(_ relativePath: String, allowRoot: Bool) throws -> [String] {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\"), !relativePath.contains("\0") else {
            throw WorkspaceBrowserError.invalidRelativePath
        }
        if relativePath.isEmpty {
            guard allowRoot else { throw WorkspaceBrowserError.invalidRelativePath }
            return []
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count <= limits.maximumPathDepth,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WorkspaceBrowserError.invalidRelativePath
        }
        return components
    }

    private func openDirectory(components: [String]) throws -> Int32 {
        var currentFD = Darwin.dup(rootFileDescriptor)
        guard currentFD >= 0 else { throw WorkspaceBrowserError.invalidRoot }
        for component in components {
            let nextFD = openat(currentFD, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            Darwin.close(currentFD)
            guard nextFD >= 0 else {
                if errno == ELOOP { throw WorkspaceBrowserError.symbolicLinkBlocked }
                if errno == ENOTDIR { throw WorkspaceBrowserError.notDirectory }
                throw WorkspaceBrowserError.itemUnavailable
            }
            currentFD = nextFD
        }
        return currentFD
    }

    private static func isSafeText(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D ||
                (scalar.properties.generalCategory != .control &&
                    scalar.properties.generalCategory != .format)
        }
    }
}
