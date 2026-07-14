// Debug/LaunchAssets/LaunchAssetArguments.swift
// B5 — CLI flags for fixture-driven launch-asset capture (DEBUG builds).

#if DEBUG
import Foundation

/// Parsed launch-asset CLI. Release builds ignore these flags entirely.
struct LaunchAssetArguments: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case normal
        case snapshot(outputDirectory: URL)
        case pose
    }

    var mode: Mode = .normal
    /// Named fixture pack (default `report2` — Digest16 / hello stop-timeout).
    var fixtureName: String = "report2"

    var usesFixtures: Bool {
        switch mode {
        case .normal: false
        case .snapshot, .pose: true
        }
    }

    static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> LaunchAssetArguments {
        var result = LaunchAssetArguments()
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--snapshot":
                let next = index + 1 < arguments.count ? arguments[index + 1] : nil
                guard let next, !next.hasPrefix("-") else {
                    fputs("launch-assets: --snapshot requires an output directory\n", stderr)
                    index += 1
                    continue
                }
                result.mode = .snapshot(
                    outputDirectory: URL(fileURLWithPath: next, isDirectory: true)
                )
                index += 2
            case "--pose":
                result.mode = .pose
                index += 1
            case "--fixture":
                let next = index + 1 < arguments.count ? arguments[index + 1] : nil
                guard let next, !next.hasPrefix("-") else {
                    fputs("launch-assets: --fixture requires a name\n", stderr)
                    index += 1
                    continue
                }
                result.fixtureName = next
                index += 2
            default:
                index += 1
            }
        }
        return result
    }
}
#endif
