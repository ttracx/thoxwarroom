import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure

final class ConfinedWorkspaceBrowserTests: XCTestCase {
    private var root: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-browser-\(UUID().uuidString)", isDirectory: true)
        outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-browser-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    func testListsOnlyBoundedMetadataAndPreviewsUTF8Text() throws {
        let nested = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("private local note\n".utf8).write(to: nested.appendingPathComponent("note.txt"))
        let browser = try ConfinedWorkspaceBrowser(rootURL: root)

        let rootListing = try browser.list()
        XCTAssertEqual(rootListing.rootDisplayPath, root.resolvingSymlinksInPath().path)
        XCTAssertEqual(rootListing.entries.map(\.name), ["Notes"])
        XCTAssertEqual(rootListing.entries.first?.kind, .directory)

        let nestedListing = try browser.list(relativePath: "Notes")
        XCTAssertEqual(nestedListing.relativePath, "Notes")
        XCTAssertEqual(nestedListing.entries.first?.relativePath, "Notes/note.txt")
        XCTAssertEqual(nestedListing.entries.first?.kind, .file)

        let preview = try browser.preview(relativePath: "Notes/note.txt")
        XCTAssertEqual(preview.text, "private local note\n")
        XCTAssertEqual(preview.relativePath, "Notes/note.txt")
        XCTAssertEqual(preview.rootDisplayPath, root.resolvingSymlinksInPath().path)
    }

    func testRejectsTraversalAbsoluteAndMalformedPaths() throws {
        let browser = try ConfinedWorkspaceBrowser(rootURL: root)
        for path in ["../secret.txt", "folder/../secret.txt", "/etc/passwd", "a//b", "a\\b", "."] {
            XCTAssertThrowsError(try browser.preview(relativePath: path), "path: \(path)") {
                XCTAssertEqual($0 as? WorkspaceBrowserError, .invalidRelativePath)
            }
        }
    }

    func testDoesNotTraverseSymbolicLinkOutsideSelectedRoot() throws {
        try Data("must not be read".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        let browser = try ConfinedWorkspaceBrowser(rootURL: root)

        let listing = try browser.list()
        XCTAssertEqual(listing.entries.first?.kind, .symbolicLinkBlocked)
        XCTAssertThrowsError(try browser.list(relativePath: "escape")) {
            XCTAssertTrue(
                ($0 as? WorkspaceBrowserError) == .symbolicLinkBlocked ||
                    ($0 as? WorkspaceBrowserError) == .notDirectory
            )
        }
        XCTAssertThrowsError(try browser.preview(relativePath: "escape/secret.txt"))
    }

    func testDirectoryListingStopsAtConfiguredLimit() throws {
        for index in 0..<5 {
            try Data("\(index)".utf8).write(to: root.appendingPathComponent("file-\(index).txt"))
        }
        let limits = try WorkspaceBrowserLimits(
            maximumEntriesPerDirectory: 3,
            maximumPreviewBytes: 128,
            maximumPathDepth: 8
        )
        let listing = try ConfinedWorkspaceBrowser(rootURL: root, limits: limits).list()

        XCTAssertEqual(listing.entries.count, 3)
        XCTAssertTrue(listing.isTruncated)
    }

    func testSelectedRootCapabilityRemainsPinnedIfPathIsReplaced() throws {
        try Data("original".utf8).write(to: root.appendingPathComponent("original.txt"))
        let browser = try ConfinedWorkspaceBrowser(rootURL: root)
        let movedRoot = root.deletingLastPathComponent()
            .appendingPathComponent("workspace-browser-moved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: root, to: movedRoot)
        defer { try? FileManager.default.removeItem(at: movedRoot) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: root.appendingPathComponent("replacement.txt"))

        let listing = try browser.list()

        XCTAssertEqual(listing.entries.map(\.name), ["original.txt"])
        XCTAssertEqual(try browser.preview(relativePath: "original.txt").text, "original")
        XCTAssertThrowsError(try browser.preview(relativePath: "replacement.txt"))
    }

    func testPreviewRejectsOversizedAndBinaryFilesWithoutReturningContent() throws {
        try Data(repeating: 0x61, count: 9).write(to: root.appendingPathComponent("large.txt"))
        try Data([0x00, 0x01, 0x02]).write(to: root.appendingPathComponent("binary.dat"))
        let limits = try WorkspaceBrowserLimits(
            maximumEntriesPerDirectory: 10,
            maximumPreviewBytes: 8,
            maximumPathDepth: 8
        )
        let browser = try ConfinedWorkspaceBrowser(rootURL: root, limits: limits)

        XCTAssertThrowsError(try browser.preview(relativePath: "large.txt")) {
            XCTAssertEqual($0 as? WorkspaceBrowserError, .previewTooLarge(limit: 8))
        }
        XCTAssertThrowsError(try browser.preview(relativePath: "binary.dat")) {
            XCTAssertEqual($0 as? WorkspaceBrowserError, .notText)
        }
    }

    func testRejectsInvalidLimitsAndNonDirectoryRoot() throws {
        XCTAssertThrowsError(try WorkspaceBrowserLimits(maximumEntriesPerDirectory: 0)) {
            XCTAssertEqual($0 as? WorkspaceBrowserError, .invalidLimits)
        }
        let file = root.appendingPathComponent("file.txt")
        try Data().write(to: file)
        XCTAssertThrowsError(try ConfinedWorkspaceBrowser(rootURL: file)) {
            XCTAssertEqual($0 as? WorkspaceBrowserError, .invalidRoot)
        }
        let linkedRoot = outside.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        XCTAssertThrowsError(try ConfinedWorkspaceBrowser(rootURL: linkedRoot)) {
            XCTAssertEqual($0 as? WorkspaceBrowserError, .invalidRoot)
        }
    }
}
