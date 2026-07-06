// Views/Containers/LogView.swift

import AppKit
import SwiftUI
import WharfsideAnalysis

struct LogView: View {
    let containerStatus: ContainerRuntimeStatus

    @State private var viewModel: LogViewModel
    @FocusState private var isSearchFocused: Bool

    init(containerID: String, service: any ContainerServicing, containerStatus: ContainerRuntimeStatus) {
        self.containerStatus = containerStatus
        _viewModel = State(initialValue: LogViewModel(containerID: containerID, service: service))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            logToolbar
            Divider()
            ZStack(alignment: .bottom) {
                logList
                if viewModel.showJumpToLatest {
                    jumpToLatestPill
                        .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            viewModel.start(containerStatus: containerStatus)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: containerStatus) { _, status in
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

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.level.label)
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(levelColor)
                .frame(width: 52, alignment: .leading)

            Text(line.text)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .lineLimit(wraps ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    LogView(containerID: "hello", service: PreviewLogService(), containerStatus: .running)
        .frame(width: 700, height: 400)
}

#if DEBUG
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
            exitCode: nil,
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
}
#endif
