// Views/Images/TagImageSheet.swift

import SwiftUI

struct TagImageSheet: View {
    let sourceReference: String
    let onTag: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newReference = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Source") {
                        Text(ImageSummaryFormatting.displayReference(sourceReference))
                            .font(.body.monospaced())
                            .lineLimit(1)
                    }
                    TextField("New reference", text: $newReference, prompt: Text("spike-test:brief"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                } header: {
                    Text("Tag Image")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tag Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tag") {
                        Task {
                            isSubmitting = true
                            await onTag(newReference.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(
                        isSubmitting
                            || newReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}
