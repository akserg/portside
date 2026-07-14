// Debug/LaunchAssets/LaunchAssetDriver.swift
// B5 — ImageRenderer snapshot driver + posed-window stderr protocol.
//
// Compiled only into DEBUG (and thus local / CI Debug builds). Not present in
// Release/notarized builds — capture from a Debug build via capture-assets.sh.
// Trade-off: notarized Release cannot regenerate assets without a Debug binary;
// acceptable because assets are a marketing/docs pipeline, not a runtime feature.

#if DEBUG
import AppKit
import SwiftUI

enum LaunchAssetDriver {
    /// Renders the snapshot catalog to PNGs under `outputDirectory`, then terminates.
    @MainActor
    static func runSnapshot(outputDirectory: URL, fixtureName: String) async {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let fixture = FixtureAppState.make(fixtureName: fixtureName)
            let (container, corrected) = try await FixtureReplay.diagnoseReport2()
            let noisyChunks = (try? FixtureReplay.loadLogChunks(
                named: FixtureReplay.noisyLogName
            )) ?? []

            let specs = LaunchAssetSnapshotCatalog.specs(
                corrected: corrected,
                container: container,
                noisyChunks: noisyChunks,
                degradedAvailability: fixture.degradedAIAvailability
            )

            // Allow SwiftUI/AppKit to finish first-frame setup before rendering.
            try? await Task.sleep(for: .milliseconds(150))

            // Warmup pass — first ImageRenderer frames can differ (font/glyph cache).
            for spec in specs {
                _ = try? renderPNG(spec: spec)
            }

            for spec in specs {
                let png = try renderPNG(spec: spec)
                let url = outputDirectory.appendingPathComponent("\(spec.id).png")
                try png.write(to: url)
            }

            fputs("launch-assets: wrote \(specs.count) PNGs to \(outputDirectory.path)\n", stderr)
            exit(0)
        } catch {
            fputs("launch-assets: snapshot failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func renderPNG(spec: LaunchAssetSnapshotSpec) throws -> Data {
        // Pin content top-leading — bare `.frame(height:)` centers under ImageRenderer
        // and leaves marketing-unfriendly empty canvas above/below.
        let view = ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            spec.makeView()
        }
        .frame(width: spec.size.width, height: spec.size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .environment(\.displayScale, LaunchAssetSnapshotCatalog.scale)
        .transaction { $0.animation = nil }
        let renderer = ImageRenderer(content: view)
        renderer.scale = LaunchAssetSnapshotCatalog.scale
        renderer.isOpaque = true
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw LaunchAssetDriverError.renderFailed(spec.id)
        }
        return png
    }
}

enum LaunchAssetDriverError: Error, LocalizedError {
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let id):
            "ImageRenderer produced no PNG for snapshot '\(id)'"
        }
    }
}

// MARK: - Pose mode

@MainActor
@Observable
final class LaunchAssetPoseController {
    enum Step: String, CaseIterable {
        case containers
        case detail
        case diagnose
        case report
    }

    private(set) var step: Step = .containers
    private(set) var reportText: String = ""
    private(set) var container: ContainerDetail = FixtureReplay.helloContainerDetail()
    private(set) var isFinished = false
    let diagnosisCardViewModel: DiagnosisCardViewModel

    private let fixtureName: String

    init(fixtureName: String) {
        self.fixtureName = fixtureName
        self.diagnosisCardViewModel = DiagnosisCardViewModel.preview(
            phase: .idle,
            containerID: "hello"
        )
    }

