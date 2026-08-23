import CryptoKit
import Foundation

/// A sanitized, offline-verifiable record of one authenticated Open WebUI contract capture.
public struct OpenWebUIEvidenceManifest: Codable, Equatable, Sendable {
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
        public let serverVersion: String
        public let accountBoundary: String
        public let syntheticPrompt: Bool
        public let retainedSensitiveValues: Bool

        public init(
            status: Status,
            capturedAt: String?,
            origin: String,
            serverVersion: String,
            accountBoundary: String,
            syntheticPrompt: Bool,
            retainedSensitiveValues: Bool
        ) {
            self.status = status
            self.capturedAt = capturedAt
            self.origin = origin
            self.serverVersion = serverVersion
            self.accountBoundary = accountBoundary
            self.syntheticPrompt = syntheticPrompt
            self.retainedSensitiveValues = retainedSensitiveValues
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case capturedAt = "captured_at"
            case origin
            case serverVersion = "server_version"
            case accountBoundary = "account_boundary"
            case syntheticPrompt = "synthetic_prompt"
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

    public enum Requirement: String, Codable, CaseIterable, Sendable {
        case credentialLifecycle = "credential_lifecycle"
        case nonStreamingRequest = "non_streaming_request"
        case nonStreamingResponse = "non_streaming_response"
        case streamingTransport = "streaming_transport"
        case streamingFrames = "streaming_frames"
        case cancellation
        case errorResponses = "error_responses"
        case durableHistory = "durable_history"
        case sourceCitations = "source_citations"
    }

    public enum Status: String, Codable, Sendable {
        case missing
        case captured
    }
}

/// Validates sanitized contract evidence without contacting Open WebUI.
public struct OpenWebUIEvidenceValidator: Sendable {
    public enum Mode: Sendable {
        /// Confirms that the manifest truthfully and safely represents its current state.
        case audit
        /// Additionally requires every native-chat contract element to be captured.
        case qualifyNativeChat
    }

    public struct Result: Equatable, Sendable {
        public let captured: Set<OpenWebUIEvidenceManifest.Requirement>
        public let missing: Set<OpenWebUIEvidenceManifest.Requirement>
        public let artifactCount: Int
        public let totalArtifactBytes: Int

        public init(
            captured: Set<OpenWebUIEvidenceManifest.Requirement>,
            missing: Set<OpenWebUIEvidenceManifest.Requirement>,
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
            throw OpenWebUIEvidenceValidationError.symbolicLinkRejected(artifactID: "manifest")
        }

        let manifestData = try boundedData(
            at: manifestURL,
            limit: maximumManifestBytes,
            artifactID: "manifest"
        )
        try rejectSensitiveContent(in: manifestData, mediaType: "application/json", artifactID: "manifest")

        let manifest: OpenWebUIEvidenceManifest
        do {
            manifest = try JSONDecoder().decode(OpenWebUIEvidenceManifest.self, from: manifestData)
        } catch {
            throw OpenWebUIEvidenceValidationError.invalidManifest
        }
        try validateMetadata(manifest)

        let requirementSet = Set(manifest.requirements.map(\.requirement))
        guard manifest.requirements.count == requirementSet.count,
              requirementSet == Set(OpenWebUIEvidenceManifest.Requirement.allCases) else {
            throw OpenWebUIEvidenceValidationError.invalidRequirementSet
        }

        if manifest.capture.status == .notCaptured,
           manifest.requirements.contains(where: { $0.status == .captured }) {
            throw OpenWebUIEvidenceValidationError.invalidCaptureMetadata
        }

        let artifactIDs = Set(manifest.artifacts.map(\.id))
        guard manifest.artifacts.count == artifactIDs.count,
              manifest.artifacts.allSatisfy({ !$0.id.isEmpty }) else {
            throw OpenWebUIEvidenceValidationError.duplicateOrEmptyArtifactID
        }

        let artifactReferences = manifest.requirements.flatMap(\.artifactIDs)
        let referencedIDs = Set(artifactReferences)
        guard referencedIDs == artifactIDs else {
            throw OpenWebUIEvidenceValidationError.artifactReferenceMismatch
        }
        guard artifactReferences.count == referencedIDs.count else {
            throw OpenWebUIEvidenceValidationError.artifactReferencedMoreThanOnce
        }
        guard Set(manifest.artifacts.map(\.relativePath)).count == manifest.artifacts.count else {
            throw OpenWebUIEvidenceValidationError.duplicateArtifactPath
        }

        for evidence in manifest.requirements {
            switch evidence.status {
            case .missing where !evidence.artifactIDs.isEmpty:
                throw OpenWebUIEvidenceValidationError.missingRequirementHasArtifacts(evidence.requirement)
            case .captured where evidence.artifactIDs.isEmpty:
                throw OpenWebUIEvidenceValidationError.capturedRequirementHasNoArtifacts(evidence.requirement)
            default:
                break
            }
        }

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
                throw OpenWebUIEvidenceValidationError.unsanitizedArtifact(artifactID: artifact.id)
            }
            guard Self.allowedMediaTypes.contains(artifact.mediaType.lowercased()) else {
                throw OpenWebUIEvidenceValidationError.unsupportedMediaType(artifactID: artifact.id)
            }
            let data = try boundedData(
                at: artifactURL,
                limit: maximumArtifactBytes,
                artifactID: artifact.id
            )
            guard data.count == artifact.byteCount else {
                throw OpenWebUIEvidenceValidationError.byteCountMismatch(artifactID: artifact.id)
            }
            totalBytes = try addingWithoutOverflow(totalBytes, data.count)
            guard totalBytes <= maximumTotalArtifactBytes else {
                throw OpenWebUIEvidenceValidationError.totalArtifactBytesExceeded
            }
            guard artifact.sha256 == Self.sha256Hex(data) else {
                throw OpenWebUIEvidenceValidationError.digestMismatch(artifactID: artifact.id)
            }
            try rejectSensitiveContent(in: data, mediaType: artifact.mediaType, artifactID: artifact.id)
        }

