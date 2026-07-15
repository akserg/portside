import Crypto
import Foundation
import RulebookCore

/// Loads and evaluates the active rulebook with fail-closed fallback to seed rules.
public struct RulebookPipeline: Sendable {
    public let rulebook: Rulebook
    public let source: RulebookSource
    /// Set when `source == .fallback`; nil on a verified bundled load.
    public let fallbackReason: FallbackReason?

    public enum RulebookSource: String, Sendable, Equatable {
        case bundled
        case fallback
    }

    /// Distinct observability tags; diagnosis behavior is identical for all reasons.
    public enum FallbackReason: String, Sendable, Equatable {
        case missing
        case malformed
        case signatureInvalid
    }

    public init(
        rulebook: Rulebook,
        source: RulebookSource,
        fallbackReason: FallbackReason? = nil
    ) {
        self.rulebook = rulebook
        self.source = source
        self.fallbackReason = fallbackReason
    }

    /// Bundled document + detached signature envelope, or `nil` data to fall back.
    ///
    /// Verify-before-decode: signature must validate against a pinned public key
    /// before untrusted bytes reach `JSONDecoder`.
    public static func load(
        rulebookData: Data?,
        signatureData: Data? = nil,
        trustedKeys: [String: Curve25519.Signing.PublicKey] = RulebookTrust.trustedKeys
    ) -> RulebookPipeline {
        guard let rulebookData else {
            return fallback(reason: .missing)
        }
        guard let signatureData else {
            return fallback(reason: .signatureInvalid)
        }

        let envelope: RulebookSignatureEnvelope
        do {
            envelope = try JSONDecoder().decode(RulebookSignatureEnvelope.self, from: signatureData)
        } catch {
            return fallback(reason: .signatureInvalid)
        }

        do {
            let rulebook = try RulebookLoader.loadVerified(
                document: rulebookData,
                envelope: envelope,
                trustedKeys: trustedKeys
            )
            return RulebookPipeline(rulebook: rulebook, source: .bundled, fallbackReason: nil)
        } catch let error as RulebookError {
            switch error {
            case .invalidSignature, .unknownKeyId:
                return fallback(reason: .signatureInvalid)
            case .malformedDocument, .unsupportedSchemaVersion:
                return fallback(reason: .malformed)
            }
        } catch {
            // JSON decode failures after a valid signature.
            return fallback(reason: .malformed)
        }
    }

    public func evaluate(entries: [LogEntry], context: ContainerContext) -> RuleEvaluation {
        let matchContext = MatchContextBuilder.make(entries: entries, context: context)
        return RuleEngine.evaluate(rulebook, context: matchContext)
    }

    private static func fallback(reason: FallbackReason) -> RulebookPipeline {
        RulebookPipeline(
            rulebook: SeedRulebook.make(),
            source: .fallback,
            fallbackReason: reason
        )
    }
}
