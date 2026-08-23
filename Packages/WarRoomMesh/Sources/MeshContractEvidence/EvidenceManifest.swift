import CryptoKit
import Foundation

/// A sanitized, offline-verifiable record of an authenticated private Mesh coordinator capture.
public struct MeshEvidenceManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let fixtureKind: String
    public let capture: Capture
    public let requirements: [RequirementEvidence]
    public let artifacts: [Artifact]

    public init(
        schemaVersion: Int,
        fixtureKind: String,
        capture: Capture,
        requirements: [RequirementEvidence],
        artifacts: [Artifact]
    ) {
        self.schemaVersion = schemaVersion
        self.fixtureKind = fixtureKind
        self.capture = capture
        self.requirements = requirements
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureKind = "fixture_kind"
        case capture, requirements, artifacts
    }

    public struct Capture: Codable, Equatable, Sendable {
        public let status: Status
        public let capturedAt: String?
        public let origin: String
        public let serviceVersion: String
        public let environmentBoundary: String
        public let sanctionedTestIdentity: Bool
        public let sanctionedTestMesh: Bool
        public let retainedSensitiveValues: Bool

        public init(
            status: Status,
            capturedAt: String?,
            origin: String,
            serviceVersion: String,
            environmentBoundary: String,
            sanctionedTestIdentity: Bool,
            sanctionedTestMesh: Bool,
            retainedSensitiveValues: Bool
        ) {
            self.status = status
            self.capturedAt = capturedAt
            self.origin = origin
            self.serviceVersion = serviceVersion
            self.environmentBoundary = environmentBoundary
            self.sanctionedTestIdentity = sanctionedTestIdentity
            self.sanctionedTestMesh = sanctionedTestMesh
            self.retainedSensitiveValues = retainedSensitiveValues
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case capturedAt = "captured_at"
            case origin
            case serviceVersion = "service_version"
            case environmentBoundary = "environment_boundary"
            case sanctionedTestIdentity = "sanctioned_test_identity"
            case sanctionedTestMesh = "sanctioned_test_mesh"
            case retainedSensitiveValues = "retained_sensitive_values"
        }

        public enum Status: String, Codable, Sendable {
            case notCaptured = "not_captured"
            case captured
        }
    }

    public struct RequirementEvidence: Codable, Equatable, Sendable {
        public let requirement: Requirement
        public let status: Status
        public let artifactIDs: [String]

        public init(requirement: Requirement, status: Status, artifactIDs: [String]) {
            self.requirement = requirement
            self.status = status
            self.artifactIDs = artifactIDs
        }

        private enum CodingKeys: String, CodingKey {
            case requirement, status
            case artifactIDs = "artifact_ids"
        }
    }

    public struct Artifact: Codable, Equatable, Sendable {
        public let id: String
        public let relativePath: String
        public let mediaType: String
        public let byteCount: Int
        public let sha256: String
        public let sanitized: Bool

        public init(
            id: String,
            relativePath: String,
            mediaType: String,
            byteCount: Int,
            sha256: String,
            sanitized: Bool
        ) {
            self.id = id
            self.relativePath = relativePath
            self.mediaType = mediaType
            self.byteCount = byteCount
            self.sha256 = sha256
            self.sanitized = sanitized
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case relativePath = "relative_path"
            case mediaType = "media_type"
            case byteCount = "byte_count"
            case sha256, sanitized
        }
    }

    /// Every boundary needed to qualify the read-only Mesh provider against a private coordinator.
    public enum Requirement: String, Codable, CaseIterable, Sendable {
        case credentialUserBearerBoundary = "credential_user_bearer_boundary"
        case testMeshIdentityMembership = "test_mesh_identity_membership"
        case devicesResponse = "devices_response"
        case topologyResponse = "topology_response"
        case eventsResponse = "events_response"
        case partialFreshnessProvenance = "partial_freshness_provenance"
        case authenticationErrors = "authentication_errors"
        case authorizationErrors = "authorization_errors"
        case cancellationBehavior = "cancellation_behavior"
        case networkErrorBehavior = "network_error_behavior"
    }

    public enum Status: String, Codable, Sendable {
        case missing
        case captured
    }
}