        let captured = Set(
            manifest.requirements.lazy
                .filter { $0.status == .captured }
                .map(\.requirement)
        )
        let missing = Set(OpenWebUIEvidenceManifest.Requirement.allCases).subtracting(captured)
        if case .qualifyNativeChat = mode, !missing.isEmpty {
            throw OpenWebUIEvidenceValidationError.incompleteContract(missing: missing)
        }
        return Result(
            captured: captured,
            missing: missing,
            artifactCount: manifest.artifacts.count,
            totalArtifactBytes: totalBytes
        )
    }

    private func validateMetadata(_ manifest: OpenWebUIEvidenceManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.fixtureKind == "sanitized_authenticated_openwebui_chat_contract",
              !manifest.capture.retainedSensitiveValues,
              !manifest.capture.serverVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let origin = URLComponents(string: manifest.capture.origin),
              origin.scheme == "https",
              origin.host != nil,
              origin.user == nil,
              origin.password == nil,
              origin.query == nil,
              origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/" else {
            throw OpenWebUIEvidenceValidationError.invalidCaptureMetadata
        }

        switch manifest.capture.status {
        case .notCaptured:
            guard manifest.capture.capturedAt == nil,
                  manifest.capture.accountBoundary == "dedicated_non_production_required",
                  !manifest.capture.syntheticPrompt else {
                throw OpenWebUIEvidenceValidationError.invalidCaptureMetadata
            }
        case .captured:
            guard let capturedAt = manifest.capture.capturedAt,
                  ISO8601DateFormatter().date(from: capturedAt) != nil,
                  manifest.capture.accountBoundary == "dedicated_non_production",
                  manifest.capture.syntheticPrompt else {
                throw OpenWebUIEvidenceValidationError.invalidCaptureMetadata
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
            throw OpenWebUIEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw OpenWebUIEvidenceValidationError.unsafeArtifactPath(artifactID: artifactID)
        }

        var cursor = rootURL
        for component in components {
            cursor.appendPathComponent(component)
            if isSymbolicLink(cursor, fileManager: fileManager) {
                throw OpenWebUIEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
            }
        }
        guard candidate.resolvingSymlinksInPath().path == candidate.path else {
            throw OpenWebUIEvidenceValidationError.symbolicLinkRejected(artifactID: artifactID)
        }
        return candidate
    }

    private func boundedData(at url: URL, limit: Int, artifactID: String) throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw OpenWebUIEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw OpenWebUIEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else {
            throw OpenWebUIEvidenceValidationError.artifactTooLarge(artifactID: artifactID)
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw OpenWebUIEvidenceValidationError.unreadableArtifact(artifactID: artifactID)
        }
    }

    private func rejectSensitiveContent(in data: Data, mediaType: String, artifactID: String) throws {
        guard let text = String(data: data, encoding: .utf8),
              text.unicodeScalars.allSatisfy({ scalar in
                  [0x09, 0x0A, 0x0D].contains(scalar.value) || scalar.value >= 0x20
              }) else {
            throw OpenWebUIEvidenceValidationError.nonTextArtifact(artifactID: artifactID)
        }

        let patterns = [
            #"(?im)^\s*authorization\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?im)^\s*(cookie|set-cookie)\s*:\s*(?!<redacted>|\[redacted\])\S+"#,
            #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
        ]
        for pattern in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            throw OpenWebUIEvidenceValidationError.potentialSecret(artifactID: artifactID)
        }

        if mediaType.lowercased() == "application/json" {
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw OpenWebUIEvidenceValidationError.invalidJSONArtifact(artifactID: artifactID)
            }
            if containsSensitiveJSONValue(object) {
                throw OpenWebUIEvidenceValidationError.potentialSecret(artifactID: artifactID)
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
                if containsSensitiveJSONValue(nestedValue) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsSensitiveJSONValue)
        }
        return false
    }

    private func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw OpenWebUIEvidenceValidationError.totalArtifactBytesExceeded
        }
        return result.partialValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let allowedMediaTypes: Set<String> = [
        "application/json",
        "application/x-ndjson",
        "text/event-stream",
        "text/plain",
    ]

    private static let sensitiveJSONKeys: Set<String> = [
        "api_key", "authorization", "cookie", "password", "refresh_token",
        "secret", "set_cookie", "token", "access_token",
    ]

    private static let redactionValues: Set<String> = [
        "", "<redacted>", "[redacted]", "redacted", "<omitted>", "[omitted]",
    ]
}

/// Stable validation failures that never include evidence body contents.
public enum OpenWebUIEvidenceValidationError: Error, Equatable, Sendable {
    case unreadableArtifact(artifactID: String)
    case artifactTooLarge(artifactID: String)
    case invalidManifest
    case invalidCaptureMetadata
    case invalidRequirementSet
    case duplicateOrEmptyArtifactID
    case artifactReferenceMismatch
    case artifactReferencedMoreThanOnce
    case duplicateArtifactPath
    case missingRequirementHasArtifacts(OpenWebUIEvidenceManifest.Requirement)
    case capturedRequirementHasNoArtifacts(OpenWebUIEvidenceManifest.Requirement)
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
    case incompleteContract(missing: Set<OpenWebUIEvidenceManifest.Requirement>)
}
