// Models/PendingImageAction.swift

import Foundation

enum PendingImageAction: Equatable, Sendable, Identifiable {
    case delete(String)

    var id: String {
        switch self {
        case .delete(let reference):
            "delete-\(reference)"
        }
    }

    var reference: String {
        switch self {
        case .delete(let reference):
            reference
        }
    }
}

enum ImageActionSupport {
    static func confirmationTitle(for action: PendingImageAction) -> String {
        switch action {
        case .delete:
            "Delete image?"
        }
    }

    static func confirmationMessage(for action: PendingImageAction) -> String {
        switch action {
        case .delete(let reference):
            let display = ImageSummaryFormatting.displayReference(reference)
            return "Image \(display) will be permanently removed."
        }
    }

    static func destructiveConfirmationLabel(for action: PendingImageAction) -> String {
        switch action {
        case .delete:
            "Delete"
        }
    }
}
