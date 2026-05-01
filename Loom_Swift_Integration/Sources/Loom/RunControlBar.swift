import AppKit
import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

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
                iconButton("photo", help: "Save Still", action: saveStill)
                    .disabled(controller.engine == nil || controller.isExporting)

                iconButton("square.and.arrow.up", help: "Export Video…") {
                    controller.showingExportSheet = true
                }
                .disabled(controller.engine == nil || controller.isExporting)

                if let dir = controller.animationRendersDirectory() {
                    iconButton("folder", help: "Open Renders Folder") {
                        NSWorkspace.shared.open(dir)
                    }
                }

                Divider().frame(height: 18)

                iconButton("folder.badge.plus", help: "Open Project…", action: presentOpenPanel)
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

    // MARK: - Actions

    private func saveStill() {
        guard let engine = controller.engine else { return }
        let name = engine.globalConfig.name.isEmpty
            ? (controller.projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.png]
        panel.nameFieldStringValue = "\(name)_\(f.string(from: Date())).png"
        panel.directoryURL         = controller.stillRendersDirectory()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? StillExporter.exportPNG(engine: engine, to: url)
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt       = "Open Project"
        panel.directoryURL = AppController.defaultProjectsDirectory
        if panel.runModal() == .OK, let url = panel.url {
            controller.open(projectDirectory: url)
        }
    }
}
