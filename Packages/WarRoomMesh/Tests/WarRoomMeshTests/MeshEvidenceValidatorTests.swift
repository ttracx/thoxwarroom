import CryptoKit
import Foundation
import MeshContractEvidence
import XCTest

final class MeshEvidenceValidatorTests: XCTestCase {
    func testAuditAcceptsTruthfulAllMissingManifest() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        try fixture.writeManifest(requirements: missingRequirements(), artifacts: [])

        let result = try fixture.audit()

        XCTAssertEqual(result.captured, [])
        XCTAssertEqual(result.missing, Set(MeshEvidenceManifest.Requirement.allCases))
        XCTAssertEqual(result.artifactCount, 0)
        XCTAssertEqual(result.totalArtifactBytes, 0)
    }

    func testAuditAcceptsTruthfulPartialManifestAndQualificationFailsClosed() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let body = Data(#"{"authorization":"<redacted>","status":401}"#.utf8)
        let artifact = try fixture.writeArtifact(
            id: "authn",
            relativePath: "artifacts/authentication.json",
            data: body
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .authenticationErrors, artifactID: artifact.id),
            artifacts: [artifact]
        )

        let result = try fixture.audit()
        XCTAssertEqual(result.captured, [.authenticationErrors])
        XCTAssertEqual(
            result.missing,
            Set(MeshEvidenceManifest.Requirement.allCases).subtracting([.authenticationErrors])
        )

        XCTAssertThrowsError(
            try MeshEvidenceValidator().validate(
                manifestURL: fixture.manifestURL,
                mode: .qualifyPrivateCoordinator
            )
        ) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
                .incompleteContract(missing: result.missing)
            )
        }
    }

    func testQualificationAcceptsCompleteSanitizedBoundedEvidence() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        var artifacts: [MeshEvidenceManifest.Artifact] = []
        var requirements: [MeshEvidenceManifest.RequirementEvidence] = []
        var totalBytes = 0

        for requirement in MeshEvidenceManifest.Requirement.allCases {
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
            requirements.append(.init(
                requirement: requirement,
                status: .captured,
                artifactIDs: [artifact.id]
            ))
        }
        try fixture.writeManifest(requirements: requirements, artifacts: artifacts)

        let result = try MeshEvidenceValidator().validate(
            manifestURL: fixture.manifestURL,
            mode: .qualifyPrivateCoordinator
        )

        XCTAssertEqual(result.captured, Set(MeshEvidenceManifest.Requirement.allCases))
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.artifactCount, MeshEvidenceManifest.Requirement.allCases.count)
        XCTAssertEqual(result.totalArtifactBytes, totalBytes)
    }

    func testRejectsTraversalAbsoluteAndSymlinkArtifacts() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let outsideURL = fixture.rootURL.deletingLastPathComponent().appendingPathComponent(
            "outside-mesh-evidence-\(ProcessInfo.processInfo.processIdentifier).txt"
        )
        try Data("safe".utf8).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        for path in ["../\(outsideURL.lastPathComponent)", outsideURL.path] {
            let artifact = fixture.artifact(
                id: "unsafe",
                relativePath: path,
                data: Data("safe".utf8),
                mediaType: "text/plain"
            )
            try fixture.writeManifest(
                requirements: requirements(capturing: .networkErrorBehavior, artifactID: artifact.id),
                artifacts: [artifact]
            )
            XCTAssertThrowsError(try fixture.audit()) { error in
                XCTAssertEqual(
                    error as? MeshEvidenceValidationError,
                    .unsafeArtifactPath(artifactID: artifact.id)
                )
            }
        }

        let artifactDirectory = fixture.rootURL.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let linkURL = artifactDirectory.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)
        let linked = fixture.artifact(
            id: "linked",
            relativePath: "artifacts/linked.txt",
            data: Data("safe".utf8),
            mediaType: "text/plain"
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .networkErrorBehavior, artifactID: linked.id),
            artifacts: [linked]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
                .symbolicLinkRejected(artifactID: linked.id)
            )
        }
    }

    func testRejectsSymlinkManifest() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        try fixture.writeManifest(requirements: missingRequirements(), artifacts: [])
        let linkedManifest = fixture.rootURL.appendingPathComponent("linked-manifest.json")
        try FileManager.default.createSymbolicLink(
            at: linkedManifest,
            withDestinationURL: fixture.manifestURL
        )

        XCTAssertThrowsError(
            try MeshEvidenceValidator().validate(manifestURL: linkedManifest, mode: .audit)
        ) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
                .symbolicLinkRejected(artifactID: "manifest")
            )
        }
    }

    func testRejectsCredentialSessionIdentityAndBinaryContent() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }

        let unsafeBodies = [
            Data(#"{"access_token":"live-secret-value"}"#.utf8),
            Data(#"{"user_id":"private-user"}"#.utf8),
            Data("Authorization: Bearer abcdefghijklmnopqrstuvwxyz".utf8),
            Data("Cookie: private-session-value".utf8),
            Data(#"{"mesh_id":"8314444b-38d8-44bb-a185-cf2578995b9f"}"#.utf8),
        ]
        for (index, body) in unsafeBodies.enumerated() {
            let artifact = try fixture.writeArtifact(
                id: "secret-\(index)",
                relativePath: "artifacts/secret-\(index).json",
                data: body,
                mediaType: index < 2 || index == 4 ? "application/json" : "text/plain"
            )
            try fixture.writeManifest(
                requirements: requirements(
                    capturing: .credentialUserBearerBoundary,
                    artifactID: artifact.id
                ),
                artifacts: [artifact]
            )
            XCTAssertThrowsError(try fixture.audit()) { error in
                XCTAssertEqual(
                    error as? MeshEvidenceValidationError,
                    .potentialSecret(artifactID: artifact.id)
                )
            }
        }

        let binary = try fixture.writeArtifact(
            id: "binary",
            relativePath: "artifacts/binary.txt",
            data: Data([0x00, 0xFF]),
            mediaType: "text/plain"
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .eventsResponse, artifactID: binary.id),
            artifacts: [binary]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
                .nonTextArtifact(artifactID: binary.id)
            )
        }
    }

    func testRejectsDigestByteCountPerArtifactAndTotalBounds() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let data = Data("bounded evidence".utf8)
        var artifact = try fixture.writeArtifact(
            id: "bounded",
            relativePath: "artifacts/bounded.txt",
            data: data,
            mediaType: "text/plain"
        )
        let captured = requirements(capturing: .cancellationBehavior, artifactID: artifact.id)

        artifact = .init(
            id: artifact.id,
            relativePath: artifact.relativePath,
            mediaType: artifact.mediaType,
            byteCount: data.count + 1,
            sha256: artifact.sha256,
            sanitized: true
        )
        try fixture.writeManifest(requirements: captured, artifacts: [artifact])
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
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
                error as? MeshEvidenceValidationError,
                .digestMismatch(artifactID: artifact.id)
            )
        }

        artifact = fixture.artifact(
            id: artifact.id,
            relativePath: artifact.relativePath,
            data: data,
            mediaType: artifact.mediaType
        )
        try fixture.writeManifest(requirements: captured, artifacts: [artifact])
        let strictArtifact = MeshEvidenceValidator(maximumArtifactBytes: data.count - 1)
        XCTAssertThrowsError(
            try strictArtifact.validate(manifestURL: fixture.manifestURL, mode: .audit)
        ) { error in
            XCTAssertEqual(
                error as? MeshEvidenceValidationError,
                .artifactTooLarge(artifactID: artifact.id)
            )
        }

        let strictTotal = MeshEvidenceValidator(maximumTotalArtifactBytes: data.count - 1)
        XCTAssertThrowsError(
            try strictTotal.validate(manifestURL: fixture.manifestURL, mode: .audit)
        ) { error in
            XCTAssertEqual(error as? MeshEvidenceValidationError, .totalArtifactBytesExceeded)
        }
    }

    func testRejectsMalformedRequirementArtifactAndCaptureMetadata() throws {
        let fixture = try EvidenceFixture()
        defer { fixture.remove() }
        let duplicated = Array(missingRequirements().dropLast()) + [missingRequirements()[0]]
        try fixture.writeManifest(requirements: duplicated, artifacts: [])
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(error as? MeshEvidenceValidationError, .invalidRequirementSet)
        }

        let body = Data("safe".utf8)
        let artifact = try fixture.writeArtifact(
            id: "orphan",
            relativePath: "artifacts/orphan.txt",
            data: body,
            mediaType: "text/plain"
        )
        try fixture.writeManifest(requirements: missingRequirements(), artifacts: [artifact])
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(error as? MeshEvidenceValidationError, .artifactReferenceMismatch)
        }

        let unsafeID = fixture.artifact(
            id: "Authorization:Bearer-private-value",
            relativePath: "artifacts/safe.txt",
            data: body,
            mediaType: "text/plain"
        )
        try fixture.writeManifest(
            requirements: requirements(capturing: .devicesResponse, artifactID: unsafeID.id),
            artifacts: [unsafeID]
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(error as? MeshEvidenceValidationError, .duplicateOrEmptyArtifactID)
        }

        try fixture.writeManifest(
            requirements: requirements(capturing: .devicesResponse, artifactID: artifact.id),
            artifacts: [artifact],
            captureOverride: .init(
                status: .captured,
                capturedAt: "2026-08-23T00:00:00Z",
                origin: "https://mesh.example.invalid",
                serviceVersion: "test",
                environmentBoundary: "dedicated_non_production",
                sanctionedTestIdentity: false,
                sanctionedTestMesh: true,
                retainedSensitiveValues: false
            )
        )
        XCTAssertThrowsError(try fixture.audit()) { error in
            XCTAssertEqual(error as? MeshEvidenceValidationError, .invalidCaptureMetadata)
        }
    }

    private func missingRequirements() -> [MeshEvidenceManifest.RequirementEvidence] {
        MeshEvidenceManifest.Requirement.allCases.map {
            .init(requirement: $0, status: .missing, artifactIDs: [])
        }
    }

    private func requirements(
        capturing requirement: MeshEvidenceManifest.Requirement,
        artifactID: String
    ) -> [MeshEvidenceManifest.RequirementEvidence] {
        MeshEvidenceManifest.Requirement.allCases.map {
            .init(
                requirement: $0,
                status: $0 == requirement ? .captured : .missing,
                artifactIDs: $0 == requirement ? [artifactID] : []
            )
        }
    }
}

