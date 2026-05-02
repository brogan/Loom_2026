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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { controller.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Project…") { controller.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched via `swift run` the app doesn't steal keyboard focus from the
        // terminal process that spawned it. Force-activate so TextFields work immediately.
        NSApp.activate(ignoringOtherApps: true)
    }
}