    /// Optional dir for ImageRenderer chrome frames (`WHARFSIDE_POSE_FRAMES`).
    /// Used when `screencapture -l` lacks Screen Recording permission.
    private var framesDirectory: URL? {
        let path = ProcessInfo.processInfo.environment["WHARFSIDE_POSE_FRAMES"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func run() async {
        do {
            if let framesDirectory {
                try FileManager.default.createDirectory(
                    at: framesDirectory,
                    withIntermediateDirectories: true
                )
            }

            // Ensure deterministic chrome before the first POSED announce.
            await LaunchAssetBootstrap.preparePoseWindow()

            let (container, corrected) = try await FixtureReplay.diagnoseReport2()
            self.container = container
            diagnosisCardViewModel.updateContainer(container)
            self.reportText = DiagnosisReportFormatter.render(
                result: corrected,
                container: container,
                environment: FixtureReplay.reportEnvironment()
            )

            // Hold *after* each announce so capture-assets.sh / ImageRenderer can grab
            // the announced frame before the UI advances.
            step = .containers
            await settle()
            await captureFrame(named: "containers")

            step = .detail
            diagnosisCardViewModel.applyIdlePhase()
            await settle()
            await captureFrame(named: "detail")

            // Visible diagnose progression for GIF capture (await transitions, not wall-clock-only).
            step = .diagnose
            diagnosisCardViewModel.applyIdlePhase()
            await settle(short: true)
            diagnosisCardViewModel.applyRunningPartial(nil)
            await settle(short: true)
            diagnosisCardViewModel.applyCompletedResult(corrected)
            await settle()
            await captureFrame(named: "diagnose")

            step = .report
            await settle()
            await captureFrame(named: "report")

            announce("done")
            isFinished = true
            try? await Task.sleep(for: .milliseconds(400))
            exit(0)
        } catch {
            fputs("launch-assets: pose replay failed: \(error.localizedDescription)\n", stderr)
            announce("done")
            isFinished = true
            exit(1)
        }
    }

    private func settle(short: Bool = false) async {
        try? await Task.sleep(for: .milliseconds(short ? 250 : 500))
    }

    private func captureFrame(named token: String) async {
        LaunchAssetBootstrap.resizePoseWindow()
        await settle(short: true)
        announce(token)
        writeRenderedFrame(named: token)
        // Give the shell script time to run screencapture -l while this frame is showing.
        try? await Task.sleep(for: .milliseconds(900))
    }

    private func announce(_ token: String) {
        fputs("POSED \(token)\n", stderr)
        fflush(stderr)
    }

    private func writeRenderedFrame(named token: String) {
        guard let framesDirectory else { return }
        let poseSize = LaunchAssetBootstrap.poseWindowSize
        let view = LaunchAssetPoseRootView(controller: self)
            .frame(width: poseSize.width, height: poseSize.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            .environment(\.displayScale, LaunchAssetSnapshotCatalog.scale)
            .transaction { $0.animation = nil }
        let renderer = ImageRenderer(content: view)
        renderer.scale = LaunchAssetSnapshotCatalog.scale
        renderer.isOpaque = true
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("launch-assets: pose frame render failed for \(token)\n", stderr)
            return
        }
        let url = framesDirectory.appendingPathComponent("\(token).png")
        do {
            try png.write(to: url)
        } catch {
            fputs("launch-assets: pose frame write failed: \(error.localizedDescription)\n", stderr)
        }
    }
}

struct LaunchAssetPoseRootView: View {
    @Bindable var controller: LaunchAssetPoseController

    var body: some View {
        HStack(spacing: 0) {
            poseSidebar
            Divider()
            Group {
                switch controller.step {
                case .containers:
                    poseContainersList
                case .detail:
                    poseDetail
                case .diagnose:
                    poseDiagnose
                case .report:
                    DiagnosisReportPreview(reportText: controller.reportText, scrollable: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var poseSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarItem("Dashboard", selected: false)
            sidebarItem("Containers", selected: true)
            sidebarItem("Images", selected: false)
            sidebarItem("Volumes", selected: false)
            sidebarItem("Machines", selected: false)
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 160)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarItem(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private var poseContainersList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Containers")
                .font(.title2.weight(.semibold))
                .padding()
            Divider()
            // Curated cast only — never the live daemon list (avoids leaking b1-* test names).
            listRow(id: "crashy", image: "crashy:latest", running: false, selected: false)
            listRow(id: "hello", image: controller.container.image, running: false, selected: true)
            listRow(id: "web", image: "nginx:alpine", running: true, selected: false)
            Spacer()
        }
    }

    private func listRow(id: String, image: String, running: Bool, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(running ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(id).font(.body)
                Text(image).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var poseDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.container.id)
                .font(.title2.weight(.semibold))
            Text(controller.container.image)
                .foregroundStyle(.secondary)
            Text("Stopped")
                .foregroundStyle(.secondary)
            Divider()
            Text("Diagnosis")
                .font(.headline)
            DiagnosisCard(viewModel: controller.diagnosisCardViewModel)
            Spacer()
        }
        .padding(24)
    }

    private var poseDiagnose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.container.id)
                .font(.title2.weight(.semibold))
            Text("Diagnosis")
                .font(.headline)
            DiagnosisCard(viewModel: controller.diagnosisCardViewModel)
            Spacer()
        }
        .padding(24)
    }
}

struct LaunchAssetSnapshotHostView: View {
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
    }
}
#endif
