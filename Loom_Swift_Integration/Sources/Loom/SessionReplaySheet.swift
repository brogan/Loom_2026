import AppKit
import SwiftUI
import AVFoundation
import LoomEngine

/// Renders a recorded Live-tab session to video — structurally mirrors
/// `Export/ExportSheet.swift`, but builds its own fresh, blank-stage
/// `Engine` (replay always starts from nothing, not "whatever the project
/// currently shows") and derives its frame range from the log itself
/// rather than `engine.maxAnimationFrames`. See `SessionReplayer` for the
/// actual per-frame event application, wired in as `VideoExporter`'s
/// `onBeforeFrame` hook.
struct SessionReplaySheet: View {

    let projectURL: URL
    let sessionURL: URL
    @EnvironmentObject private var controller: AppController
    @Environment(\.dismiss) private var dismiss

    @State private var engine: Engine?
    @State private var replayer: SessionReplayer?
    @State private var loadError: String?
    /// Set the moment `loadSession()` starts, cleared once it finishes —
    /// paired with `Text(_:style:.timer)` below so loading always shows a
    /// live-ticking elapsed time, not just a static spinner. A spinner alone
    /// looks identical whether the app is working or actually hung; a
    /// counter that keeps moving is unambiguous proof it isn't.
    @State private var loadStartedAt: Date?

    @State private var fps:        Int              = 30
    @State private var endFrame:   Int              = 0
    @State private var codec:      AVVideoCodecType = .h264
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var skippedSummary: String?
    /// Same reasoning as `loadStartedAt`, for the render itself.
    @State private var exportStartedAt: Date?

    private let fpsOptions:   [Int]                        = [24, 25, 30, 60]
    private let codecOptions: [(AVVideoCodecType, String)] = [
        (.h264, "H.264"), (.hevc, "HEVC (H.265)"), (.proRes4444, "ProRes 4444")
    ]

