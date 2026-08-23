import CryptoKit
import Foundation
import XCTest
@testable import HermesContractEvidence

final class HermesEvidenceManifestTests: XCTestCase {
    typealias Manifest = HermesEvidenceManifest
    typealias Requirement = HermesEvidenceManifest.Requirement
    typealias ValidationError = HermesEvidenceValidationError

    func testCheckedInPlaceholderAuditsTruthfullyButDoesNotQualify() throws {
        let manifestURL = packageRoot
            .appendingPathComponent("Evidence/private-api/current.manifest.json")
        let expectedMissing = Set(Requirement.allCases)

        let result = try HermesEvidenceValidator().validate(manifestURL: manifestURL, mode: .audit)

        XCTAssertEqual(result.captured, [])
        XCTAssertEqual(result.missing, expectedMissing)
        XCTAssertEqual(result.artifactCount, 0)
        XCTAssertEqual(result.totalArtifactBytes, 0)
        assertValidationError(
            .incompleteContract(missing: expectedMissing),
            manifestURL: manifestURL,
            mode: .qualifyPrivateAPI
        )
    }

    func testCompleteSanitizedCaptureQualifies() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let manifest = try completeCapturedManifest(in: sandbox)
        let manifestURL = try sandbox.writeManifest(manifest)

        let result = try HermesEvidenceValidator().validate(
            manifestURL: manifestURL,
            mode: .qualifyPrivateAPI
        )

