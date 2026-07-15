import Crypto
import Foundation

/// Detached signature envelope for a rulebook document (`Rulebook.json.sig`).
///
/// The signed message is the exact byte contents of `Rulebook.json` (no
/// canonicalization). Verification happens before any JSON decode of the document.
public struct RulebookSignatureEnvelope: Codable, Sendable, Equatable {
    public let keyId: String
    /// Base64-encoded raw Ed25519 signature (64 bytes).
    public let signature: String

    public init(keyId: String, signature: String) {
        self.keyId = keyId
        self.signature = signature
    }

    public var signatureData: Data? {
        Data(base64Encoded: signature)
    }

    /// Build a detached envelope for `document` (exact file bytes).
    public static func sign(
        document: Data,
        privateKey: Curve25519.Signing.PrivateKey,
        keyId: String = RulebookTrust.currentKeyID
    ) throws -> RulebookSignatureEnvelope {
        let signature = try privateKey.signature(for: document)
        return RulebookSignatureEnvelope(
            keyId: keyId,
            signature: signature.base64EncodedString()
        )
    }
}
