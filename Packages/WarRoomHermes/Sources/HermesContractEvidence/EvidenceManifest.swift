import CryptoKit
import Foundation

/// A sanitized, offline-verifiable record of one authenticated Hermes API contract capture.
public struct HermesEvidenceManifest: Codable, Equatable, Sendable {
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
        public let syntheticRun: Bool
        public let retainedSensitiveValues: Bool

        public init(
            status: Status,
            capturedAt: String?,
            origin: String,
            serviceVersion: String,
            environmentBoundary: String,
            syntheticRun: Bool,
            retainedSensitiveValues: Bool
        ) {
            self.status = status
            self.capturedAt = capturedAt
            self.origin = origin
            self.serviceVersion = serviceVersion
            self.environmentBoundary = environmentBoundary
            self.syntheticRun = syntheticRun
            self.retainedSensitiveValues = retainedSensitiveValues
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case capturedAt = "captured_at"
            case origin
            case serviceVersion = "service_version"
            case environmentBoundary = "environment_boundary"
            case syntheticRun = "synthetic_run"
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

    /// The exact read-only and mutation contract boundaries exposed by the current Hermes client.
    /// This validator records evidence only; it performs no network request or mutation.
    public enum Requirement: String, Codable, CaseIterable, Sendable {
        case credentialBoundary = "credential_boundary"
        case capabilitiesResponse = "capabilities_response"
        case runSubmissionRequest = "run_submission_request"
        case runSubmissionResponse = "run_submission_response"
        case runStatusResponse = "run_status_response"
        case eventStreamTransport = "event_stream_transport"
        case eventStreamFrames = "event_stream_frames"
        case approvalRequestResponse = "approval_request_response"
        case stopRequestResponse = "stop_request_response"
        case cancellationBehavior = "cancellation_behavior"
        case errorResponses = "error_responses"
    }

    public enum Status: String, Codable, Sendable {
        case missing
        case captured
    }
}

/// Validates a Hermes evidence bundle entirely from local files rooted beside its manifest.
public struct HermesEvidenceValidator: Sendable {
    public enum Mode: Sendable {
        /// Validates safety, integrity, and truthful captured/missing state.
        case audit
        /// Also requires every current Hermes contract boundary to be captured.
        case qualifyPrivateAPI
    }

    public struct Result: Equatable, Sendable {
        public let captured: Set<HermesEvidenceManifest.Requirement>
        public let missing: Set<HermesEvidenceManifest.Requirement>
        public let artifactCount: Int
        public let totalArtifactBytes: Int

        public init(
            captured: Set<HermesEvidenceManifest.Requirement>,
            missing: Set<HermesEvidenceManifest.Requirement>,
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
            throw HermesEvidenceValidationError.symbolicLinkRejected(artifactID: "manifest")
        }

        let manifestData = try boundedData(
            at: manifestURL,
            limit: maximumManifestBytes,
            artifactID: "manifest"
        )
        try rejectSensitiveContent(in: manifestData, mediaType: "application/json", artifactID: "manifest")

        let manifest: HermesEvidenceManifest
        do {
            manifest = try JSONDecoder().decode(HermesEvidenceManifest.self, from: manifestData)
        } catch {
            throw HermesEvidenceValidationError.invalidManifest
        }
        try validateMetadata(manifest)

        let required = Set(HermesEvidenceManifest.Requirement.allCases)
        let requirementSet = Set(manifest.requirements.map(\.requirement))
        guard manifest.requirements.count == requirementSet.count, requirementSet == required else {
            throw HermesEvidenceValidationError.invalidRequirementSet
        }
        if manifest.capture.status == .notCaptured,
           manifest.requirements.contains(where: { $0.status == .captured }) {
            throw HermesEvidenceValidationError.invalidCaptureMetadata
        }

        let artifactIDs = Set(manifest.artifacts.map(\.id))
        guard artifactIDs.count == manifest.artifacts.count,
              manifest.artifacts.allSatisfy({ !$0.id.isEmpty }) else {
            throw HermesEvidenceValidationError.duplicateOrEmptyArtifactID
        }
        guard Set(manifest.artifacts.map(\.relativePath)).count == manifest.artifacts.count else {
            throw HermesEvidenceValidationError.duplicateArtifactPath
        }

        let references = manifest.requirements.flatMap(\.artifactIDs)
        let referencedIDs = Set(references)
        guard referencedIDs == artifactIDs else {
            throw HermesEvidenceValidationError.artifactReferenceMismatch
        }
        guard references.count == referencedIDs.count else {
            throw HermesEvidenceValidationError.artifactReferencedMoreThanOnce
        }

        for evidence in manifest.requirements {
            switch evidence.status {
            case .missing where !evidence.artifactIDs.isEmpty:
                throw HermesEvidenceValidationError.missingRequirementHasArtifacts(evidence.requirement)
            case .captured where evidence.artifactIDs.isEmpty:
                throw HermesEvidenceValidationError.capturedRequirementHasNoArtifacts(evidence.requirement)
            default:
                break
            }
        }

