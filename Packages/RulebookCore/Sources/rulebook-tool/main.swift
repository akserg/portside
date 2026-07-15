import Crypto
import Foundation
import RulebookCore

@main
enum RulebookTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsageAndExit()
        }
        switch command {
        case "generate-key":
            try generateKey(args: Array(args.dropFirst()))
        case "sign":
            try sign(args: Array(args.dropFirst()))
        case "verify":
            try verify(args: Array(args.dropFirst()))
        default:
            printUsageAndExit()
        }
    }

    private static func printUsageAndExit() -> Never {
        // FileHandle avoids Linux Swift 6 `stderr` shared-mutable-state errors.
        let usage = Data("""
            usage:
              rulebook-tool generate-key --out-dir <dir>
              rulebook-tool sign --key <private.b64> --document <Rulebook.json> --out <Rulebook.json.sig>
              rulebook-tool verify --document <Rulebook.json> --sig <Rulebook.json.sig>

            """.utf8)
        try? FileHandle.standardError.write(contentsOf: usage)
        exit(2)
    }

    private static func generateKey(args: [String]) throws {
        let outDir = try requiredValue("--out-dir", in: args)
        try FileManager.default.createDirectory(
            atPath: outDir,
            withIntermediateDirectories: true
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let privateURL = URL(fileURLWithPath: outDir)
            .appendingPathComponent("\(RulebookTrust.currentKeyID).private.b64")
        let publicURL = URL(fileURLWithPath: outDir)
            .appendingPathComponent("\(RulebookTrust.currentKeyID).public.b64")
        try privateKey.rawRepresentation.base64EncodedString()
            .write(to: privateURL, atomically: true, encoding: .utf8)
        try privateKey.publicKey.rawRepresentation.base64EncodedString()
            .write(to: publicURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: privateURL.path
        )
        print("Wrote \(privateURL.path)")
        print("Wrote \(publicURL.path)")
        print("Embed public key in RulebookTrust.currentPublicKeyBase64:")
        print(privateKey.publicKey.rawRepresentation.base64EncodedString())
    }

    private static func sign(args: [String]) throws {
        let keyPath = try requiredValue("--key", in: args)
        let documentPath = try requiredValue("--document", in: args)
        let outPath = try requiredValue("--out", in: args)

        let keyB64 = try String(contentsOfFile: keyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyData = Data(base64Encoded: keyB64) else {
            throw ToolError.invalidBase64("private key")
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        let document = try Data(contentsOf: URL(fileURLWithPath: documentPath))
        let signature = try privateKey.signature(for: document)
        let envelope = RulebookSignatureEnvelope(
            keyId: RulebookTrust.currentKeyID,
            signature: signature.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(envelope)
        try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
        print("Signed \(documentPath) → \(outPath)")
    }

    private static func verify(args: [String]) throws {
        let documentPath = try requiredValue("--document", in: args)
        let sigPath = try requiredValue("--sig", in: args)
        let document = try Data(contentsOf: URL(fileURLWithPath: documentPath))
        let envelopeData = try Data(contentsOf: URL(fileURLWithPath: sigPath))
        let envelope = try JSONDecoder().decode(RulebookSignatureEnvelope.self, from: envelopeData)
        let rulebook = try RulebookLoader.loadVerified(document: document, envelope: envelope)
        print("OK \(rulebook.version) keyId=\(envelope.keyId)")
    }

    private static func requiredValue(_ flag: String, in args: [String]) throws -> String {
        guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else {
            throw ToolError.missingFlag(flag)
        }
        return args[args.index(after: index)]
    }
}

private enum ToolError: Error, CustomStringConvertible {
    case missingFlag(String)
    case invalidBase64(String)

    var description: String {
        switch self {
        case .missingFlag(let flag): "missing \(flag)"
        case .invalidBase64(let label): "invalid base64 for \(label)"
        }
    }
}
