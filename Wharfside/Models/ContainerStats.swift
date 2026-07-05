// Models/ContainerStats.swift

import Foundation

struct ContainerStats: Sendable, Hashable {
    let id: String
    let memoryUsageBytes: UInt64?
    let memoryLimitBytes: UInt64?
    let cpuUsageMicroseconds: UInt64?
    let networkRxBytes: UInt64?
    let networkTxBytes: UInt64?
    let blockReadBytes: UInt64?
    let blockWriteBytes: UInt64?
    let processCount: UInt64?
}