/// Validates a Mesh evidence bundle entirely from bounded local files beside its manifest.
public struct MeshEvidenceValidator: Sendable {
    public enum Mode: Sendable {
        /// Validates safety, integrity, and truthful captured/missing state.
        case audit
        /// Also requires every current read-only private coordinator boundary.
        case qualifyPrivateCoordinator
    }

    public struct Result: Equatable, Sendable {
        public let captured: Set<MeshEvidenceManifest.Requirement>
        public let missing: Set<MeshEvidenceManifest.Requirement>
        public let artifactCount: Int
        public let totalArtifactBytes: Int

        public init(
            captured: Set<MeshEvidenceManifest.Requirement>,
            missing: Set<MeshEvidenceManifest.Requirement>,
            artifactCount: Int,
            totalArtifactBytes: Int
        ) {
            self.captured = captured
            self.missing = missing
            self.artifactCount = artifactCount
            self.totalArtifactBytes = totalArtifactBytes
        }
    }

    public let maximumManifestBytes: Int
    public let maximumArtifactBytes: Int
    public let maximumTotalArtifactBytes: Int

    public init(
        maximumManifestBytes: Int = 262_144,
        maximumArtifactBytes: Int = 1_048_576,
        maximumTotalArtifactBytes: Int = 8_388_608
    ) {
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumArtifactBytes = maximumArtifactBytes
        self.maximumTotalArtifactBytes = maximumTotalArtifactBytes
    }

    public func validate(manifestURL: URL, mode: Mode) throws -> Result {
        let fileManager = FileManager.default
        guard !isSymbolicLink(manifestURL, fileManager: fileManager) else {
            throw MeshEvidenceValidationError.symbolicLinkRejected(artifactID: "manifest")
        }

        let manifestData = try boundedData(
            at: manifestURL,
            limit: maximumManifestBytes,
            artifactID: "manifest"
        )
        try rejectSensitiveContent(
            in: manifestData,
            mediaType: "application/json",
            artifactID: "manifest"
        )

        let manifest: MeshEvidenceManifest
        do {
            manifest = try JSONDecoder().decode(MeshEvidenceManifest.self, from: manifestData)
        } catch {
            throw MeshEvidenceValidationError.invalidManifest
        }
        try validateMetadata(manifest)

        let required = Set(MeshEvidenceManifest.Requirement.allCases)
        let supplied = Set(manifest.requirements.map(\.requirement))
        guard manifest.requirements.count == supplied.count, supplied == required else {
            throw MeshEvidenceValidationError.invalidRequirementSet
        }
        if manifest.capture.status == .notCaptured,
           manifest.requirements.contains(where: { $0.status == .captured }) {
            throw MeshEvidenceValidationError.invalidCaptureMetadata
        }

        let artifactIDs = Set(manifest.artifacts.map(\.id))
        guard artifactIDs.count == manifest.artifacts.count,
              manifest.artifacts.allSatisfy({ Self.isSafeArtifactID($0.id) }) else {
            throw MeshEvidenceValidationError.duplicateOrEmptyArtifactID
        }
        guard Set(manifest.artifacts.map(\.relativePath)).count == manifest.artifacts.count else {
            throw MeshEvidenceValidationError.duplicateArtifactPath
        }

        let references = manifest.requirements.flatMap(\.artifactIDs)
        let referencedIDs = Set(references)
        guard referencedIDs == artifactIDs else {
            throw MeshEvidenceValidationError.artifactReferenceMismatch
        }
        guard references.count == referencedIDs.count else {
            throw MeshEvidenceValidationError.artifactReferencedMoreThanOnce
        }
        for evidence in manifest.requirements {
            switch evidence.status {
            case .missing where !evidence.artifactIDs.isEmpty:
                throw MeshEvidenceValidationError.missingRequirementHasArtifacts(evidence.requirement)
            case .captured where evidence.artifactIDs.isEmpty:
                throw MeshEvidenceValidationError.capturedRequirementHasNoArtifacts(evidence.requirement)
            default:
                break
            }
        }

        // The manifest directory is the sole artifact root. Reject traversal and every
        // symlink component before reading so artifacts cannot redirect outside it.
        let declaredRootURL = manifestURL.deletingLastPathComponent().standardizedFileURL
        guard !isSymbolicLink(declaredRootURL, fileManager: fileManager) else {
            throw MeshEvidenceValidationError.symbolicLinkRejected(artifactID: "manifest")
        }
        let rootURL = declaredRootURL.resolvingSymlinksInPath()
        var totalBytes = 0
        for artifact in manifest.artifacts {
            let artifactURL = try confinedArtifactURL(
                relativePath: artifact.relativePath,
                rootURL: rootURL,
                fileManager: fileManager,
                artifactID: artifact.id
            )
            guard artifact.sanitized else {
                throw MeshEvidenceValidationError.unsanitizedArtifact(artifactID: artifact.id)
            }
            guard Self.allowedMediaTypes.contains(artifact.mediaType.lowercased()) else {
                throw MeshEvidenceValidationError.unsupportedMediaType(artifactID: artifact.id)
            }
            let data = try boundedData(
                at: artifactURL,
                limit: maximumArtifactBytes,
                artifactID: artifact.id
            )
            guard data.count == artifact.byteCount else {
                throw MeshEvidenceValidationError.byteCountMismatch(artifactID: artifact.id)
            }
            totalBytes = try addingWithoutOverflow(totalBytes, data.count)
            guard totalBytes <= maximumTotalArtifactBytes else {
                throw MeshEvidenceValidationError.totalArtifactBytesExceeded
            }
            guard artifact.sha256 == Self.sha256Hex(data) else {
                throw MeshEvidenceValidationError.digestMismatch(artifactID: artifact.id)
            }
            try rejectSensitiveContent(in: data, mediaType: artifact.mediaType, artifactID: artifact.id)
        }

        let captured = Set(
            manifest.requirements.lazy.filter { $0.status == .captured }.map(\.requirement)
        )
        let missing = required.subtracting(captured)
        if case .qualifyPrivateCoordinator = mode, !missing.isEmpty {
            throw MeshEvidenceValidationError.incompleteContract(missing: missing)
        }
        return Result(
            captured: captured,
            missing: missing,
            artifactCount: manifest.artifacts.count,
            totalArtifactBytes: totalBytes
        )
    }

