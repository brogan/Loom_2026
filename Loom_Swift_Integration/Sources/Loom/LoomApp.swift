import AppKit
import SwiftUI

@main
struct LoomIntegrationApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 900, minHeight: 600)
                .focusedObject(controller)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { LoomCommands() }
    }
}

struct LoomCommands: Commands {
    @FocusedObject private var controller: AppController?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { controller?.newProject() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open Project…") { controller?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { controller?.saveNow() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(controller?.projectURL == nil)
        }
        CommandMenu("Playback") {
            Button(controller?.playbackState == .paused ? "Resume" : "Pause") {
                switch controller?.playbackState {
                case .playing: controller?.pause()
                case .paused:  controller?.play()
                default: break
                }
            }
            .keyboardShortcut(" ", modifiers: [])
            .disabled(controller?.playbackState != .playing && controller?.playbackState != .paused)
        }
        CommandGroup(replacing: .help) {
            Button("Loom Help") { HelpWindowController.shared.show() }
                .keyboardShortcut("?", modifiers: .command)
            Button("Reveal Loom Log") { LoomLogger.revealInFinder() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoomLogger.install()
        // When launched via `swift run` the app doesn't steal keyboard focus from the
        // terminal process that spawned it. Force-activate so TextFields work immediately.
        NSApp.activate(ignoringOtherApps: true)
    }
}
