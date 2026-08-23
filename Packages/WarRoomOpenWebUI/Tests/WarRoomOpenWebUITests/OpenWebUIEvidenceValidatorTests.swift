import CryptoKit
import Foundation
import OpenWebUIContractEvidence
import XCTest

final class OpenWebUIEvidenceValidatorTests: XCTestCase {
    func testAuditAcceptsTruthfulIncompleteManifest() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        try fixture.writeManifest(requirements: missingRequirements(), artifacts: [])

        let result = try OpenWebUIEvidenceValidator().validate(
            manifestURL: fixture.manifestURL,
            mode: .audit
        )

        XCTAssertEqual(result.captured, [])
        XCTAssertEqual(result.missing, Set(OpenWebUIEvidenceManifest.Requirement.allCases))
        XCTAssertEqual(result.artifactCount, 0)
        XCTAssertEqual(result.totalArtifactBytes, 0)
    }

    func testQualificationFailsClosedWithExactMissingSet() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        try fixture.writeManifest(requirements: missingRequirements(), artifacts: [])

        XCTAssertThrowsError(
            try OpenWebUIEvidenceValidator().validate(
                manifestURL: fixture.manifestURL,
                mode: .qualifyNativeChat
            )
        ) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .incompleteContract(missing: Set(OpenWebUIEvidenceManifest.Requirement.allCases))
            )
        }
    }

    func testQualificationAcceptsCompleteSanitizedBoundedEvidence() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var artifacts: [OpenWebUIEvidenceManifest.Artifact] = []
        var requirements: [OpenWebUIEvidenceManifest.RequirementEvidence] = []
        var totalBytes = 0
        for requirement in OpenWebUIEvidenceManifest.Requirement.allCases {
            let body = Data(
                #"{"authorization":"<redacted>","evidence_kind":"\#(requirement.rawValue)"}"#.utf8
            )
            let artifact = try fixture.writeArtifact(
                id: requirement.rawValue,
                relativePath: "artifacts/\(requirement.rawValue).json",
                data: body
            )
            artifacts.append(artifact)
            totalBytes += body.count
            requirements.append(
            OpenWebUIEvidenceManifest.RequirementEvidence(
                requirement: requirement,
                status: .captured,
                artifactIDs: [artifact.id]
            )
            )
        }
        try fixture.writeManifest(requirements: requirements, artifacts: artifacts)

        let result = try OpenWebUIEvidenceValidator().validate(
            manifestURL: fixture.manifestURL,
            mode: .qualifyNativeChat
        )

        XCTAssertEqual(result.captured, Set(OpenWebUIEvidenceManifest.Requirement.allCases))
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.artifactCount, OpenWebUIEvidenceManifest.Requirement.allCases.count)
        XCTAssertEqual(result.totalArtifactBytes, totalBytes)
    }

    func testRejectsTraversalAndSymlinkArtifacts() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let outsideURL = fixture.rootURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("safe".utf8).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        let traversal = OpenWebUIEvidenceManifest.Artifact(
            id: "traversal",
            relativePath: "../\(outsideURL.lastPathComponent)",
            mediaType: "text/plain",
            byteCount: 4,
            sha256: digest(Data("safe".utf8)),
            sanitized: true
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .credentialLifecycle, artifactID: traversal.id),
            artifacts: [traversal]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .unsafeArtifactPath(artifactID: traversal.id)
            )
        }

        let artifactsURL = fixture.rootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
        let linkURL = artifactsURL.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)
        let linked = OpenWebUIEvidenceManifest.Artifact(
            id: "linked",
            relativePath: "artifacts/linked.txt",
            mediaType: "text/plain",
            byteCount: 4,
            sha256: digest(Data("safe".utf8)),
            sanitized: true
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .credentialLifecycle, artifactID: linked.id),
            artifacts: [linked]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .symbolicLinkRejected(artifactID: linked.id)
            )
        }
    }

    func testRejectsUnredactedSecretAndBinaryContent() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }

        let secretBody = Data(#"{"access_token":"live-secret-value"}"#.utf8)
        let secret = try fixture.writeArtifact(
            id: "secret",
            relativePath: "artifacts/secret.json",
            data: secretBody
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .credentialLifecycle, artifactID: secret.id),
            artifacts: [secret]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .potentialSecret(artifactID: secret.id)
            )
        }

        let binaryBody = Data([0x00, 0xFF])
        let binary = try fixture.writeArtifact(
            id: "binary",
            relativePath: "artifacts/binary.txt",
            data: binaryBody,
            mediaType: "text/plain"
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .streamingFrames, artifactID: binary.id),
            artifacts: [binary]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .nonTextArtifact(artifactID: binary.id)
            )
        }
    }

    func testRejectsDigestByteCountAndSizeMismatches() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let data = Data("bounded evidence".utf8)
        var artifact = try fixture.writeArtifact(
            id: "bounded",
            relativePath: "artifacts/bounded.txt",
            data: data,
            mediaType: "text/plain"
        )
        let captured = requirements(capturing: .cancellation, artifactID: artifact.id)

        artifact = .init(
            id: artifact.id,
            relativePath: artifact.relativePath,
            mediaType: artifact.mediaType,
            byteCount: artifact.byteCount + 1,
            sha256: artifact.sha256,
            sanitized: true
        )
        try fixture.writeManifest(requirements: captured, artifacts: [artifact])
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .byteCountMismatch(artifactID: artifact.id)
            )
        }

        artifact = .init(
            id: artifact.id,
            relativePath: artifact.relativePath,
            mediaType: artifact.mediaType,
            byteCount: data.count,
            sha256: String(repeating: "0", count: 64),
            sanitized: true
        )
        try fixture.writeManifest(requirements: captured, artifacts: [artifact])
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .digestMismatch(artifactID: artifact.id)
            )
        }

        let strict = OpenWebUIEvidenceValidator(maximumArtifactBytes: data.count - 1)
        artifact = .init(
            id: artifact.id,
            relativePath: artifact.relativePath,
            mediaType: artifact.mediaType,
            byteCount: data.count,
            sha256: digest(data),
            sanitized: true
        )
        try fixture.writeManifest(requirements: captured, artifacts: [artifact])
        XCTAssertThrowsError(
            try strict.validate(manifestURL: fixture.manifestURL, mode: .audit)
        ) { error in
            XCTAssertEqual(
                error as? OpenWebUIEvidenceValidationError,
                .artifactTooLarge(artifactID: artifact.id)
            )
        }
    }

    private func missingRequirements() -> [OpenWebUIEvidenceManifest.RequirementEvidence] {
        OpenWebUIEvidenceManifest.Requirement.allCases.map {
            .init(requirement: $0, status: .missing, artifactIDs: [])
        }
    }

    private func requirements(
        capturing requirement: OpenWebUIEvidenceManifest.Requirement,
        artifactID: String
    ) -> [OpenWebUIEvidenceManifest.RequirementEvidence] {
        OpenWebUIEvidenceManifest.Requirement.allCases.map {
            .init(
                requirement: $0,
                status: $0 == requirement ? .captured : .missing,
                artifactIDs: $0 == requirement ? [artifactID] : []
            )
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class EvidenceFixture {
    let rootURL: URL
    var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwebui-evidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeManifest(
        requirements: [OpenWebUIEvidenceManifest.RequirementEvidence],
        artifacts: [OpenWebUIEvidenceManifest.Artifact]
    ) throws {
        let manifest = OpenWebUIEvidenceManifest(
            schemaVersion: 1,
            fixtureKind: "sanitized_authenticated_openwebui_chat_contract",
            capture: .init(
                status: requirements.contains(where: { $0.status == .captured }) ? .captured : .notCaptured,
                capturedAt: requirements.contains(where: { $0.status == .captured })
                    ? "2026-08-23T00:00:00Z"
                    : nil,
                origin: "https://webui.thox.ai",
                serverVersion: "0.11.0",
                accountBoundary: requirements.contains(where: { $0.status == .captured })
                    ? "dedicated_non_production"
                    : "dedicated_non_production_required",
                syntheticPrompt: requirements.contains(where: { $0.status == .captured }),
                retainedSensitiveValues: false
            ),
            requirements: requirements,
            artifacts: artifacts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    func writeArtifact(
        id: String,
        relativePath: String,
        data: Data,
        mediaType: String = "application/json"
    ) throws -> OpenWebUIEvidenceManifest.Artifact {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return .init(
            id: id,
            relativePath: relativePath,
            mediaType: mediaType,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sanitized: true
        )
    }

    func audit() throws -> OpenWebUIEvidenceValidator.Result {
        try OpenWebUIEvidenceValidator().validate(manifestURL: manifestURL, mode: .audit)
    }
}
