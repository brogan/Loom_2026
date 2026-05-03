import AppKit
import SwiftUI
import LoomEngine

struct RunControlBar: View {

    @EnvironmentObject private var controller: AppController
    @Binding var currentFrame: Int

    var body: some View {
        HStack(spacing: 12) {

            // Playback controls
            HStack(spacing: 2) {
                mediaButton("stop.fill", help: "Stop") {
                    controller.stop()
                    currentFrame = 0
                }
                .disabled(controller.engine == nil || controller.isExporting)

                mediaButton(controller.playbackState == .playing ? "pause.fill" : "play.fill",
                            help: controller.playbackState == .playing ? "Pause" : "Play") {
                    controller.playbackState == .playing ? controller.pause() : controller.play()
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(controller.engine == nil || controller.isExporting)
            }

            // Frame counter
            Text(controller.engine != nil ? "\(currentFrame)" : "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)

            Spacer()

            // Project name
            if let engine = controller.engine {
                Text(engine.globalConfig.name.isEmpty
                     ? (controller.projectURL?.lastPathComponent ?? "")
                     : engine.globalConfig.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                // Render output section
                iconButton("photo", help: "Save Still") { controller.saveStill() }
                    .disabled(controller.engine == nil || controller.isExporting)

                iconButton("movieclapper", help: "Export Video…") {
                    controller.showingExportSheet = true
                }
                .disabled(controller.engine == nil || controller.isExporting)

                if let dir = controller.lastUsedRendersDirectory() {
                    iconButton("folder", help: "Open Renders Folder") {
                        NSWorkspace.shared.open(dir)
                    }
                }

                Divider().frame(height: 18)

                // Loom projects section
                iconButton("smallcircle.filled.circle", help: "Open Loom Projects Folder") {
                    NSWorkspace.shared.open(AppController.defaultProjectsDirectory)
                }

                Divider().frame(height: 18)

                // New / open / reload section
                iconButton("folder.badge.plus", help: "New Project…") { controller.newProject() }
                    .keyboardShortcut("n", modifiers: .command)

                iconButton("folder", help: "Open Project…") { controller.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                if controller.engine != nil {
                    iconButton("arrow.clockwise", help: "Reload") { controller.reload() }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Button helpers

    private func mediaButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

}

