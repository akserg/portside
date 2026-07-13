// Views/Shared/PreOnePointZeroDaemonBanner.swift

import SwiftUI

/// Shown when the connected apiserver is on the pre-1.0 release line (0.x).
struct PreOnePointZeroDaemonBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(
                "Container daemon is pre-1.0 — exit-status and stop behavior may differ from "
                + "this build's tested surface (1.0.0+)."
            )
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("preOnePointZeroDaemonBanner")
    }
}
