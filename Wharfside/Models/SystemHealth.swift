// Models/SystemHealth.swift

import Foundation

struct SystemHealth: Sendable, Hashable {
    let apiServerVersion: String
    let apiServerCommit: String
    let apiServerBuild: String
    let apiServerAppName: String
    let appRoot: URL
    let installRoot: URL
    let logRootPath: String?
}