        // The manifest's containing directory is the only artifact root. Every path component
        // is checked before reading so neither traversal nor a symlink can escape that root.
        let rootURL = manifestURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        var totalBytes = 0
        for artifact in manifest.artifacts {
            let artifactURL = try confinedArtifactURL(
                relativePath: artifact.relativePath,
                rootURL: rootURL,
                fileManager: fileManager,
                artifactID: artifact.id
            )
            guard artifact.sanitized else {
                throw HermesEvidenceValidationError.unsanitizedArtifact(artifactID: artifact.id)
            }
            guard Self.allowedMediaTypes.contains(artifact.mediaType.lowercased()) else {
                throw HermesEvidenceValidationError.unsupportedMediaType(artifactID: artifact.id)
            }
            let data = try boundedData(at: artifactURL, limit: maximumArtifactBytes, artifactID: artifact.id)
            guard data.count == artifact.byteCount else {
                throw HermesEvidenceValidationError.byteCountMismatch(artifactID: artifact.id)
            }
            totalBytes = try addingWithoutOverflow(totalBytes, data.count)
            guard totalBytes <= maximumTotalArtifactBytes else {
                throw HermesEvidenceValidationError.totalArtifactBytesExceeded
            }
            guard artifact.sha256 == Self.sha256Hex(data) else {
                throw HermesEvidenceValidationError.digestMismatch(artifactID: artifact.id)
            }
            try rejectSensitiveContent(in: data, mediaType: artifact.mediaType, artifactID: artifact.id)
        }

        let captured = Set(
            manifest.requirements.lazy.filter { $0.status == .captured }.map(\.requirement)
        )
        let missing = required.subtracting(captured)
        if case .qualifyPrivateAPI = mode, !missing.isEmpty {
            throw HermesEvidenceValidationError.incompleteContract(missing: missing)
        }
        return Result(
            captured: captured,
            missing: missing,
            artifactCount: manifest.artifacts.count,
            totalArtifactBytes: totalBytes
        )
    }

    private func validateMetadata(_ manifest: HermesEvidenceManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.fixtureKind == "sanitized_authenticated_hermes_private_api_contract",
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
            throw HermesEvidenceValidationError.invalidCaptureMetadata
        }

        switch manifest.capture.status {
        case .notCaptured:
            guard manifest.capture.capturedAt == nil,
                  manifest.capture.environmentBoundary == "dedicated_non_production_required",
                  !manifest.capture.syntheticRun else {
                throw HermesEvidenceValidationError.invalidCaptureMetadata
            }
        case .captured:
            guard let capturedAt = manifest.capture.capturedAt,
                  ISO8601DateFormatter().date(from: capturedAt) != nil,
                  manifest.capture.environmentBoundary == "dedicated_non_production",
                  manifest.capture.syntheticRun else {
                throw HermesEvidenceValidationError.invalidCaptureMetadata
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
            throw HermesEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw HermesEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }
        var cursor = rootURL
        for component in components {
            cursor.appendPathComponent(component)
            if isSymbolicLink(cursor, fileManager: fileManager) {
                throw HermesEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
            }
        }
        guard candidate.resolvingSymlinksInPath().path == candidate.path else {
            throw HermesEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
        }
        return candidate
    }

    private func boundedData(at url: URL, limit: Int, artifactID: String) throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw HermesEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw HermesEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else {
            throw HermesEvidenceValidationError.artifactTooLarge(artifactID: artifactID)
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw HermesEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
    }

    private func rejectSensitiveContent(in data: Data, mediaType: String, artifactID: String) throws {
        guard let text = String(data: data, encoding: .utf8),
              text.unicodeScalars.allSatisfy({ scalar in
                  [0x09, 0x0A, 0x0D].contains(scalar.value) || scalar.value >= 0x20
              }) else {
            throw HermesEvidenceValidationError.nonTextArtifact(artifactID: artifactID)
        }

        let patterns = [
            #"(?im)^\s*authorization\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?im)^\s*(cookie|set-cookie|x-hermes-session-id|x-hermes-session-key|x-api-key)\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
        ]
        for pattern in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            throw HermesEvidenceValidationError.potentialSecret(artifactID: artifactID)
        }

        if mediaType.lowercased() == "application/json" {
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw HermesEvidenceValidationError.invalidJSONArtifact(artifactID: artifactID)
            }
            if containsSensitiveJSONValue(object) {
                throw HermesEvidenceValidationError.potentialSecret(artifactID: artifactID)
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
        guard !result.overflow else { throw HermesEvidenceValidationError.totalArtifactBytesExceeded }
        return result.partialValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let allowedMediaTypes: Set<String> = [
        "application/json", "application/x-ndjson", "text/event-stream", "text/plain",
    ]
    private static let sensitiveJSONKeys: Set<String> = [
        "access_token", "api_key", "authorization", "cookie", "password", "refresh_token",
        "secret", "session_id", "session_key", "set_cookie", "token",
        "x_api_key", "x_hermes_session_id", "x_hermes_session_key",
    ]
    private static let redactionValues: Set<String> = [
        "", "<redacted>", "[redacted]", "redacted", "<omitted>", "[omitted]",
    ]
}

/// Stable failures that do not echo manifest or artifact contents.
public enum HermesEvidenceValidationError: Error, Equatable, Sendable {
    case unreadableArtifact(artifactID: String)
    case artifactTooLarge(artifactID: String)
    case invalidManifest
    case invalidCaptureMetadata
    case invalidRequirementSet
    case duplicateOrEmptyArtifactID
    case artifactReferenceMismatch
    case artifactReferencedMoreThanOnce
    case duplicateArtifactPath
    case missingRequirementHasArtifacts(HermesEvidenceManifest.Requirement)
    case capturedRequirementHasNoArtifacts(HermesEvidenceManifest.Requirement)
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
    case incompleteContract(missing: Set<HermesEvidenceManifest.Requirement>)
}
