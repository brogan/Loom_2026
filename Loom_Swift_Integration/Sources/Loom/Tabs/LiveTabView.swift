import AppKit
import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

/// Left-panel content for the Live tab: a read-only browse of the project's
/// existing sprite sets/sprites (stage from here) plus the list of currently
/// staged instances with visibility + pose controls — `LoomLiveV1Scope.md` §2.1.
struct LiveTabView: View {

    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var liveController: LiveSessionController
    // Separate subscription from `liveController` — mutating `liveAudio`'s
    // own @Published properties doesn't propagate through `liveController`'s
    // objectWillChange, so views needing live updates from it (filename,
    // offset, etc.) must observe it directly.
    @EnvironmentObject private var liveAudio: AudioController
    @State private var sessionNameDraft: String = ""
    @State private var showReplaySheet = false
    @State private var sessionToRenderURL: URL?
    @State private var showTimelineSheet = false
    @State private var sessionToReviewURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let error = liveController.loadError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                recordingSection

                Divider().padding(.horizontal, 12)

                audioSection

                Divider().padding(.horizontal, 12)

                musicSyncSection

                Divider().padding(.horizontal, 12)

                stagedSection

                Divider().padding(.horizontal, 12)

                browseSection
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showReplaySheet, onDismiss: { liveController.canvasPaused = false }) {
            if let url = sessionToRenderURL, let projectURL = controller.projectURL {
                SessionReplaySheet(projectURL: projectURL, sessionURL: url)
                    .environmentObject(controller)
            }
        }
        .sheet(isPresented: $showTimelineSheet, onDismiss: { liveController.canvasPaused = false }) {
            if let url = sessionToReviewURL, let projectURL = controller.projectURL {
                EventTimelineSheet(projectURL: projectURL, sessionURL: url, fps: controller.projectConfig?.globalConfig.targetFPS ?? 30)
                    .environmentObject(controller)
            }
        }
    }

    /// Opens an `NSOpenPanel` defaulted to the project's `sessions/` folder
    /// to pick a recorded log, then presents `SessionReplaySheet` for it.
    /// `.jsonl` has no built-in `UTType`, so this allows any file type
    /// rather than filtering — matching the existing convention for
    /// extension-less/uncommon file pickers elsewhere in `AppController`.
    private func presentRenderSessionPicker() {
        LoomLogger.info("[SessionReplay] Render Session… clicked, opening file picker")
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        if let projectURL = controller.projectURL {
            panel.directoryURL = projectURL.appendingPathComponent("sessions")
        }
        panel.begin { response in
            LoomLogger.info("[SessionReplay] File picker completed, response=\(response == .OK ? "OK" : "cancel"), url=\(panel.url?.path ?? "nil")")
            guard response == .OK, let url = panel.url else { return }
            sessionToRenderURL = url
            // Stop the Live canvas's continuous 60fps render timer before
            // presenting the sheet — see `LiveSessionController.canvasPaused`'s
            // doc comment for why presenting a sheet on a window whose
            // content is being redrawn on a timer like that can deadlock.
            liveController.canvasPaused = true
            showReplaySheet = true
            LoomLogger.info("[SessionReplay] showReplaySheet set to true for \(url.lastPathComponent)")
        }
    }

    /// Same `NSOpenPanel` pattern as `presentRenderSessionPicker`, opening
    /// `EventTimelineSheet` (review/edit) instead of jumping straight to
    /// `SessionReplaySheet` (render-only, unchanged fast path).
    private func presentReviewSessionPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        if let projectURL = controller.projectURL {
            panel.directoryURL = projectURL.appendingPathComponent("sessions")
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            sessionToReviewURL = url
            liveController.canvasPaused = true
            showTimelineSheet = true
        }
    }

    private var header: some View {
        Text("Live")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }

    // MARK: - Recording (SessionWorkflow.md §3.2)

    /// Explicit start/stop, not automatic — opening the Live tab or poking
    /// around records nothing until the user asks for it, so a session file
    /// is one deliberate take rather than "everything since the tab opened."
    /// The name field becomes the file's name (sanitized, collision-safe);
    /// left blank, it falls back to a timestamp.
    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recording")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            HStack(spacing: 6) {
                TextField("Session name", text: $sessionNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(liveController.isRecording)

                Button(liveController.isRecording ? "Stop" : "Start") {
                    if liveController.isRecording {
                        liveController.stopRecording()
                    } else {
                        liveController.startRecording(name: sessionNameDraft)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)

            if liveController.isRecording {
                Label("Recording — \(liveController.sessionEvents.count) events", systemImage: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            } else if let url = liveController.sessionLogURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 6) {
                Button("Review Session…") { presentReviewSessionPicker() }
                    .buttonStyle(.bordered)
                    .disabled(liveController.isRecording)
                Button("Render Session…") { presentRenderSessionPicker() }
                    .buttonStyle(.bordered)
                    .disabled(liveController.isRecording)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Audio
    //
    // Live's own audio track — a separate `AudioController` instance
    // (`liveController.liveAudio`) from the main timeline's, tied to the
    // Live engine's own continuous clock via `LiveCanvasView`'s
    // `onFrameTick` rather than the main timeline (which doesn't even tick
    // while the Live tab is open — see `LiveSessionController.liveAudio`'s
    // doc comment). No waveform strip here — this panel is a narrow list
    // column; the visual waveform lives in the Review Session panel instead.

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            HStack(spacing: 6) {
                Button { importLiveAudioFile() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                        .iconHitArea(16)
                }
                .buttonStyle(.plain)
                .modifier(LoomHoverHelp("Import audio for this Live session"))

                if let name = liveAudio.audioFilename {
                    Text(liveAudio.fileNotFound ? "\(name) — not found" : name)
                        .font(.system(size: 11))
                        .foregroundStyle(liveAudio.fileNotFound ? Color.red : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button { liveAudio.isMuted.toggle() } label: {
                        Image(systemName: liveAudio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .iconHitArea(16)
                    }
                    .buttonStyle(.plain)
                    .modifier(LoomHoverHelp(liveAudio.isMuted ? "Unmute" : "Mute"))

                    Button { liveAudio.clear() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10))
                            .iconHitArea(16)
                    }
                    .buttonStyle(.plain)
                    .modifier(LoomHoverHelp("Remove audio"))
                } else {
                    Text("No audio").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)

            if liveAudio.audioFilename != nil {
                HStack(spacing: 4) {
                    Text("Offset").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("", value: Binding(
                        get: { liveAudio.offsetFrames },
                        set: { liveController.setLiveAudioOffset($0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 56)
                    Text("frame — loops automatically").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func importLiveAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Audio"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["wav", "aiff", "aif", "mp3", "m4a", "caf", "flac", "aac"]
            .compactMap { UTType(filenameExtension: $0) }
        if let projectURL = controller.projectURL {
            // Default to the project's main audio/ folder, not Live's own
            // sessions/audio/ — the file being imported almost always
            // already exists there (e.g. the main timeline's own soundtrack)
            // and sessions/audio/ is typically empty until this picker has
            // been used at least once. Must point at a directory that
            // actually exists: NSOpenPanel silently falls back to whatever
            // location a *different* panel elsewhere in the app last used
            // (e.g. the video export save panel) if `directoryURL` doesn't.
            let audioDir = projectURL.appendingPathComponent("audio")
            panel.directoryURL = FileManager.default.fileExists(atPath: audioDir.path) ? audioDir : projectURL
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            liveController.importLiveAudio(from: url)
        }
    }

    // MARK: - Music sync (LoomLiveV1Scope.md §2.6)

    /// Global BPM/time-signature + a manual downbeat-tap button — the cheap
    /// substitute for MIDI-driven sync explored here (full MIDI stays in the
    /// separate adjunct app, `PerformanceArchitecture.md` §0.2). Any driver
    /// can opt into tracking this via its Rate control in the right
    /// inspector; this section only owns the shared clock, not any one driver.
    private var musicSyncSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Music Sync")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            HStack(spacing: 6) {
                Text("BPM").font(.system(size: 10)).foregroundStyle(.secondary)
                FloatEntryField(value: Binding(
                    get: { liveController.bpm },
                    set: { liveController.setBPM($0) }
                ), width: 46, fractionDigits: 1)

                Text("Beats/Bar").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { liveController.beatsPerBar },
                    set: { liveController.setBeatsPerBar($0) }
                )) {
                    ForEach([2, 3, 4, 5, 6, 7, 8, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 50)

                Button("Tap") { liveController.tapDownbeat() }
                    .buttonStyle(.bordered)
                    .modifier(LoomHoverHelp("Press in time with a bar's first beat to align musically-linked drivers. Re-tappable anytime; no drift correction between taps."))
            }
            .padding(.horizontal, 12)

            Text(liveController.barReferenceFrame != nil ? "Synced" : "Not synced — tap once to align")
                .font(.system(size: 9))
                .foregroundStyle(liveController.barReferenceFrame != nil ? .green : .secondary)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Staged sprites

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Staged")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            if liveController.stagedSprites.isEmpty {
                Text("Nothing staged yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(liveController.stagedSprites) { staged in
                    stagedRow(staged)
                }
            }
        }
    }

    private func stagedRow(_ staged: LiveSessionController.StagedSprite) -> some View {
        let isSelected = liveController.selectedStagedID == staged.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { staged.isVisible },
                    set: { liveController.setVisible(staged.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Text(staged.spriteDefName)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer()

                Button { liveController.destage(staged.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).iconHitArea(16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .modifier(LoomHoverHelp("Remove from stage"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { liveController.selectedStagedID = staged.id }

            if isSelected {
                poseControls(staged)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private func poseControls(_ staged: LiveSessionController.StagedSprite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Pos").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.position.x), width: 52)
                FloatEntryField(value: poseBinding(staged.id, \.position.y), width: 52)
            }
            HStack(spacing: 4) {
                Text("Scale").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.scale.x), width: 52)
                FloatEntryField(value: poseBinding(staged.id, \.scale.y), width: 52)
            }
            HStack(spacing: 4) {
                Text("Rot").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.rotation), width: 52)
            }
        }
    }

    /// Reads/writes one scalar of a staged sprite's pose, routing every write
    /// through `LiveSessionController.updatePose` so the engine and the
    /// app-side record stay in sync on every commit.
    private func poseBinding(
        _ id: LiveSessionController.StagedSprite.ID,
        _ keyPath: WritableKeyPath<LiveSessionController.StagedSprite, Double>
    ) -> Binding<Double> {
        Binding(
            get: { liveController.stagedSprites.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard var staged = liveController.stagedSprites.first(where: { $0.id == id }) else { return }
                staged[keyPath: keyPath] = newValue
                liveController.updatePose(id, position: staged.position, scale: staged.scale, rotation: staged.rotation)
            }
        )
    }

    // MARK: - Browse sprite sets

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sprite Sets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            ForEach(controller.projectConfig?.spriteConfig.library.spriteSets ?? [], id: \.name) { set in
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)

                    ForEach(set.sprites, id: \.name) { sprite in
                        Button {
                            liveController.stage(spriteSetName: set.name, spriteName: sprite.name)
                        } label: {
                            HStack {
                                Text(sprite.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Centre-panel canvas for the Live tab — mirrors `ContentView.liveCanvas`
/// but is bound to the Live tab's own independent `Engine`
/// (`LiveSessionController.engine`), never `AppController.engine`.
struct LiveCanvasView: View {

    @EnvironmentObject private var liveController: LiveSessionController
    @EnvironmentObject private var liveAudio: AudioController
    @State private var currentFrame: Int = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let engine = liveController.engine {
                GeometryReader { geo in
                    let size   = engine.canvasSize
                    let aspect = size.width / max(size.height, 1)
                    let fps    = engine.globalConfig.targetFPS
                    RenderSurfaceView(
                        engine:        engine,
                        playbackState: liveController.canvasPaused ? .paused : .playing,
                        onFrameTick:   { frame in
                            currentFrame = frame
                            liveAudio.syncTransport(
                                playbackState: liveController.canvasPaused ? .paused : .playing,
                                frame: frame, fps: fps, loop: true
                            )
                        },
                        ignoresAnimationEnd: true
                    )
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            liveModeBadge
            pauseButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(Color.red.opacity(0.6), lineWidth: 3)
        )
    }

    /// Toggles `canvasPaused` — the same flag already used to pause the
    /// canvas (and, via `syncTransport`'s `playbackState` argument above,
    /// Live's audio) while a sheet is presented. Reused here as a genuine
    /// user-facing pause, since both the visual and audio consequences are
    /// already exactly what's wanted: Live otherwise has no transport
    /// controls at all and just runs continuously.
    private var pauseButton: some View {
        HStack {
            Spacer()
            Button {
                liveController.canvasPaused.toggle()
            } label: {
                Image(systemName: liveController.canvasPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .modifier(LoomHoverHelp(liveController.canvasPaused ? "Resume Live playback" : "Pause Live playback"))
        }
    }

    private var liveModeBadge: some View {
        Label("LIVE", systemImage: "circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
            .padding(10)
    }
}