    private func validateMetadata(_ manifest: MeshEvidenceManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.fixtureKind == "sanitized_authenticated_mesh_read_only_contract",
              !manifest.capture.retainedSensitiveValues,
              !manifest.capture.serviceVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let origin = URLComponents(string: manifest.capture.origin),
              origin.scheme == "https",
              origin.host != nil,
              origin.user == nil,
              origin.password == nil,
              origin.query == nil,
              origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/" else {
            throw MeshEvidenceValidationError.invalidCaptureMetadata
        }

        switch manifest.capture.status {
        case .notCaptured:
            guard manifest.capture.capturedAt == nil,
                  manifest.capture.environmentBoundary == "dedicated_non_production_required",
                  !manifest.capture.sanctionedTestIdentity,
                  !manifest.capture.sanctionedTestMesh else {
                throw MeshEvidenceValidationError.invalidCaptureMetadata
            }
        case .captured:
            guard let capturedAt = manifest.capture.capturedAt,
                  ISO8601DateFormatter().date(from: capturedAt) != nil,
                  manifest.capture.environmentBoundary == "dedicated_non_production",
                  manifest.capture.sanctionedTestIdentity,
                  manifest.capture.sanctionedTestMesh else {
                throw MeshEvidenceValidationError.invalidCaptureMetadata
            }
        }
    }

    private func confinedArtifactURL(
        relativePath: String,
        rootURL: URL,
        fileManager: FileManager,
        artifactID: String
    ) throws -> URL {
        let path = NSString(string: relativePath)
        let components = path.pathComponents
        guard !relativePath.isEmpty,
              !path.isAbsolutePath,
              !components.contains(".."),
              !components.contains("."),
              !components.contains("/") else {
            throw MeshEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw MeshEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }
        var cursor = rootURL
        for component in components {
            cursor.appendPathComponent(component)
            if isSymbolicLink(cursor, fileManager: fileManager) {
                throw MeshEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
            }
        }
        guard candidate.resolvingSymlinksInPath().path == candidate.path else {
            throw MeshEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
        }
        return candidate
    }

    private func boundedData(at url: URL, limit: Int, artifactID: String) throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw MeshEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MeshEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else {
            throw MeshEvidenceValidationError.artifactTooLarge(artifactID: artifactID)
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw MeshEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
    }

    private func rejectSensitiveContent(in data: Data, mediaType: String, artifactID: String) throws {
        guard let text = String(data: data, encoding: .utf8),
              text.unicodeScalars.allSatisfy({ scalar in
                  [0x09, 0x0A, 0x0D].contains(scalar.value) || scalar.value >= 0x20
              }) else {
            throw MeshEvidenceValidationError.nonTextArtifact(artifactID: artifactID)
        }

        let patterns = [
            #"(?im)^\s*authorization\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?im)^\s*(cookie|set-cookie|x-api-key)\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            // Captured mesh, device, event, and membership UUIDs must be replaced
            // with the documented all-zero synthetic namespace before retention.
            #"(?i)\b(?!00000000-0000-0000-0000-)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
        ]
        for pattern in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            throw MeshEvidenceValidationError.potentialSecret(artifactID: artifactID)
        }

        if mediaType.lowercased() == "application/json" {
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw MeshEvidenceValidationError.invalidJSONArtifact(artifactID: artifactID)
            }
            if containsSensitiveJSONValue(object) {
                throw MeshEvidenceValidationError.potentialSecret(artifactID: artifactID)
            }
        }
    }

    private func containsSensitiveJSONValue(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased().replacingOccurrences(of: "-", with: "_")
                if Self.sensitiveJSONKeys.contains(normalizedKey),
                   let stringValue = nestedValue as? String,
                   !Self.redactionValues.contains(stringValue.lowercased()) {
                    return true
                }
                if containsSensitiveJSONValue(nestedValue) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsSensitiveJSONValue)
        }
        return false
    }

    private func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw MeshEvidenceValidationError.totalArtifactBytesExceeded
        }
        return result.partialValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeArtifactID(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count),
              let expression = try? NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9._-]*$"#) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, options: [], range: range)?.range == range
    }

    private static let allowedMediaTypes: Set<String> = [
        "application/json", "application/x-ndjson", "text/plain",
    ]
    private static let sensitiveJSONKeys: Set<String> = [
        "access_token", "api_key", "authorization", "cookie", "email", "password",
        "refresh_token", "secret", "session_id", "set_cookie", "token", "user_id",
        "x_api_key",
    ]
    private static let redactionValues: Set<String> = [
        "", "<redacted>", "[redacted]", "redacted", "<omitted>", "[omitted]",
    ]
}

/// Stable failures that never echo manifest or artifact contents.
public enum MeshEvidenceValidationError: Error, Equatable, Sendable {
    case unreadableArtifact(artifactID: String)
    case artifactTooLarge(artifactID: String)
    case invalidManifest
    case invalidCaptureMetadata
    case invalidRequirementSet
    case duplicateOrEmptyArtifactID
    case artifactReferenceMismatch
    case artifactReferencedMoreThanOnce
    case duplicateArtifactPath
    case missingRequirementHasArtifacts(MeshEvidenceManifest.Requirement)
    case capturedRequirementHasNoArtifacts(MeshEvidenceManifest.Requirement)
    case unsafeArtifactPath(artifactID: String)
    case symbolicLinkRejected(artifactID: String)
    case unsanitizedArtifact(artifactID: String)
    case unsupportedMediaType(artifactID: String)
    case byteCountMismatch(artifactID: String)
    case totalArtifactBytesExceeded
    case digestMismatch(artifactID: String)
    case nonTextArtifact(artifactID: String)
    case invalidJSONArtifact(artifactID: String)
    case potentialSecret(artifactID: String)
    case incompleteContract(missing: Set<MeshEvidenceManifest.Requirement>)
}
