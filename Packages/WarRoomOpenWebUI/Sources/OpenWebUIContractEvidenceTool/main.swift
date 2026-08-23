import Foundation
import OpenWebUIContractEvidence

private enum Command: String {
    case audit
    case qualify
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let command = Command(rawValue: arguments[1]) else {
    writeError("usage: openwebui-contract-evidence <audit|qualify> <manifest.json>")
    exit(64)
}

let manifestURL = URL(fileURLWithPath: arguments[2])
let mode: OpenWebUIEvidenceValidator.Mode = command == .audit ? .audit : .qualifyNativeChat

do {
    let result = try OpenWebUIEvidenceValidator().validate(manifestURL: manifestURL, mode: mode)
    let missing = result.missing.map(\.rawValue).sorted().joined(separator: ",")
    print(
        "valid mode=\(command.rawValue) captured=\(result.captured.count) "
            + "missing=\(result.missing.count) artifacts=\(result.artifactCount) "
            + "bytes=\(result.totalArtifactBytes) missing_ids=\(missing.isEmpty ? "none" : missing)"
    )
} catch let error as OpenWebUIEvidenceValidationError {
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
