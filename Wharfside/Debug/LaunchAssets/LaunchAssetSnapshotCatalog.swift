// Debug/LaunchAssets/LaunchAssetSnapshotCatalog.swift
// B5 — fixed-size ImageRenderer view list (scale = 2).

#if DEBUG
import AppKit
import SwiftUI
import WharfsideAnalysis

struct LaunchAssetSnapshotSpec: Identifiable {
    let id: String
    let size: CGSize
    let makeView: @MainActor () -> AnyView
}

private struct SnapshotContainerRow: Identifiable {
    let id: String
    let image: String
    let running: Bool
}

@MainActor
enum LaunchAssetSnapshotCatalog {
    static let scale: CGFloat = 2

    static func specs(
        corrected: DiagnosisResult,
        container: ContainerDetail,
        noisyChunks: [LogChunk],
        degradedAvailability: AIAvailabilityService
    ) -> [LaunchAssetSnapshotSpec] {
        let reportText = DiagnosisReportFormatter.render(
            result: corrected,
            container: container,
            environment: FixtureReplay.reportEnvironment()
        )
        let wrong = FixtureReplay.wrongDiagnosisResult(renderedDigest: corrected.renderedDigest)

        return heroSpecs(corrected: corrected, container: container, reportText: reportText, wrong: wrong)
            + surfaceSpecs(noisyChunks: noisyChunks, degradedAvailability: degradedAvailability)
    }

    private static func heroSpecs(
        corrected: DiagnosisResult,
        container: ContainerDetail,
        reportText: String,
        wrong: DiagnosisResult
    ) -> [LaunchAssetSnapshotSpec] {
        [
            // Pre-diagnosis: Explain CTA + on-device privacy tagline (AI available, idle).
            LaunchAssetSnapshotSpec(
                id: "diagnosis-idle",
                size: CGSize(width: 520, height: 120)
            ) {
                AnyView(
                    diagnosisSection {
                        DiagnosisCard(
                            viewModel: DiagnosisCardViewModel.preview(
                                phase: .idle,
                                containerID: container.id
                            )
                        )
                    }
                    .padding(16)
                    .frame(width: 520, height: 120, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                )
            },
            // Completed diagnosis with actionable footer (Copy report / Regenerate).
            LaunchAssetSnapshotSpec(
                id: "diagnosis-hero",
                size: CGSize(width: 520, height: 280)
            ) {
                AnyView(
                    diagnosisSection {
                        diagnosisCard(
                            result: corrected,
                            showsFooterActions: true,
                            showsRegenerate: true
                        )
                    }
                    .padding(16)
                    .frame(width: 520, height: 280, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                )
            },
            LaunchAssetSnapshotSpec(
                id: "report-markdown",
                size: CGSize(width: 720, height: 560)
            ) {
                AnyView(
                    DiagnosisReportPreview(
                        reportText: reportText,
                        scrollable: false,
                        allowsTextSelection: false
                    )
                    .frame(width: 720, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                )
            },
            LaunchAssetSnapshotSpec(
                id: "wrong-diagnosis",
                size: CGSize(width: 520, height: 280)
            ) {
                AnyView(
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Historical misdiagnosis (report2 — fixed in 0.1.1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        ActionErrorBanner(
                            message: DiagnosisPrivacyCopy.copyReportToast
                        )
                        diagnosisCard(result: wrong)
                            .padding(16)
                    }
                    .frame(width: 520, height: 280, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                )
            }
        ]
    }

    private static func surfaceSpecs(
        noisyChunks: [LogChunk],
        degradedAvailability: AIAvailabilityService
    ) -> [LaunchAssetSnapshotSpec] {
        [
            LaunchAssetSnapshotSpec(
                id: "log-viewer",
                size: CGSize(width: 720, height: 200)
            ) {
                AnyView(logViewer(chunks: noisyChunks))
            },
            LaunchAssetSnapshotSpec(
                id: "containers-list",
                size: CGSize(width: 460, height: 220)
            ) {
                AnyView(containersList())
            },
            LaunchAssetSnapshotSpec(
                id: "degraded-ai-banner",
                size: CGSize(width: 480, height: 72)
            ) {
                AnyView(
                    AIStatusBanner(reason: .appleIntelligenceNotEnabled, showsActionButton: false)
                        .environment(degradedAvailability)
                        .padding(12)
                        .frame(width: 480, height: 72, alignment: .topLeading)
                        .background(Color(nsColor: .windowBackgroundColor))
                )
            },
            LaunchAssetSnapshotSpec(
                id: "degraded-ai-downloading",
                size: CGSize(width: 480, height: 72)
            ) {
                AnyView(
                    AIStatusBanner(reason: .modelNotReady, showsActionButton: false)
                        .environment(
                            AIAvailabilityService(
                                provider: LaunchAssetFixedAvailability(
                                    capability: .heuristicsOnly(.modelNotReady)
                                )
                            )
                        )
                        .padding(12)
                        .frame(width: 480, height: 72, alignment: .topLeading)
                        .background(Color(nsColor: .windowBackgroundColor))
                )
            }
        ]
    }

    private static func diagnosisSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnosis")
                .font(.headline)
            content()
        }
    }

    private static func diagnosisCard(
        result: DiagnosisResult,
        showsFooterActions: Bool = false,
        showsRegenerate: Bool = false
    ) -> some View {
        // Skip DiagnosisCard chrome for result stills — idle uses DiagnosisCard directly.
        // Footer actions are text-only under ImageRenderer (SF Symbols paint yellow there);
        // inline per-action copy chips stay off for the same reason.
        DiagnosisResultCard(
            result: result,
            isDimmed: false,
            isVerifying: false,
            showsRegenerate: showsRegenerate,
            showsFooterActions: showsFooterActions,
            showsFooterActionSymbols: false,
            showsInlineCopyButtons: false,
            isRunning: false,
            onRegenerate: {},
            onCopyReport: {}
        )
    }

    private static func logViewer(chunks: [LogChunk]) -> some View {
        // Avoid LogView toolbar (Picker/search Buttons) — ImageRenderer paints
        // yellow missing-glyph placeholders for those controls.
        _ = chunks
        let lines: [(level: String, color: Color, text: String)] = [
            ("INFO", .primary, "2026-07-09T10:00:01.123Z LOG:  database system is ready to accept connections"),
            ("INFO", .primary, "2026-07-09T10:00:05.456Z INFO:  checkpoint starting"),
            ("ERROR", Color(red: 1, green: 0.35, blue: 0.35),
             "2026-07-09T10:00:10.789Z FATAL:  terminating connection due to administrator command"),
            ("INFO", .primary, "2026-07-09T10:00:10.790Z LOG:  database system is shut down"),
            ("ERROR", Color(red: 1, green: 0.35, blue: 0.35),
             "2026-07-09T10:00:10.791Z ERROR: could not write to file \"pg_wal/…\": No space left on device")
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Text("Logs — db")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.level)
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(line.color)
                        .frame(width: 52, alignment: .leading)
                    Text(line.text)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
            HStack(spacing: 8) {
                Text("●")
                    .foregroundStyle(.secondary)
                Text("Container stopped — end of log stream")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 720, height: 200, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func containersList() -> some View {
        let rows: [SnapshotContainerRow] = [
            SnapshotContainerRow(id: "crashy", image: "crashy:latest", running: false),
            SnapshotContainerRow(id: "hello", image: "docker.io/library/alpine:latest", running: false),
            SnapshotContainerRow(id: "web", image: "nginx:alpine", running: true)
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Text("Containers")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(row.running ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.id).font(.body)
                        Text(row.image)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 460, height: 220, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
