// Models/ImageSummaryFormatting.swift

import Foundation

enum ImageSummaryFormatting {
    static func displayReference(_ reference: String) -> String {
        if isUntagged(reference) {
            return "<none>"
        }
        return reference
    }

    static func isUntagged(_ reference: String) -> Bool {
        if reference.isEmpty { return true }
        if reference == "<none>" || reference == "<none>:<none>" { return true }
        if reference.hasPrefix("<none>:") || reference.hasSuffix(":<none>") { return true }
        if reference.hasPrefix("sha256:"), !reference.contains("/") { return true }
        return false
    }

    static func shortDigest(_ digest: String) -> String {
        guard digest.hasPrefix("sha256:") else { return digest }
        let hex = String(digest.dropFirst("sha256:".count))
        guard hex.count > 12 else { return digest }
        return "sha256:\(hex.prefix(12))…"
    }

    static func formattedSize(_ sizeBytes: Int64?) -> String {
        guard let sizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static func relativeCreated(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }
}
