// Models/ExecResult.swift

import Foundation

struct ExecResult: Sendable, Hashable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
