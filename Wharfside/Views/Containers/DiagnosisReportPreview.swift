// Views/Containers/DiagnosisReportPreview.swift
// Markdown-ish preview of DiagnosisReportFormatter output (launch assets + DEBUG).

import AppKit
import SwiftUI

/// Renders a diagnosis report string in a monospaced scrollable (or full-height) surface.
struct DiagnosisReportPreview: View {
    let reportText: String
    /// When `false`, expands to intrinsic height for `ImageRenderer` capture.
    var scrollable: Bool = true
    /// Text selection can leave highlight artifacts in `ImageRenderer` stills.
    var allowsTextSelection: Bool = true

    var body: some View {
        Group {
            if scrollable {
                ScrollView {
                    reportBody
                }
            } else {
                reportBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: scrollable ? .infinity : nil, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var reportBody: some View {
        let text = Text(reportText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        if allowsTextSelection {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}
