// Models/PullProgress.swift

import Foundation

struct PullProgress: Sendable, Hashable {
    let description: String
    let completedUnits: Int
    let totalUnits: Int?
}
