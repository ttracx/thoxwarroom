import Foundation
import MeshContractEvidence

private enum Command: String {
    case audit
    case qualify
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let command = Command(rawValue: arguments[1]) else {
    writeError("usage: mesh-contract-evidence <audit|qualify> <manifest.json>")
    exit(64)
}

let manifestURL = URL(fileURLWithPath: arguments[2])
let mode: MeshEvidenceValidator.Mode = command == .audit ? .audit : .qualifyPrivateCoordinator

do {
    let result = try MeshEvidenceValidator().validate(manifestURL: manifestURL, mode: mode)
    let missing = result.missing.map(\.rawValue).sorted().joined(separator: ",")
    let missingIDs = missing.isEmpty ? "none" : missing
    print(
        "valid mode=\(command.rawValue) captured=\(result.captured.count) "
            + "missing=\(result.missing.count) artifacts=\(result.artifactCount) "
            + "bytes=\(result.totalArtifactBytes) missing_ids=\(missingIDs)"
    )
} catch let error as MeshEvidenceValidationError {
    if case let .incompleteContract(missing) = error {
        writeError(
            "invalid evidence: incomplete_contract missing_ids="
                + missing.map(\.rawValue).sorted().joined(separator: ",")
        )
    } else {
        writeError("invalid evidence: \(String(describing: error))")
    }
    exit(2)
} catch {
    writeError("invalid evidence: unexpected local validation failure")
    exit(2)
}
