// Models/ImageSummary.swift

import Foundation

struct ImageSummary: Sendable, Hashable, Identifiable {
    var id: String { reference }
    let reference: String
    let digest: String
}
