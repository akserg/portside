// Debug/LaunchAssets/LaunchAssetAppDelegate.swift
// B5 — kicks snapshot/pose once NSApplication is ready (CLI `.task` is unreliable).

#if DEBUG
import AppKit
import SwiftUI

enum LaunchAssetBootstrap {
    static var arguments = LaunchAssetArguments()
    @MainActor static var poseController: LaunchAssetPoseController?
    @MainActor static var poseAppState: AppState?
    @MainActor static var poseAIAvailability: AIAvailabilityService?
    /// Retains the explicit pose `NSWindow` (WindowGroup alone is unreliable under CLI launch).
    @MainActor static var poseWindow: NSWindow?

    /// Deterministic pose window (pt). Narrow enough that a README-width (~880px) GIF
    /// keeps diagnosis text / footer readable (~85% scale).
    static let poseWindowSize = NSSize(width: 1_050, height: 700)

    @MainActor
    static func openPoseWindow() {
        if poseWindow != nil {
            resizePoseWindow()
            return
        }
        guard let controller = poseController,
              let appState = poseAppState,
              let aiAvailability = poseAIAvailability else {
            fputs("launch-assets: pose bootstrap missing controller/environment\n", stderr)
            return
        }

        let root = LaunchAssetPoseRootView(controller: controller)
            .environment(appState)
            .environment(aiAvailability)
            .preferredColorScheme(.dark)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let size = poseWindowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wharfside"
        window.contentViewController = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.styleMask.remove(.resizable)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        poseWindow = window
        fputs(
            "launch-assets: pose window \(Int(size.width))×\(Int(size.height)) pt\n",
            stderr
        )
    }

    @MainActor
    static func resizePoseWindow() {
        let size = poseWindowSize
        let window = poseWindow
            ?? NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible })
            ?? NSApp.windows.first(where: { $0.contentView != nil })
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
        guard let window else {
            fputs("launch-assets: no visible window to resize for pose\n", stderr)
            return
        }
        window.styleMask.remove(.resizable)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        if let screen = window.screen ?? NSScreen.main {
            let frame = window.frame
            let visible = screen.visibleFrame
            // Keep current top-left; only enforce content size (title bar height varies).
            let chrome = frame.height - (window.contentLayoutRect.height)
            let outer = NSSize(width: size.width, height: size.height + max(0, chrome))
            let origin = NSPoint(
                x: visible.midX - outer.width / 2,
                y: visible.midY - outer.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: outer), display: true)
            window.setContentSize(size)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @MainActor
    static func preparePoseWindow() async {
        openPoseWindow()
        try? await Task.sleep(for: .milliseconds(150))
        resizePoseWindow()
    }
}

final class LaunchAssetAppDelegate: NSObject, NSApplicationDelegate {
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !started else { return }
        started = true

        let arguments = LaunchAssetBootstrap.arguments
        switch arguments.mode {
        case .normal:
            return
        case .snapshot(let directory):
            NSApp.appearance = NSAppearance(named: .darkAqua)
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                await LaunchAssetDriver.runSnapshot(
                    outputDirectory: directory,
                    fixtureName: arguments.fixtureName
                )
            }
        case .pose:
            NSApp.appearance = NSAppearance(named: .darkAqua)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                await LaunchAssetBootstrap.preparePoseWindow()
                if let controller = LaunchAssetBootstrap.poseController {
                    await controller.run()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        switch LaunchAssetBootstrap.arguments.mode {
        case .snapshot, .pose:
            return true
        case .normal:
            return false
        }
    }
}
#endif