    private var totalFrames: Int { max(1, endFrame) }
    private var durationSeconds: Double { Double(totalFrames) / Double(fps) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Render Session").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 12)

            Divider()

            if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding()
            } else if let engine {
                Form {
                    Section("Session") {
                        LabeledContent("File") {
                            Text(sessionURL.lastPathComponent).foregroundStyle(.secondary)
                        }
                    }
                    Section("Canvas") {
                        LabeledContent("Size") {
                            Text("\(engine.globalConfig.width) × \(engine.globalConfig.height) px")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Quality") {
                            Text("\(engine.globalConfig.qualityMultiple)×").foregroundStyle(.secondary)
                        }
                    }
                    Section("Frame Range") {
                        HStack {
                            Text("End frame")
                            Spacer()
                            TextField("", value: $endFrame, format: .number)
                                .frame(width: 72)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Total frames") {
                            Text("\(totalFrames)").foregroundStyle(.secondary)
                        }
                        LabeledContent("Duration") {
                            Text(String(format: "%.2f s", durationSeconds)).foregroundStyle(.secondary)
                        }
                    }
                    Section("Video") {
                        Picker("Frame rate", selection: $fps) {
                            ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                        }
                        .pickerStyle(.segmented)

                        Picker("Codec", selection: $codec) {
                            ForEach(codecOptions, id: \.0.rawValue) { Text($1).tag($0) }
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(isExporting)
            } else {
                VStack(spacing: 4) {
                    ProgressView("Loading session…")
                    if let loadStartedAt {
                        Text(loadStartedAt, style: .timer)
                            .font(.caption).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding()
            }

            Divider()

            VStack(spacing: 8) {
                if isExporting {
                    ProgressView(value: controller.exportProgress).padding(.horizontal)
                    HStack(spacing: 4) {
                        Text("Frame \(Int(controller.exportProgress * Double(totalFrames))) of \(totalFrames)")
                        if let exportStartedAt {
                            Text("·")
                            Text(exportStartedAt, style: .timer).monospacedDigit()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                if let err = exportError {
                    Text(err).foregroundStyle(.red).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                if let skippedSummary {
                    Text(skippedSummary).foregroundStyle(.orange).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                HStack {
                    Button("Cancel") { dismiss() }.disabled(isExporting)
                    Spacer()
                    Button(isExporting ? "Rendering…" : "Render") { startExport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExporting || engine == nil || endFrame <= 0)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            LoomLogger.info("[SessionReplay] SessionReplaySheet appeared for \(sessionURL.lastPathComponent)")
            loadSession()
        }
    }

    /// Builds a fresh `Engine`, blanks its stage (same pattern as
    /// `LiveSessionController.ensureEngine`), parses the session log, and
    /// derives a default end frame from the log's last event plus a short
    /// tail so the last action isn't cut off abruptly.
    ///
    /// Runs the actual work on `Task.detached` — same reasoning as
    /// `startExport()`: this method is called from `.onAppear`, itself
    /// MainActor-isolated (a View method), so awaiting `Engine(projectDirectory:)`
    /// / log parsing directly here would block the main thread (and the
    /// "Loading session…" placeholder would never even get a chance to
    /// paint) for however long that work takes.
    private func loadSession() {
        let projectURL = self.projectURL
        let sessionURL = self.sessionURL
        loadStartedAt = Date()
        LoomLogger.info("[SessionReplay] loadSession starting: project=\(projectURL.path) session=\(sessionURL.path)")
        Task {
            LoomLogger.info("[SessionReplay] loadSession outer Task running (MainActor-inherited)")
            do {
                let (newEngine, newReplayer) = try await Task.detached(priority: .userInitiated) {
                    LoomLogger.info("[SessionReplay] detached task started, constructing Engine…")
                    let newEngine = try Engine(projectDirectory: projectURL)
                    LoomLogger.info("[SessionReplay] Engine constructed, hiding \(newEngine.spriteInstances.count) sprite instance(s)")
                    for instance in newEngine.spriteInstances {
                        newEngine.hideSprite(instanceName: instance.def.name)
                    }
                    LoomLogger.info("[SessionReplay] sprites hidden, loading events from \(sessionURL.lastPathComponent)")
                    let events = try SessionReplayer.loadEvents(from: sessionURL)
                    LoomLogger.info("[SessionReplay] loaded \(events.count) event(s), constructing SessionReplayer…")
                    let newReplayer = SessionReplayer(engine: newEngine, events: events)
                    LoomLogger.info("[SessionReplay] SessionReplayer constructed, maxEventFrame=\(newReplayer.maxEventFrame)")
                    return (newEngine, newReplayer)
                }.value
                LoomLogger.info("[SessionReplay] detached load task returned, updating UI state")
                fps = Int(newEngine.globalConfig.targetFPS)
                endFrame = newReplayer.maxEventFrame + 60
                engine = newEngine
                replayer = newReplayer
                LoomLogger.info("[SessionReplay] loadSession complete: fps=\(fps) endFrame=\(endFrame)")
            } catch {
                LoomLogger.error("[SessionReplay] loadSession failed", error: error)
                loadError = "Couldn't load session: \(error.localizedDescription)"
            }
            loadStartedAt = nil
        }
    }

    private func startExport() {
        guard let engine, let replayer, endFrame > 0 else {
            LoomLogger.warning("[SessionReplay] startExport called but guard failed (engine=\(engine != nil) replayer=\(replayer != nil) endFrame=\(endFrame))")
            return
        }
        LoomLogger.info("[SessionReplay] Render clicked, opening save panel")
        let name = sessionURL.deletingPathExtension().lastPathComponent
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.movie]
        panel.nameFieldStringValue = "\(name).mov"
        if let dir = controller.animationRendersDirectory() { panel.directoryURL = dir }

        let fps = self.fps; let endFrame = self.endFrame; let codec = self.codec

        panel.begin { response in
            LoomLogger.info("[SessionReplay] Save panel completed, response=\(response == .OK ? "OK" : "cancel"), url=\(panel.url?.path ?? "nil")")
            guard response == .OK, let url = panel.url else { return }
            isExporting = true
            exportStartedAt = Date()
            exportError = nil
            skippedSummary = nil
            controller.beginExport()
            Task {
                LoomLogger.info("[SessionReplay] export outer Task running (MainActor-inherited)")
                do {
                    let settings = VideoExporter.Settings(fps: fps, startFrame: 0, endFrame: endFrame,
                                                          codec: codec, outputURL: url)
                    let progress: @Sendable (Double) -> Void = { p in
                        Task { @MainActor in controller.exportProgress = p }
                    }
                    LoomLogger.info("[SessionReplay] launching detached export task: totalFrames=\(settings.totalFrames) fps=\(fps) codec=\(codec.rawValue) output=\(url.path)")
                    // VideoExporter's frame loop is CPU-bound with essentially
                    // no internal suspension points (only Task.yield() under
                    // encoder backpressure, rarely hit) — awaiting it directly
                    // from this Task would run the whole render synchronously
                    // on the main thread (this Task inherits MainActor
                    // isolation from startExport(), a View method), freezing
                    // the entire app for the render's duration: no button
                    // presses, no menu, not even Cmd+Q. Task.detached moves
                    // the actual work to a background thread; awaiting
                    // `.value` here just suspends this Task so the main run
                    // loop keeps processing events while the render happens.
                    try await Task.detached(priority: .userInitiated) {
                        LoomLogger.info("[SessionReplay] detached export task started")
                        try await VideoExporter().export(
                            engine: engine, settings: settings, progress: progress,
                            onBeforeFrame: { frame in replayer.applyFrame(frame) }
                        )
                        LoomLogger.info("[SessionReplay] VideoExporter.export returned normally")
                    }.value
                    LoomLogger.info("[SessionReplay] detached export task awaited/joined, updating UI state")
                    controller.endExport()
                    isExporting = false
                    exportStartedAt = nil
                    if !replayer.skippedEventDescriptions.isEmpty {
                        skippedSummary = "Skipped \(replayer.skippedEventDescriptions.count) event(s) during render:\n"
                            + replayer.skippedEventDescriptions.joined(separator: "\n")
                    } else {
                        dismiss()
                    }
                    LoomLogger.info("[SessionReplay] export flow complete")
                } catch {
                    LoomLogger.error("[SessionReplay] export failed", error: error)
                    exportError = error.localizedDescription
                    controller.endExport(error: error)
                    isExporting = false
                    exportStartedAt = nil
                }
            }
        }
    }
}
