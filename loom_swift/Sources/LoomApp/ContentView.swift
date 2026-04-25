import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject private var controller: EngineController
    @State private var showExportSheet = false
    @State private var currentFrame:   Int = 0

    var body: some View {
        Group {
            if let engine = controller.engine {
                renderView(engine: engine)
            } else {
                landingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .sheet(isPresented: $showExportSheet) {
            if let engine = controller.engine {
                ExportSheet(engine: engine)
                    .environmentObject(controller)
            }
        }
        // Reset frame counter when a new project is loaded.
        .onChange(of: controller.projectURL) { _, _ in currentFrame = 0 }
        // Python editor ".capture_video" sentinel → present export sheet.
        .onChange(of: controller.requestingExportSheet) { _, requested in
            if requested {
                showExportSheet = true
                controller.requestingExportSheet = false
            }
        }
    }

    // MARK: - Landing view (no project loaded)

    private var landingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Loom")
                .font(.largeTitle.bold())

            if let error = controller.loadError {
                VStack(spacing: 4) {
                    Label("Load failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(.red.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            Button("Open Project…") { presentOpenPanel() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)

            if !controller.recentProjects.isEmpty {
                recentProjectsList
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 400)
    }

    private var recentProjectsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 2) {
                ForEach(controller.recentProjects, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.body)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { controller.open(projectDirectory: url) }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Render view (project loaded)

    private func renderView(engine: Engine) -> some View {
        RenderSurfaceView(
            engine:        engine,
            playbackState: controller.isExporting ? .paused : controller.playbackState,
            onFrameTick:   { currentFrame = $0 }
        )
        .aspectRatio(
            CGSize(width: engine.globalConfig.width, height: engine.globalConfig.height),
            contentMode: .fit
        )
        .toolbar {
            // Left: project name
            ToolbarItem(placement: .navigation) {
                Text(engine.globalConfig.name.isEmpty
                     ? "Loom" : engine.globalConfig.name)
                    .font(.headline)
            }

            // Centre: playback controls + frame counter
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    // Stop (rewind to frame 0)
                    Button {
                        controller.stop()
                        currentFrame = 0
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(controller.isExporting)
                    .help("Stop and reset to frame 0")

                    // Play / Pause toggle
                    Button {
                        if controller.playbackState == .playing {
                            controller.pause()
                        } else {
                            controller.play()
                        }
                    } label: {
                        Image(systemName: controller.playbackState == .playing
                              ? "pause.fill" : "play.fill")
                    }
                    .disabled(controller.isExporting)
                    .keyboardShortcut(" ", modifiers: [])
                    .help(controller.playbackState == .playing ? "Pause" : "Play")

                    // Frame counter: "42 / ∞"
                    Text("\(currentFrame) / ∞")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 80, alignment: .leading)
                }
            }

            // Right: file / export actions
            ToolbarItemGroup(placement: .primaryAction) {
                Button { presentOpenPanel() } label: {
                    Label("Open Project", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button { exportStill() } label: {
                    Label("Save Frame", systemImage: "photo")
                }
                .disabled(controller.isExporting)
                .keyboardShortcut("s", modifiers: .command)

                Button { showExportSheet = true } label: {
                    Label("Export Video…", systemImage: "square.and.arrow.up")
                }
                .disabled(controller.isExporting)
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Still export

    private func exportStill() {
        guard let engine = controller.engine else { return }

        let projectName = engine.globalConfig.name.isEmpty
            ? (controller.projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name

        let filename = "\(projectName)_\(timestampString()).png"

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType.png]
        panel.nameFieldStringValue = filename
        panel.prompt               = "Save Frame"
        panel.directoryURL         = controller.stillRendersDirectory()

        // Use beginSheetModal so the panel attaches to the app window as a
        // proper sheet — runModal() creates a blocking nested event loop that
        // fights SwiftUI's focus system and causes the filename field to lose
        // focus immediately after clicking it.
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try StillExporter.exportPNG(engine: engine, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText     = "Still export failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        if let window = NSApplication.shared.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    // MARK: - Open panel

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt                  = "Open Project"
        panel.message                 = "Select a Loom project folder."
        panel.directoryURL            = EngineController.defaultProjectsDirectory

        if panel.runModal() == .OK, let url = panel.url {
            controller.open(projectDirectory: url)
        }
    }

    // MARK: - Helpers

    private func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
