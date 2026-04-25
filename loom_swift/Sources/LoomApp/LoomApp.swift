import AppKit
import SwiftUI

@main
struct LoomApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = EngineController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 540, minHeight: 400)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            LoomCommands()
        }
    }
}

// MARK: - AppDelegate

/// Ensures the process exits when the user closes the main window.
/// Without this macOS keeps the app alive in the Dock, preventing
/// `swift run` from exiting and leaving the Loom Editor's Run button disabled.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Menu commands

struct LoomCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) { }   // suppress New (we open existing projects)
    }
}
