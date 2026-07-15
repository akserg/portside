// Views/Containers/CopyableValueView.swift

import AppKit
import SwiftUI

struct CopyableValueView: View {
    let label: String
    let value: String
    var monospaced = true

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isHovering {
                    copyButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") {
                copyToClipboard(value)
            }
        }
    }

    private var copyButton: some View {
        Button {
            copyToClipboard(value)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CopyableRowView: View {
    let value: String
    var monospaced = true

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isHovering {
                    copyButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") {
                copyToClipboard(value)
            }
        }
    }

    private var copyButton: some View {
        Button {
            copyToClipboard(value)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
