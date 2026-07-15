import Crypto
import Foundation

/// Pinned Ed25519 trust anchors for rulebook signature verification.
///
/// The public key is embedded in code — never loaded from next to the payload.
/// Private key lives only in the maintainer keychain / password manager (see
/// RULEBOOK_INTEGRATION.md §Signing).
public enum RulebookTrust {
    /// Key id carried by the detached signature envelope.
    public static let currentKeyID = "wharfside-rulebook-2026-01"

    /// Base64 (raw 32-byte) Ed25519 public key for `currentKeyID`.
    /// Created 2026-07-13 for Wharfside 0.1.1 rulebook signing.
    private static let currentPublicKeyBase64 = "nhk3szfuwlFSruiGONM9pUTCyRroqvqNT9LUNK8D91M="

    public static var trustedKeys: [String: Curve25519.Signing.PublicKey] {
        [currentKeyID: currentPublicKey]
    }

    public static var currentPublicKey: Curve25519.Signing.PublicKey {
        guard let data = Data(base64Encoded: currentPublicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
            preconditionFailure("RulebookTrust: embedded public key is corrupt")
        }
        return key
    }
}
