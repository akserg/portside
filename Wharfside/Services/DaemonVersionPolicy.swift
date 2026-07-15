// Services/DaemonVersionPolicy.swift

import Foundation

enum DaemonVersionPolicy {
    nonisolated static func isPreOnePointZero(apiServerVersion: String?) -> Bool {
        guard let apiServerVersion, !apiServerVersion.isEmpty else { return false }
        guard let semver = parseMajor(apiServerVersion) else { return false }
        return semver == 0
    }

    nonisolated private static func parseMajor(_ versionString: String) -> Int? {
        let pattern = #/(\d+)\.\d+\.\d+/#
        guard let match = versionString.firstMatch(of: pattern) else { return nil }
        return Int(match.1)
    }
}
