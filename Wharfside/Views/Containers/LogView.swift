// Views/Containers/LogView.swift

import AppKit
import SwiftUI
import WharfsideAnalysis

struct LogView: View {
    let containerStatus: ContainerRuntimeStatus
    /// When `false`, lays out all lines at full height (no `ScrollView`) so
    /// `ImageRenderer` can capture the complete log surface for launch assets.
    let scrollable: Bool

    @Bindable var viewModel: LogViewModel
    @FocusState private var isSearchFocused: Bool

    init(
        viewModel: LogViewModel,
        containerStatus: ContainerRuntimeStatus,
        scrollable: Bool = true
    ) {
        self.viewModel = viewModel
        self.containerStatus = containerStatus
        self.scrollable = scrollable
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            logToolbar
            Divider()
            ZStack(alignment: .bottom) {
                logList
                if scrollable, viewModel.showJumpToLatest {
                    jumpToLatestPill
                        .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            guard scrollable else { return }
            viewModel.start(containerStatus: containerStatus)
        }
        .onDisappear {
            guard scrollable else { return }
            viewModel.stop()
        }
        .onChange(of: containerStatus) { _, status in
            guard scrollable else { return }
            viewModel.updateContainerStatus(status)
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var logToolbar: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $viewModel.sourceFilter) {
                ForEach(LogViewSourceFilter.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            TextField("Search logs…", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .frame(maxWidth: 220)

            if viewModel.showsSearchMatchCount {
                Text("\(viewModel.matchCount) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle(isOn: $viewModel.isPaused) {
                Label("Pause", systemImage: viewModel.isPaused ? "pause.fill" : "play.fill")
            }
            .toggleStyle(.button)
            .help(viewModel.isPaused ? "Resume stream" : "Pause stream")

            Toggle(isOn: $viewModel.isLineWrapEnabled) {
                Label("Wrap", systemImage: "text.append")
            }
            .toggleStyle(.button)
            .help("Toggle line wrap")

            Button {
                copyToClipboard(viewModel.visibleLinesText())
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy visible log lines")

            Button("Clear") {
                viewModel.clearDisplay()
            }
            .help("Clear displayed logs")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var logList: some View {
        if scrollable {
            ScrollViewReader { proxy in
                ScrollView {
                    logRows
                }
                .font(.body.monospaced())
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { oldOffset, newOffset in
                    if newOffset < oldOffset - 1 {
                        viewModel.userScrolledUp()
                    }
                }
                .onChange(of: viewModel.bufferRevision) { _, _ in
                    guard viewModel.isTailPinned,
                          let lastID = viewModel.displayRows.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isTailPinned) { _, pinned in
                    guard pinned, let lastID = viewModel.displayRows.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        } else {
            logRows
                .font(.body.monospaced())
        }
    }

    private var logRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.displayRows) { row in
                switch row {
                case .line(let line):
                    LogLineRow(line: line, wraps: viewModel.isLineWrapEnabled)
                        .id(row.id)
                case .stoppedCap:
                    LogStoppedCapRow()
                        .id(row.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var jumpToLatestPill: some View {
        Button {
            viewModel.jumpToLatest()
        } label: {
            Label("Jump to latest", systemImage: "arrow.down")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct LogLineRow: View {
    let line: BufferedLogLine
    let wraps: Bool

    var body: some View {
        // The message must be a standalone Text (not an HStack sibling of the fixed-width
        // level label): in an HStack, SwiftUI's width negotiation makes the message fall back
        // to word-wrap-with-truncation, so a long tail shows a stray "…" even at lineLimit(nil).
        // Reserving a leading gutter and floating the level label in an overlay keeps the
        // aligned column while letting the message wrap like a lone Text.
        Text(line.text)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .lineLimit(wraps ? nil : 1)
            .padding(.leading, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(line.level.label)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(levelColor)
                    .frame(width: 52, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch line.level {
        case .error: Color(red: 1, green: 0.35, blue: 0.35)
        case .warn: Color(red: 1, green: 0.75, blue: 0.2)
        case .info: .primary
        case .debug, .trace: .secondary
        case .unknown: .secondary
        }
    }

    private var textColor: Color {
        switch line.level {
        case .error: Color(red: 1, green: 0.55, blue: 0.55)
        case .warn: Color(red: 1, green: 0.85, blue: 0.45)
        case .debug, .trace: .secondary
        default: .primary
        }
    }
}

private struct LogStoppedCapRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
            Text("Container stopped — end of log stream")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview {
    LogView(
        viewModel: LogViewModel(containerID: "hello", service: PreviewLogService()),
        containerStatus: .running
    )
        .frame(width: 700, height: 400)
}

private struct PreviewLogService: ContainerServicing {
    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail {
        ContainerDetail(
            id: id,
            image: "alpine:latest",
            status: .running,
            command: ["/bin/sh"],
            createdAt: .now,
            startedAt: .now,
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0,
            ports: [],
            mounts: [],
            environment: [],
            networks: []
        )
    }
    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}
    func stats(id: String) async throws -> ContainerStats { fatalError() }
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LogChunk(source: .stdio, data: Data("2024-01-01 INFO hello\n".utf8)))
            continuation.yield(LogChunk(source: .stdio, data: Data("2024-01-01 ERROR boom\n".utf8)))
            continuation.finish()
        }
    }
    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
    func exitStatus(id: String) async -> ExitStatus { .unavailable(reason: .noEvidence) }
}
#endif
