// Models/ContainerDetail.swift

import Foundation

struct ContainerDetail: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let command: [String]
    let environmentCount: Int
    let mountCount: Int
    let publishedPortCount: Int
    let networkCount: Int
    let startedAt: Date?
}