        XCTAssertEqual(result.captured, Set(Requirement.allCases))
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.artifactCount, Requirement.allCases.count)
        XCTAssertGreaterThan(result.totalArtifactBytes, 0)
    }

    func testMissingSetIsExactAndIndependentOfManifestRequirementOrder() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let captured: Set<Requirement> = [.credentialBoundary, .runStatusResponse, .errorResponses]
        let expectedMissing = Set(Requirement.allCases).subtracting(captured)
        let normal = try capturedManifest(in: sandbox, captured: captured)
        let reversed = Manifest(
            schemaVersion: normal.schemaVersion,
            fixtureKind: normal.fixtureKind,
            capture: normal.capture,
            requirements: normal.requirements.reversed(),
            artifacts: normal.artifacts
        )
        let firstURL = try sandbox.writeManifest(normal, name: "normal.manifest.json")
        let secondURL = try sandbox.writeManifest(reversed, name: "reversed.manifest.json")

        let first = try HermesEvidenceValidator().validate(manifestURL: firstURL, mode: .audit)
        let second = try HermesEvidenceValidator().validate(manifestURL: secondURL, mode: .audit)

        XCTAssertEqual(first.missing, expectedMissing)
        XCTAssertEqual(second.missing, expectedMissing)
        XCTAssertEqual(first, second)
        assertValidationError(
            .incompleteContract(missing: expectedMissing),
            manifestURL: secondURL,
            mode: .qualifyPrivateAPI
        )
    }

    func testRejectsManifestWithWrongShape() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let manifestURL = try sandbox.write(Data("{}".utf8), relativePath: "bad.manifest.json")

        assertValidationError(.invalidManifest, manifestURL: manifestURL)
    }

    func testRejectsMalformedJSONManifestWithoutEchoingContent() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let manifestURL = try sandbox.write(Data("{not-json".utf8), relativePath: "bad.manifest.json")

        assertValidationError(
            .invalidJSONArtifact(artifactID: "manifest"),
            manifestURL: manifestURL
        )
    }

    func testRejectsOversizedManifestBeforeDecoding() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let manifestURL = try sandbox.write(Data("{}".utf8), relativePath: "manifest.json")

        assertValidationError(
            .artifactTooLarge(artifactID: "manifest"),
            manifestURL: manifestURL,
            validator: HermesEvidenceValidator(maximumManifestBytes: 1)
        )
    }

    func testRejectsManifestSymbolicLink() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let targetURL = try sandbox.writeManifest(missingManifest(), name: "actual.manifest.json")
        let linkURL = sandbox.url.appendingPathComponent("linked.manifest.json")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        assertValidationError(
            .symbolicLinkRejected(artifactID: "manifest"),
            manifestURL: linkURL
        )
    }

    func testRejectsTraversalAndAbsoluteArtifactPaths() throws {
        for unsafePath in ["../outside.json", "/tmp/outside.json", "nested/../outside.json"] {
            let sandbox = try EvidenceSandbox()
            defer { sandbox.remove() }
            let data = Data("{}".utf8)
            let artifact = artifactRecord(id: "unsafe", path: unsafePath, data: data)
            let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

            assertValidationError(
                .unsafeArtifactPath(artifactID: "unsafe"),
                manifestURL: manifestURL
            )
        }
    }

    func testRejectsArtifactSymbolicLinkIncludingSymlinkedParentDirectory() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{}".utf8)
        let targetURL = try sandbox.write(data, relativePath: "actual.json")
        let directLinkURL = sandbox.url.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: directLinkURL, withDestinationURL: targetURL)
        var artifact = artifactRecord(id: "linked", path: "linked.json", data: data)
        var manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "direct.manifest.json"
        )
        assertValidationError(
            .symbolicLinkRejected(artifactID: "linked"),
            manifestURL: manifestURL
        )

        let realDirectory = sandbox.url.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try data.write(to: realDirectory.appendingPathComponent("capture.json"))
        let linkedDirectory = sandbox.url.appendingPathComponent("linked-directory", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        artifact = artifactRecord(id: "nested-link", path: "linked-directory/capture.json", data: data)
        manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "parent.manifest.json"
        )
        assertValidationError(
            .symbolicLinkRejected(artifactID: "nested-link"),
            manifestURL: manifestURL
        )
    }

    func testRejectsDigestMismatch() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{}".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        let artifact = Manifest.Artifact(
            id: "digest",
            relativePath: "capture.json",
            mediaType: "application/json",
            byteCount: data.count,
            sha256: String(repeating: "0", count: 64),
            sanitized: true
        )
        let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

        assertValidationError(.digestMismatch(artifactID: "digest"), manifestURL: manifestURL)
    }

    func testRejectsByteCountMismatch() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{}".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        let artifact = Manifest.Artifact(
            id: "bytes",
            relativePath: "capture.json",
            mediaType: "application/json",
            byteCount: data.count + 1,
            sha256: sha256Hex(data),
            sanitized: true
        )
        let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

        assertValidationError(.byteCountMismatch(artifactID: "bytes"), manifestURL: manifestURL)
    }

    func testRejectsPerArtifactAndAggregateSizeLimitViolations() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let singleData = Data("{}".utf8)
        var manifest = try capturedManifest(
            in: sandbox,
            captured: [.credentialBoundary],
            payload: { _ in singleData }
        )
        var manifestURL = try sandbox.writeManifest(manifest, name: "single.manifest.json")
        assertValidationError(
            .artifactTooLarge(artifactID: "credential_boundary"),
            manifestURL: manifestURL,
            validator: HermesEvidenceValidator(maximumArtifactBytes: singleData.count - 1)
        )

        let captured: Set<Requirement> = [.credentialBoundary, .capabilitiesResponse]
        manifest = try capturedManifest(in: sandbox, captured: captured, payload: { _ in singleData })
        manifestURL = try sandbox.writeManifest(manifest, name: "aggregate.manifest.json")
        assertValidationError(
            .totalArtifactBytesExceeded,
            manifestURL: manifestURL,
            validator: HermesEvidenceValidator(maximumTotalArtifactBytes: singleData.count)
        )
    }

    func testRejectsUnsupportedMediaTypeAndUnsanitizedMarker() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{}".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        var artifact = Manifest.Artifact(
            id: "media",
            relativePath: "capture.json",
            mediaType: "application/octet-stream",
            byteCount: data.count,
            sha256: sha256Hex(data),
            sanitized: true
        )
        var manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "media.manifest.json"
        )
        assertValidationError(.unsupportedMediaType(artifactID: "media"), manifestURL: manifestURL)

        artifact = Manifest.Artifact(
            id: "raw",
            relativePath: "capture.json",
            mediaType: "application/json",
            byteCount: data.count,
            sha256: sha256Hex(data),
            sanitized: false
        )
        manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "raw.manifest.json"
        )
        assertValidationError(.unsanitizedArtifact(artifactID: "raw"), manifestURL: manifestURL)
    }

    func testRejectsBinaryArtifactEvenWhenDigestAndLengthMatch() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        _ = try sandbox.write(data, relativePath: "capture.txt")
        let artifact = artifactRecord(
            id: "binary",
            path: "capture.txt",
            mediaType: "text/plain",
            data: data
        )
        let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

        assertValidationError(.nonTextArtifact(artifactID: "binary"), manifestURL: manifestURL)
    }

    func testRejectsMalformedJSONArtifact() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{not-json".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        let artifact = artifactRecord(id: "json", path: "capture.json", data: data)
        let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

        assertValidationError(.invalidJSONArtifact(artifactID: "json"), manifestURL: manifestURL)
    }

    func testRejectsHeaderBearerJWTAndPrivateKeySecrets() throws {
        let secretPayloads = [
            "Authorization: actual-secret",
            "Cookie: session-secret",
            "Bearer abcdefghijklmnopqrstuvwxyz",
            "eyJabcdefgh.ijklmnop.qrstuvwx",
            "-----BEGIN PRIVATE " + "KEY-----",
        ]

        for (index, text) in secretPayloads.enumerated() {
            let sandbox = try EvidenceSandbox()
            defer { sandbox.remove() }
            let data = Data(text.utf8)
            let path = "secret-\(index).txt"
            _ = try sandbox.write(data, relativePath: path)
            let artifact = artifactRecord(
                id: "secret-\(index)",
                path: path,
                mediaType: "text/plain",
                data: data
            )
            let manifestURL = try sandbox.writeManifest(singleCapturedManifest(artifact: artifact))

            assertValidationError(
                .potentialSecret(artifactID: "secret-\(index)"),
                manifestURL: manifestURL
            )
        }
    }

    func testRejectsNestedSensitiveJSONButAcceptsExplicitRedaction() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let secretData = Data(#"{"outer":[{"x-api-key":"actual-secret"}]}"#.utf8)
        _ = try sandbox.write(secretData, relativePath: "secret.json")
        var artifact = artifactRecord(id: "json-secret", path: "secret.json", data: secretData)
        var manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "secret.manifest.json"
        )
        assertValidationError(
            .potentialSecret(artifactID: "json-secret"),
            manifestURL: manifestURL
        )

        let redactedData = Data(#"{"outer":[{"x-api-key":"<redacted>"}]}"#.utf8)
        _ = try sandbox.write(redactedData, relativePath: "redacted.json")
        artifact = artifactRecord(id: "redacted", path: "redacted.json", data: redactedData)
        manifestURL = try sandbox.writeManifest(
            singleCapturedManifest(artifact: artifact),
            name: "redacted.manifest.json"
        )
        XCTAssertNoThrow(
            try HermesEvidenceValidator().validate(manifestURL: manifestURL, mode: .audit)
        )
    }

    func testRejectsInvalidCapturedAndNotCapturedMetadataCombinations() throws {
        let invalidCaptures = [
            Manifest.Capture(
                status: .captured,
                capturedAt: nil,
                origin: "https://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "not-a-timestamp",
                origin: "https://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "http://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://user:password@hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://hermes.test.invalid?leak=value",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "production",
                syntheticRun: true,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: false,
                retainedSensitiveValues: false
            ),
            Manifest.Capture(
                status: .captured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://hermes.test.invalid",
                serviceVersion: "test-version",
                environmentBoundary: "dedicated_non_production",
                syntheticRun: true,
                retainedSensitiveValues: true
            ),
            Manifest.Capture(
                status: .notCaptured,
                capturedAt: "2026-08-23T12:34:56Z",
                origin: "https://hermes.test.invalid",
                serviceVersion: "not_captured",
                environmentBoundary: "dedicated_non_production_required",
                syntheticRun: false,
                retainedSensitiveValues: false
            ),
        ]

        for (index, capture) in invalidCaptures.enumerated() {
            let sandbox = try EvidenceSandbox()
            defer { sandbox.remove() }
            let manifest = Manifest(
                schemaVersion: 1,
                fixtureKind: validFixtureKind,
                capture: capture,
                requirements: missingRequirementEvidence(),
                artifacts: []
            )
            let manifestURL = try sandbox.writeManifest(manifest, name: "invalid-\(index).json")
            assertValidationError(.invalidCaptureMetadata, manifestURL: manifestURL)
        }
    }

    func testNotCapturedMetadataCannotClaimCapturedRequirements() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }
        let data = Data("{}".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        let artifact = artifactRecord(id: "capture", path: "capture.json", data: data)
        let capturedEvidence = Requirement.allCases.map { requirement in
            Manifest.RequirementEvidence(
                requirement: requirement,
                status: requirement == .credentialBoundary ? .captured : .missing,
                artifactIDs: requirement == .credentialBoundary ? [artifact.id] : []
            )
        }
        let manifest = Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validNotCapturedMetadata,
            requirements: capturedEvidence,
            artifacts: [artifact]
        )
        let manifestURL = try sandbox.writeManifest(manifest)

        assertValidationError(.invalidCaptureMetadata, manifestURL: manifestURL)
    }

    func testRejectsInvalidRequirementAndArtifactReferenceStructures() throws {
        let sandbox = try EvidenceSandbox()
        defer { sandbox.remove() }

        let missingRequirement = Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validNotCapturedMetadata,
            requirements: Array(missingRequirementEvidence().dropLast()),
            artifacts: []
        )
        var manifestURL = try sandbox.writeManifest(
            missingRequirement,
            name: "missing-requirement.json"
        )
        assertValidationError(.invalidRequirementSet, manifestURL: manifestURL)

        let data = Data("{}".utf8)
        _ = try sandbox.write(data, relativePath: "capture.json")
        let artifact = artifactRecord(id: "orphan", path: "capture.json", data: data)
        let orphanManifest = Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validCapturedMetadata,
            requirements: missingRequirementEvidence(),
            artifacts: [artifact]
        )
        manifestURL = try sandbox.writeManifest(orphanManifest, name: "orphan.json")
        assertValidationError(.artifactReferenceMismatch, manifestURL: manifestURL)

        let emptyCaptured = Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validCapturedMetadata,
            requirements: Requirement.allCases.map { requirement in
                Manifest.RequirementEvidence(
                    requirement: requirement,
                    status: requirement == .credentialBoundary ? .captured : .missing,
                    artifactIDs: []
                )
            },
            artifacts: []
        )
        manifestURL = try sandbox.writeManifest(emptyCaptured, name: "empty-captured.json")
        assertValidationError(
            .capturedRequirementHasNoArtifacts(.credentialBoundary),
            manifestURL: manifestURL
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var validCapturedMetadata: Manifest.Capture {
        Manifest.Capture(
            status: .captured,
            capturedAt: "2026-08-23T12:34:56Z",
            origin: "https://hermes.test.invalid",
            serviceVersion: "test-version",
            environmentBoundary: "dedicated_non_production",
            syntheticRun: true,
            retainedSensitiveValues: false
        )
    }

    private var validNotCapturedMetadata: Manifest.Capture {
        Manifest.Capture(
            status: .notCaptured,
            capturedAt: nil,
            origin: "https://dedicated-hermes-nonproduction.invalid",
            serviceVersion: "not_captured",
            environmentBoundary: "dedicated_non_production_required",
            syntheticRun: false,
            retainedSensitiveValues: false
        )
    }

    private var validFixtureKind: String {
        "sanitized_authenticated_hermes_private_api_contract"
    }

    private func missingManifest() -> Manifest {
        Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validNotCapturedMetadata,
            requirements: missingRequirementEvidence(),
            artifacts: []
        )
    }

    private func missingRequirementEvidence() -> [Manifest.RequirementEvidence] {
        Requirement.allCases.map {
            Manifest.RequirementEvidence(requirement: $0, status: .missing, artifactIDs: [])
        }
    }

    private func completeCapturedManifest(in sandbox: EvidenceSandbox) throws -> Manifest {
        try capturedManifest(in: sandbox, captured: Set(Requirement.allCases))
    }

    private func capturedManifest(
        in sandbox: EvidenceSandbox,
        captured: Set<Requirement>,
        payload: (Requirement) -> Data = { requirement in
            Data(#"{"captured":"\#(requirement.rawValue)"}"#.utf8)
        }
    ) throws -> Manifest {
        var artifacts: [Manifest.Artifact] = []
        let requirements = try Requirement.allCases.map { requirement in
            guard captured.contains(requirement) else {
                return Manifest.RequirementEvidence(
                    requirement: requirement,
                    status: .missing,
                    artifactIDs: []
                )
            }
            let data = payload(requirement)
            let path = "artifacts/\(requirement.rawValue).json"
            _ = try sandbox.write(data, relativePath: path)
            let artifact = artifactRecord(id: requirement.rawValue, path: path, data: data)
            artifacts.append(artifact)
            return Manifest.RequirementEvidence(
                requirement: requirement,
                status: .captured,
                artifactIDs: [artifact.id]
            )
        }
        return Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validCapturedMetadata,
            requirements: requirements,
            artifacts: artifacts
        )
    }

    private func singleCapturedManifest(artifact: Manifest.Artifact) -> Manifest {
        Manifest(
            schemaVersion: 1,
            fixtureKind: validFixtureKind,
            capture: validCapturedMetadata,
            requirements: Requirement.allCases.map { requirement in
                Manifest.RequirementEvidence(
                    requirement: requirement,
                    status: requirement == .credentialBoundary ? .captured : .missing,
                    artifactIDs: requirement == .credentialBoundary ? [artifact.id] : []
                )
            },
            artifacts: [artifact]
        )
    }

    private func artifactRecord(
        id: String,
        path: String,
        mediaType: String = "application/json",
        data: Data
    ) -> Manifest.Artifact {
        Manifest.Artifact(
            id: id,
            relativePath: path,
            mediaType: mediaType,
            byteCount: data.count,
            sha256: sha256Hex(data),
            sanitized: true
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func assertValidationError(
        _ expected: ValidationError,
        manifestURL: URL,
        mode: HermesEvidenceValidator.Mode = .audit,
        validator: HermesEvidenceValidator = HermesEvidenceValidator(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try validator.validate(manifestURL: manifestURL, mode: mode),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? ValidationError, expected, file: file, line: line)
        }
    }
}

private final class EvidenceSandbox {
    let url: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thoxwarroom-hermes-evidence-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        url = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, relativePath: String) throws -> URL {
        let destination = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func writeManifest(
        _ manifest: HermesEvidenceManifest,
        name: String = "manifest.json"
    ) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try write(encoder.encode(manifest), relativePath: name)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
