// Views/Images/PullImageSheet.swift

import SwiftUI

struct PullImageSheet: View {
    @Bindable var pulls: PullTaskCoordinator
    let onPull: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""
    @State private var trackedPulls: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let notice = pulls.noticeMessage {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if !pulls.recentFailures.isEmpty {
                    Section("Recent errors") {
                        ForEach(pulls.recentFailures) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.reference)
                                    .font(.body.monospaced())
                                Text(failure.message)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Section {
                    TextField("Image reference", text: $reference, prompt: Text("docker.io/library/redis:7"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                } header: {
                    Text("Reference")
                } footer: {
                    Text("Use a full registry reference, e.g. docker.io/library/alpine:latest")
                }

                if !pulls.activePulls.isEmpty {
                    Section("In progress") {
                        ForEach(pulls.activePulls) { pull in
                            PullSheetProgressRow(pull: pull)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pull Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pull") {
                        pullFromSheet()
                    }
                    .disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: pulls.activePulls) { _, _ in
                reconcileTrackedPulls()
            }
            .onChange(of: pulls.recentFailures) { _, _ in
                reconcileTrackedPulls()
            }
        }
        .frame(minWidth: 440, minHeight: 300)
    }

    private func pullFromSheet() {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let knownIDs = Set(pulls.activePulls.map(\.id))
        onPull(trimmed)
        reference = ""

        for pull in pulls.activePulls where pull.reference == trimmed && !knownIDs.contains(pull.id) {
            trackedPulls[pull.id] = trimmed
        }
    }

    private func reconcileTrackedPulls() {
        guard !trackedPulls.isEmpty else { return }

        let activeIDs = Set(pulls.activePulls.map(\.id))
        let failedReferences = Set(pulls.recentFailures.map(\.reference))
        var sawFailure = false

        for id in Array(trackedPulls.keys) where !activeIDs.contains(id) {
            let pullReference = trackedPulls.removeValue(forKey: id)
            if let pullReference, failedReferences.contains(pullReference) {
                sawFailure = true
            }
        }

        if trackedPulls.isEmpty, !sawFailure {
            dismiss()
        }
    }
}

private struct PullSheetProgressRow: View {
    let pull: PullTaskCoordinator.ActivePull

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(pull.reference)
                    .font(.body.monospaced())
                Text(PullProgressFormatting.statusLabel(
                    progress: pull.progress,
                    startedAt: pull.startedAt,
                    now: context.date
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                if let fraction = PullProgressFormatting.progressFraction(pull.progress) {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
        }
    }
}
