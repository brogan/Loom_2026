import AppKit
import SwiftUI
import LoomEngine

struct RunControlBar: View {

    @EnvironmentObject private var controller: AppController
    @Binding var currentFrame: Int
    @Binding var seekFrame:    Int?

    @State private var isScrubbing:           Bool   = false
    @State private var scrubValue:            Double = 0
    @State private var wasPlayingBeforeScrub: Bool   = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if controller.engine != nil && controller.showScrubBar {
                scrubRow
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 12) {

            // Playback controls
            HStack(spacing: 2) {
                mediaButton("stop.fill", help: "Stop") {
                    controller.stop()
                    currentFrame = 0
                    controller.currentTimelineFrame = 0
                }
                .disabled(controller.engine == nil || controller.isExporting)

                mediaButton(controller.playbackState == .playing ? "pause.fill" : "play.fill",
                            help: controller.playbackState == .playing ? "Pause" : "Play") {
                    controller.playbackState == .playing ? controller.pause() : controller.play()
                }
                .disabled(controller.engine == nil || controller.isExporting || !controller.canPlay)

                Button {
                    controller.loopPlayback.toggle()
                } label: {
                    Image(systemName: controller.loopPlayback ? "repeat" : "repeat.1")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .foregroundStyle(controller.loopPlayback ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(controller.loopPlayback ? "Loop: On (click to play once)" : "Loop: Off (click to loop)")
                .modifier(LoomHoverHelp(controller.loopPlayback ? "Loop: On (click to play once)" : "Loop: Off (click to loop)"))
            }

            // Frame counter
            Text(controller.engine != nil ? "\(currentFrame)" : "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)

            playbackGlobals

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

                iconButton("doc.text", help: "Save SVG…") { controller.saveSVG() }
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

    private var playbackGlobals: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Duration")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("", value: bindGlobal(\.duration), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
                    .help("Duration in frames. 0 uses the automatic duration.")
                    .modifier(LoomHoverHelp("Duration in frames. 0 uses the automatic duration."))
            }
            Toggle("Animating", isOn: bindGlobal(\.animating))
                .font(.system(size: 10))
                .toggleStyle(.checkbox)
                .help("Enable global animation.")
                .modifier(LoomHoverHelp("Enable global animation."))
            Toggle("BG once", isOn: bindGlobal(\.drawBackgroundOnce))
                .font(.system(size: 10))
                .toggleStyle(.checkbox)
                .help("Draw the background once rather than every frame.")
                .modifier(LoomHoverHelp("Draw the background once rather than every frame."))
        }
        .disabled(controller.engine == nil || controller.projectConfig == nil)
    }

    private var scrubRow: some View {
        let maxFrames = Double(controller.maxScrubFrames)
        let displayFrame = isScrubbing ? Int(scrubValue) : currentFrame
        return HStack(spacing: 6) {
            Text("\(displayFrame)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : Double(currentFrame) },
                    set: { newVal in
                        scrubValue = newVal
                        seekFrame  = Int(newVal.rounded())
                    }
                ),
                in: 0...max(1, maxFrames),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        wasPlayingBeforeScrub = controller.playbackState == .playing
                        controller.pause()
                    } else {
                        if wasPlayingBeforeScrub { controller.play() }
                    }
                }
            )
            Text("\(Int(maxFrames))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 20)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: currentFrame) { _, val in
            if !isScrubbing { scrubValue = Double(val) }
        }
    }

    // MARK: - Button helpers

    private func mediaButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .modifier(LoomHoverHelp(help))
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .modifier(LoomHoverHelp(help))
    }

    private func bindGlobal<T>(_ kp: WritableKeyPath<GlobalConfig, T>) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig[keyPath: kp] ?? GlobalConfig.default[keyPath: kp] },
            set: { value in
                ctl.updateProjectConfig { $0.globalConfig[keyPath: kp] = value }
            }
        )
    }

}
