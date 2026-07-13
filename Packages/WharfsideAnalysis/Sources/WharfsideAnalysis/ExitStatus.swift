import Foundation

/// Where init-process exit evidence came from.
public enum ExitStatusSource: Sendable, Equatable, Hashable {
    case runtime
    case bootLog
}

/// Why exit evidence could not be established (fail-closed — never nil-by-accident).
public enum ExitStatusUnavailableReason: Sendable, Equatable, Hashable {
    case stillRunning
    case runtimeGone
    case noEvidence
    case ambiguousEvidence
}

/// Container init-process exit evidence for Layer 1 / diagnosis.
public enum ExitStatus: Sendable, Equatable, Hashable {
    case known(Int32, source: ExitStatusSource)
    case unavailable(reason: ExitStatusUnavailableReason)

    public var knownCode: Int32? {
        if case .known(let code, _) = self { return code }
        return nil
    }

    public var source: ExitStatusSource? {
        if case .known(_, let source) = self { return source }
        return nil
    }

    /// Overview / detail field — nil when unavailable.
    public var overviewDisplay: String? {
        switch self {
        case .known(let code, .runtime):
            return String(code)
        case .known(let code, .bootLog):
            return "\(code) (boot log)"
        case .unavailable:
            return nil
        }
    }

    /// Plain-text digest line suffix for `PromptRenderer`.
    public var digestExitLine: String? {
        switch self {
        case .known(let code, .runtime):
            return "EXIT_CODE: \(code)"
        case .known(let code, .bootLog):
            return "EXIT_CODE: \(code) (from boot log)"
        case .unavailable:
            return nil
        }
    }
}