private final class EvidenceFixture {
    let rootURL: URL
    var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mesh-evidence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeManifest(
        requirements: [MeshEvidenceManifest.RequirementEvidence],
        artifacts: [MeshEvidenceManifest.Artifact],
        captureOverride: MeshEvidenceManifest.Capture? = nil
    ) throws {
        let hasCapture = requirements.contains(where: { $0.status == .captured })
        let capture = captureOverride ?? .init(
            status: hasCapture ? .captured : .notCaptured,
            capturedAt: hasCapture ? "2026-08-23T00:00:00Z" : nil,
            origin: "https://dedicated-mesh-nonproduction.invalid",
            serviceVersion: hasCapture ? "test-version" : "not_captured",
            environmentBoundary: hasCapture
                ? "dedicated_non_production"
                : "dedicated_non_production_required",
            sanctionedTestIdentity: hasCapture,
            sanctionedTestMesh: hasCapture,
            retainedSensitiveValues: false
        )
        let manifest = MeshEvidenceManifest(
            schemaVersion: 1,
            fixtureKind: "sanitized_authenticated_mesh_read_only_contract",
            capture: capture,
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
    ) throws -> MeshEvidenceManifest.Artifact {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return artifact(id: id, relativePath: relativePath, data: data, mediaType: mediaType)
    }

    func artifact(
        id: String,
        relativePath: String,
        data: Data,
        mediaType: String
    ) -> MeshEvidenceManifest.Artifact {
        .init(
            id: id,
            relativePath: relativePath,
            mediaType: mediaType,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sanitized: true
        )
    }

    func audit() throws -> MeshEvidenceValidator.Result {
        try MeshEvidenceValidator().validate(manifestURL: manifestURL, mode: .audit)
    }
}
