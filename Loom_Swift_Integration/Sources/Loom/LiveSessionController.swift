import Foundation
import LoomEngine

/// Owns the Live tab's own independent `Engine` instance, entirely separate
/// from `AppController.engine` — see `PerformanceArchitecture.md` §0.1 and
/// `LoomLiveV1Scope.md` §2.1. Ordinary inspector edits elsewhere still go
/// through `AppController`'s save→reload cycle, which only ever replaces
/// `AppController.engine`; this controller's `engine` is untouched by that,
/// so sprites staged here are never silently discarded by unrelated edits.
///
/// Also owns the semantic "staged sprite" model. `LoomEngine.hideSprite` is
/// destructive (array removal), so it can't remember a sprite's pose/set/
/// driver state across a hide→show round trip — this controller keeps that
/// richer record and replays the right sequence of engine calls to restore
/// it. The engine mutators stay dumb, minimal scene-mutation primitives,
/// generic over `LiveDriverTarget`'s keypaths (see `LiveDriverTarget.swift`)
/// so this covers sprite drivers, transform-set-pass drivers, and
/// renderer-entry drivers uniformly.
///
/// Also records every interaction as a `LiveEvent` (`SessionWorkflow.md`
/// §3.2) — a new session log starts each time `ensureEngine` builds a fresh
/// engine, written incrementally (append-only, one JSON Lines record per
/// event) to `<project>/sessions/`, so a crash mid-session loses at most the
/// last unwritten event, not the whole take.
///
/// ### Threading
/// `Engine`/`LoomEngine` are explicitly not thread-safe, and the same
/// `Engine` instance driving this tab's canvas is mutated/read every frame
/// on `RenderSurfaceNSView.sharedRenderQueue` (`RenderSurfaceNSView.tick()`).
/// Every engine call below therefore runs on that same serial queue rather
/// than directly on the caller's (main) thread, so a live mutation can never
/// race the render loop's concurrent `update`/`makeFrame`. UI-facing
/// `@Published` state is only ever updated back on the main actor, after the
/// engine call completes — and events are recorded with the frame number
/// read at that same point, not whenever the user's gesture originated.
@MainActor
final class LiveSessionController: ObservableObject {

    /// A configured driver's live-tunable "Rate"/"Range" controls. "Rate"
    /// applies only to oscillator/noise modes (jitter re-rolls every frame
    /// with no periodicity); "Range" applies to all three. Bounds are
    /// captured once at stage time, scaled from whatever the driver's own
    /// authored value already was, so the slider stays sensibly scoped
    /// without needing the user to set a range first.
    struct DriverControlInfo: Equatable {
        var mode: String       // Mode rawValue: "oscillator"/"noise"/"jitter"
        var isVector: Bool
        var hasRate: Bool
        var rateX: Double = 0
        var rateY: Double = 0  // meaningful only when isVector && mode == "oscillator"
        var rangeX: Double = 0
        var rangeY: Double = 0 // meaningful only when isVector
        var rateBounds: ClosedRange<Double> = 0...10
        var rangeBounds: ClosedRange<Double> = 0...10
        /// Non-nil when Rate is BPM-linked (cycles/bar) instead of a manual
        /// slider value — `LoomLiveV1Scope.md` §2.6. `rateX`/`rateY` still
        /// hold the computed `freqHz` for display; this is what the UI
        /// checks to decide which control to show.
        var musicalMultiplier: Double? = nil

        private static func bounds(_ current: Double) -> ClosedRange<Double> {
            let upper = current > 0 ? current * 2 : 10
            return 0...max(upper, 0.001)
        }

        static func make(from d: DoubleDriver) -> DriverControlInfo? {
            guard d.mode == .oscillator || d.mode == .noise || d.mode == .jitter else { return nil }
            let rate  = d.mode == .oscillator ? d.freqHz : Double(d.period)
            let range = d.mode == .jitter ? d.range : d.amplitude
            return DriverControlInfo(
                mode: d.mode.rawValue, isVector: false, hasRate: d.mode != .jitter,
                rateX: rate, rangeX: range, rateBounds: bounds(rate), rangeBounds: bounds(range)
            )
        }

        static func make(from d: VectorDriver) -> DriverControlInfo? {
            guard d.mode == .oscillator || d.mode == .noise || d.mode == .jitter else { return nil }
            let rateX  = d.mode == .oscillator ? d.freqHz.x : Double(d.period)
            let rateY  = d.mode == .oscillator ? d.freqHz.y : Double(d.period)
            let rangeX = d.mode == .jitter ? d.range.x : d.amplitude.x
            let rangeY = d.mode == .jitter ? d.range.y : d.amplitude.y
            return DriverControlInfo(
                mode: d.mode.rawValue, isVector: true, hasRate: d.mode != .jitter,
                rateX: rateX, rateY: rateY, rangeX: rangeX, rangeY: rangeY,
                rateBounds: bounds(max(rateX, rateY)), rangeBounds: bounds(max(rangeX, rangeY))
            )
        }

        static func make(from d: ColorDriver) -> DriverControlInfo? {
            guard d.mode == .oscillator || d.mode == .noise || d.mode == .jitter else { return nil }
            let rate  = d.mode == .oscillator ? d.freqHz : Double(d.period)
            let range = d.mode == .jitter ? d.range : d.amplitude
            return DriverControlInfo(
                mode: d.mode.rawValue, isVector: false, hasRate: d.mode != .jitter,
                rateX: rate, rangeX: range, rateBounds: bounds(rate), rangeBounds: bounds(range)
            )
        }
    }

    struct StagedSprite: Identifiable, Equatable {
        let id: String                  // == engine instanceName, unique per stage action
        var spriteSetName: String
        var spriteDefName: String       // source SpriteDef.name as picked from the browser
        var isVisible: Bool = true
        var position: Vector2D
        var scale: Vector2D
        var rotation: Double
        var rendererSetName: String? = nil
        var subdivisionSetName: String? = nil

        /// Every driver field discovered as configured when staged — sprite
        /// fields plus anything found on the assigned transform/renderer
        /// sets (`LiveDriverDiscoverer.discover`). This list itself IS the
        /// "relevant drivers" filter; order is preserved for the navigator.
        var driverTargets: [LiveDriverTarget] = []
        var driverLabels: [LiveDriverTarget: String] = [:]
        var driverEnabled: [LiveDriverTarget: Bool] = [:]
        /// Absent for name-drivers (subdivisionSet/rendererSet/cycleName),
        /// which have no rate/range concept.
        var driverControls: [LiveDriverTarget: DriverControlInfo] = [:]
    }

    @Published private(set) var engine: Engine?
    @Published private(set) var loadedProjectURL: URL?
    @Published private(set) var loadError: String?
    /// Pauses the Live canvas (and, via `syncTransport`'s `playbackState`
    /// argument, `liveAudio` alongside it) — two callers: automatically
    /// while a sheet (e.g. `SessionReplaySheet`) is presented over the Live
    /// tab, and manually via `LiveCanvasView`'s pause button, since Live
    /// otherwise has no transport controls at all and just runs
    /// continuously. `LiveCanvasView`'s canvas otherwise animates
    /// continuously (`playbackState: .playing` when this is false) via a
    /// 60fps `Timer` added to `RunLoop.main` in `.common` mode — which keeps
    /// firing during a sheet's modal/attach transition, issuing a
    /// `CATransaction` commit to that same window every tick. Presenting a
    /// new sheet on a window whose content is being aggressively,
    /// continuously redrawn like that is a known class of AppKit deadlock
    /// (the sheet-attach animation and the competing layer commits can lock
    /// each other out) — pausing the render loop for the sheet's duration
    /// avoids it.
    @Published var canvasPaused: Bool = false

    @Published private(set) var stagedSprites: [StagedSprite] = []
    @Published var selectedStagedID: StagedSprite.ID?
    @Published var selectedDriverTarget: LiveDriverTarget?

    /// Live mode's own audio track — entirely separate from the main
    /// timeline's `AudioController` (a different instance, pointed at
    /// `sessions/audio`/`sessions/live_audio.json` instead of `audio`/
    /// `audio.json`, so the two never collide). Tied to the Live engine's
    /// own never-stopping clock via `LiveCanvasView`'s `onFrameTick`, not to
    /// the main timeline, which is what made the old approach (referencing
    /// the main timeline's audio while in Live mode) unreliable — that
    /// timeline doesn't even tick while the Live tab is open. Not
    /// `@Published` — SwiftUI views observe `liveAudio` directly via their
    /// own `@EnvironmentObject`, since nesting one `ObservableObject`
    /// inside another doesn't forward its change notifications.
    let liveAudio = AudioController()

    private var nextInstanceSuffix = 1
    /// Coalesces rapid slider-drag updates: a new call cancels any not-yet-
    /// fired update for the same (sprite, target, quantity), so a fast drag
    /// collapses to "latest value wins" with a ~1-frame debounce, instead of
    /// flooding the render queue with every intermediate drag position.
    private var pendingDriverTasks: [String: Task<Void, Never>] = [:]

    // MARK: - BPM-linked musical rate (LoomLiveV1Scope.md §2.6)

    @Published var bpm: Double = 120
    @Published var beatsPerBar: Int = 4
    /// The engine frame tapped as a bar's first beat, or `nil` if never
    /// tapped this session — musically-linked drivers align their phase to
    /// this frame; with no tap, phase defaults to 0 (aligned to engine
    /// start instead of a bar boundary).
    @Published private(set) var barReferenceFrame: Int?

    // MARK: - Session recording
    //
    // Recording is explicit and opt-in — opening/using the Live tab records
    // nothing on its own; only `startRecording` does. This matters for
    // Phase 2 (replay-to-render): a session file is meant to be one
    // deliberate take, not "everything that happened since the tab was
    // last opened."

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var sessionEvents: [LiveEvent] = []
    @Published private(set) var sessionLogURL: URL?
    private var sessionFileHandle: FileHandle?
    /// The engine frame of the *first* event recorded this session — every
    /// recorded `t` is rebased against this, so frame 0 in the log always
    /// means "the first thing that actually happened," not "whenever the
    /// Live tab's engine happened to be created." The engine's own clock
    /// keeps ticking for as long as the tab is open, well before or after
    /// any particular recording; without this, replay would render however
    /// long the tab sat open before Start was pressed as blank leading frames.
    private var recordingStartFrame: Int?

    /// Starts a new recording named `name` (sanitized for the filesystem; a
    /// blank name falls back to a timestamp) in `<projectDirectory>/sessions/`
    /// — `LoomLiveV1Scope.md` §2.5's "exactly one new thing added to the
    /// project directory." A name that collides with an existing file gets
    /// a numeric suffix rather than silently overwriting an earlier take.
    /// Stops any in-progress recording first. Failure to create the
    /// folder/file is non-fatal: recording just becomes in-memory-only
    /// (`sessionEvents` still fills in, `sessionFileHandle` stays nil and
    /// `recordEvent` skips the write) rather than blocking Live tab use over
    /// a filesystem hiccup.
    func startRecording(name: String) {
        guard let projectURL = loadedProjectURL else { return }
        stopRecording()
        sessionEvents = []
        recordingStartFrame = nil

        let sessionsDir = projectURL.appendingPathComponent("sessions")
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let base = Self.sanitizedSessionName(name) ?? Self.timestampedSessionName()
        let url = Self.uniqueSessionURL(in: sessionsDir, base: base)

        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
        sessionFileHandle = try? FileHandle(forWritingTo: url)
        sessionLogURL = url
        isRecording = true

        // Snapshot whatever's already staged and visible so the recording's
        // baseline reflects reality, not each sprite's authored defaults —
        // without this, a sprite configured (custom transform/renderer/pose)
        // *before* Start was pressed would silently replay as if none of
        // that setup had ever happened, since none of it was ever recorded.
        // Same reasoning applies to audio imported before Start: without
        // this, a render would silently have no audio even though it was
        // playing throughout the whole take. And to BPM/beats-per-bar/tap
        // sync: neither persists across a project reopen (`bpm`/
        // `beatsPerBar` reset to 120/4 every time `ensureEngine` runs), so
        // dialing in a tempo before Start — the natural order, same as
        // staging a sprite or importing audio first — left `SessionReplayer`
        // with nothing but its own 120bpm default for every musically-linked
        // driver, silently replaying eighth notes (etc.) at the wrong speed
        // even though the live take itself was correctly in time. Recorded
        // unconditionally (unlike the sprite/audio snapshots, which are
        // skipped when there's nothing to snapshot) since 120/4 is itself a
        // meaningful, worth-recording baseline, not a "nothing configured" case.
        guard let engine else { return }
        let visibleStaged = stagedSprites.filter(\.isVisible)
        let hasAudio = liveAudio.audioFilename != nil
        RenderSurfaceNSView.sharedRenderQueue.async { [weak self] in
            let frame = engine.currentFrame
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recordEvent(.bpmSet(t: frame, bpm: self.bpm, beatsPerBar: self.beatsPerBar))
                    if let barReferenceFrame = self.barReferenceFrame {
                        self.recordEvent(.tapSync(t: frame, referenceFrame: barReferenceFrame))
                    }
                    for staged in visibleStaged { self.recordStagedSnapshot(staged, at: frame) }
                    if hasAudio { self.recordAudioSet() }
                }
            }
        }
    }

    /// Records `staged`'s full current state as a batch of events at
    /// `frame` — pose, renderer/transform-set assignment, every known
    /// driver's enabled state, and (for configured drivers) their current
    /// Rate/Range or musical-multiplier — not just a bare `spriteShow`
    /// position. Used both to snapshot whatever's already staged the moment
    /// recording starts, and whenever a sprite is (re)shown during an
    /// already-active recording (`setVisible`), since `replayShow` restores
    /// this same full state on the engine side but the old recording only
    /// ever captured the position.
    private func recordStagedSnapshot(_ staged: StagedSprite, at frame: Int) {
        recordEvent(.spriteShow(
            t: frame, instanceName: staged.id, spriteSetName: staged.spriteSetName,
            spriteName: staged.spriteDefName, position: staged.position,
            scale: staged.scale, rotation: staged.rotation
        ))
        if let rendererSetName = staged.rendererSetName {
            recordEvent(.rendererSetAssign(t: frame, instanceName: staged.id, rendererSetName: rendererSetName))
        }
        if let subdivisionSetName = staged.subdivisionSetName {
            recordEvent(.transformSetAssign(t: frame, instanceName: staged.id, subdivisionSetName: subdivisionSetName))
        }
        for target in staged.driverTargets {
            let enabled = staged.driverEnabled[target] ?? false
            recordEvent(.driverEnabledToggle(t: frame, instanceName: staged.id, target: target, enabled: enabled))
            guard let info = staged.driverControls[target] else { continue }
            if let multiplier = info.musicalMultiplier {
                recordEvent(.driverMusicalRateAssign(t: frame, instanceName: staged.id, target: target, multiplier: multiplier))
            } else if info.hasRate {
                recordEvent(.driverAutomationPoint(
                    t: frame, instanceName: staged.id, target: target, quantity: "rate",
                    axis: info.isVector ? "x" : nil, value: info.rateX
                ))
                if info.isVector {
                    recordEvent(.driverAutomationPoint(
                        t: frame, instanceName: staged.id, target: target, quantity: "rate", axis: "y", value: info.rateY
                    ))
                }
            }
            recordEvent(.driverAutomationPoint(
                t: frame, instanceName: staged.id, target: target, quantity: "range",
                axis: info.isVector ? "x" : nil, value: info.rangeX
            ))
            if info.isVector {
                recordEvent(.driverAutomationPoint(
                    t: frame, instanceName: staged.id, target: target, quantity: "range", axis: "y", value: info.rangeY
                ))
            }
        }
    }

    /// Stops the current recording (closing the file) — a no-op if nothing
    /// was recording. `sessionEvents`/`sessionLogURL` are left as-is so the
    /// UI can still show what was just captured until the next recording starts.
    ///
    /// Records a `.sessionEnd` marker first, at the engine's current frame,
    /// while `isRecording` is still true so it goes through the normal
    /// `recordEvent` rebase/write path — this captures the true end of the
    /// take even when idle time (nothing else happening) preceded Stop,
    /// which otherwise leaves nothing in the log to distinguish "the take
    /// ended right after the last action" from "it continued a while
    /// longer with nothing happening." Replay prefers this over
    /// "last event + a short tail" when choosing a default render length —
    /// see `SessionReplaySheet.loadSession`.
    func stopRecording() {
        if isRecording, let engine {
            recordEvent(.sessionEnd(t: engine.currentFrame))
        }
        sessionFileHandle?.closeFile()
        sessionFileHandle = nil
        isRecording = false
    }

    /// Internal (not `private`) — `EventTimelineSheet`'s "Save Copy…" reuses
    /// this exact collision-safe naming so an edited session never silently
    /// overwrites the original recording, the same guarantee recording
    /// itself already gives.
    static func sanitizedSessionName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return trimmed.components(separatedBy: invalid).joined(separator: "_")
    }

    static func timestampedSessionName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "session_" + formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    static func uniqueSessionURL(in dir: URL, base: String) -> URL {
        var candidate = dir.appendingPathComponent("\(base).jsonl")
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)_\(i).jsonl")
            i += 1
        }
        return candidate
    }

    /// Appends one event to the in-memory log and, if currently recording,
    /// writes it as one JSON Lines record (a flat JSON object per line, no
    /// enclosing array) — the natural on-disk shape for an append-only log,
    /// trivially convertible to a JSON array later if a future editor UI
    /// wants one. A no-op when not recording — every mutator below calls
    /// this unconditionally; the gating lives here, in one place.
    ///
    /// `event.t` is rebased against the frame of the *first* event recorded
    /// this session, so frame 0 in the log always means "the first thing
    /// that actually happened" rather than "whenever the Live tab's engine
    /// was created" — the engine's clock ticks continuously for as long as
    /// the tab is open, independent of when Start was pressed, so without
    /// this rebase, replay would render that idle gap as blank leading frames.
    private func recordEvent(_ event: LiveEvent) {
        guard isRecording else { return }
        if recordingStartFrame == nil {
            recordingStartFrame = event.t
            // The Live engine's clock ticks continuously from whenever the
            // tab was opened, not from Start — so any project-authored
            // content that isn't itself tracked as a LiveEvent (camera
            // keyframes/drivers, background) has typically already moved
            // past its opening moments by the time recording begins.
            // Recording where the engine's raw clock actually was lets
            // replay seek a fresh engine to the same point before applying
            // the session's own events, instead of showing that content
            // from its own beginning — see `SessionReplaySheet.loadSession`.
            appendAndWrite(.sessionStart(t: 0, engineFrameAtStart: event.t))
        }
        let baseline = recordingStartFrame ?? 0
        var rebased = event.withT(max(0, event.t - baseline))
        // `offsetFrames` is an absolute engine-clock frame like `t` (where
        // audio position 0 plays), not a duration — `withT` above only
        // rebases `t` itself, so this field needs the same treatment
        // applied separately. Can go negative (audio already playing when
        // recording started); left as-is rather than clamped, since a
        // negative offset is a meaningful "already N frames in" state that
        // `AudioController.syncTransport`/Review's derivation can interpret
        // directly, not an error case.
        if case .audioSet(let t, let filename, let offsetFrames) = rebased {
            rebased = .audioSet(t: t, filename: filename, offsetFrames: offsetFrames - baseline)
        }
        appendAndWrite(rebased)
    }

    private func appendAndWrite(_ event: LiveEvent) {
        sessionEvents.append(event)
        guard let handle = sessionFileHandle,
              let data = try? JSONEncoder().encode(event),
              let line = String(data: data, encoding: .utf8),
              let lineData = (line + "\n").data(using: .utf8)
        else { return }
        handle.write(lineData)
    }

    // MARK: - Live audio

    /// Imports a file into `liveAudio` and records the resulting reference —
    /// mirrors the `stage()`/`assignRendererSet()` shape (mutate the live
    /// state, then record it) rather than passively observing `liveAudio`
    /// for changes.
    func importLiveAudio(from url: URL) {
        liveAudio.importAudio(from: url)
        recordAudioSet()
    }

    /// Adjusts `liveAudio`'s offset and records the change — called from
    /// both the Live tab's own numeric field and (later) the Review panel's
    /// drag-to-offset editing of an already-recorded session.
    func setLiveAudioOffset(_ frames: Int) {
        liveAudio.setOffset(frames)
        recordAudioSet()
    }

    private func recordAudioSet() {
        guard let filename = liveAudio.audioFilename else { return }
        recordEvent(.audioSet(t: engine?.currentFrame ?? 0, filename: filename, offsetFrames: liveAudio.offsetFrames))
    }

    /// (Re)builds the Live tab's engine from `projectURL` if it isn't already
    /// pointed at that project. A no-op when called again for the same URL,
    /// so it's safe to call from `.onAppear` every time the tab is shown.
    func ensureEngine(projectURL: URL) {
        guard loadedProjectURL != projectURL else { return }
        do {
            let newEngine = try Engine(projectDirectory: projectURL)
            // Start from a blank stage — the Live tab works against the
            // project's sprite/transform/renderer *sets*, not whatever the
            // project's own sprites.xml happens to place on canvas by default.
            for instance in newEngine.spriteInstances {
                newEngine.hideSprite(instanceName: instance.def.name)
            }
            stopRecording()
            sessionEvents = []
            sessionLogURL = nil
            engine = newEngine
            loadedProjectURL = projectURL
            loadError = nil
            stagedSprites = []
            selectedStagedID = nil
            selectedDriverTarget = nil
            bpm = 120
            beatsPerBar = 4
            barReferenceFrame = nil
            liveAudio.projectOpened(projectURL, subdirectory: "sessions/audio", stateFilename: "sessions/live_audio.json")
        } catch {
            engine = nil
            loadedProjectURL = nil
            loadError = error.localizedDescription
        }
    }

    // MARK: - Staging

    func stage(spriteSetName: String, spriteName: String) {
        guard let engine else { return }
        let instanceName = "live_\(spriteName)_\(nextInstanceSuffix)"
        nextInstanceSuffix += 1
        let position = Vector2D.zero
        let scale    = Vector2D(x: 1, y: 1)
        let rotation = 0.0

        RenderSurfaceNSView.sharedRenderQueue.async {
            do {
                try? engine.refreshProjectConfig()
                try engine.showSprite(
                    spriteSetName: spriteSetName, spriteName: spriteName, instanceName: instanceName,
                    position: position, scale: scale, rotation: rotation
                )
                // Read back the actual resolved instance so the Live tab
                // reflects reality — which drivers this sprite's own
                // authoring (and its assigned transform/renderer sets)
                // configured, and their real current values.
                guard let instance = engine.spriteInstances.first(where: { $0.def.name == instanceName }) else { return }
                let discovered = LiveDriverDiscoverer.discover(in: instance)
                var targets: [LiveDriverTarget] = []
                var labels: [LiveDriverTarget: String] = [:]
                var enabledMap: [LiveDriverTarget: Bool] = [:]
                var controlsMap: [LiveDriverTarget: DriverControlInfo] = [:]
                for d in discovered {
                    targets.append(d.target)
                    labels[d.target] = d.label
                    enabledMap[d.target] = d.enabled
                    if let info = d.controlInfo { controlsMap[d.target] = info }
                }
                let frame = engine.currentFrame
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.stagedSprites.append(StagedSprite(
                            id: instanceName, spriteSetName: spriteSetName, spriteDefName: spriteName,
                            position: position, scale: scale, rotation: rotation,
                            driverTargets: targets, driverLabels: labels,
                            driverEnabled: enabledMap, driverControls: controlsMap
                        ))
                        self.selectedStagedID = instanceName
                        self.selectedDriverTarget = nil
                        self.recordEvent(.spriteShow(
                            t: frame, instanceName: instanceName, spriteSetName: spriteSetName,
                            spriteName: spriteName, position: position, scale: scale, rotation: rotation
                        ))
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func setVisible(_ id: StagedSprite.ID, _ visible: Bool) {
        guard let engine, let staged = stagedSprites.first(where: { $0.id == id }) else { return }
        stagedSprites[stagedSprites.firstIndex(where: { $0.id == id })!].isVisible = visible
        let bpm = self.bpm
        let beatsPerBar = self.beatsPerBar
        let barReferenceFrame = self.barReferenceFrame
        RenderSurfaceNSView.sharedRenderQueue.async {
            if visible {
                Self.replayShow(staged, engine: engine, bpm: bpm, beatsPerBar: beatsPerBar, barReferenceFrame: barReferenceFrame)
            } else {
                engine.hideSprite(instanceName: id)
            }
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    if visible {
                        // Full snapshot, not just position — `replayShow`
                        // above just restored renderer/transform-set/driver
                        // state on the engine too, and the recording needs
                        // to capture all of that, not only the bare show.
                        self?.recordStagedSnapshot(staged, at: frame)
                    } else {
                        self?.recordEvent(.spriteHide(t: frame, instanceName: id))
                    }
                }
            }
        }
    }

    /// Removes a staged instance entirely — unlike `setVisible(_:false)`,
    /// which just hides it while keeping its pose/driver configuration
    /// around for a later re-show, this drops it from `stagedSprites` for
    /// good. The only way back is re-staging from scratch. Always records a
    /// `spriteHide` (regardless of whether it was currently visible) since,
    /// from the session log's perspective, this is unambiguously where that
    /// instance's visibility span ends.
    func destage(_ id: StagedSprite.ID) {
        guard let engine, stagedSprites.contains(where: { $0.id == id }) else { return }
        stagedSprites.removeAll { $0.id == id }
        if selectedStagedID == id {
            selectedStagedID = nil
            selectedDriverTarget = nil
        }
        RenderSurfaceNSView.sharedRenderQueue.async {
            engine.hideSprite(instanceName: id)
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.recordEvent(.spriteHide(t: frame, instanceName: id))
                }
            }
        }
    }

    /// Replays the compound sequence of engine calls needed to restore a
    /// staged sprite's configured pose/set/driver state after a hide→show
    /// round trip (`showSprite` is a bare instantiation with no memory of
    /// prior configuration). Runs entirely on the caller's queue — callers
    /// are responsible for already being on `RenderSurfaceNSView.sharedRenderQueue`.
    nonisolated private static func replayShow(
        _ staged: StagedSprite, engine: Engine, bpm: Double, beatsPerBar: Int, barReferenceFrame: Int?
    ) {
        try? engine.refreshProjectConfig()
        try? engine.showSprite(
            spriteSetName: staged.spriteSetName, spriteName: staged.spriteDefName, instanceName: staged.id,
            position: staged.position, scale: staged.scale, rotation: staged.rotation
        )
        if let rendererSetName = staged.rendererSetName {
            try? engine.updateRendererSet(instanceName: staged.id, rendererSetName: rendererSetName)
        }
        if let subdivisionSetName = staged.subdivisionSetName {
            try? engine.updateSubdivisionSet(instanceName: staged.id, subdivisionSetName: subdivisionSetName)
        }
        for (target, enabled) in staged.driverEnabled {
            applyEnabled(target, engine: engine, instanceName: staged.id, enabled: enabled)
        }
        for (target, info) in staged.driverControls {
            if let multiplier = info.musicalMultiplier {
                let (rate, phase) = musicalRateAndPhase(
                    mode: info.mode, multiplier: multiplier, bpm: bpm, beatsPerBar: beatsPerBar,
                    barReferenceFrame: barReferenceFrame, targetFPS: engine.globalConfig.targetFPS
                )
                applyRateRange(
                    target, engine: engine, instanceName: staged.id,
                    rateX: rate, rateY: rate, rangeX: info.rangeX, rangeY: info.rangeY,
                    phaseX: phase, phaseY: phase
                )
            } else {
                applyRateRange(
                    target, engine: engine, instanceName: staged.id,
                    rateX: info.hasRate ? info.rateX : nil, rateY: info.hasRate ? info.rateY : nil,
                    rangeX: info.rangeX, rangeY: info.rangeY
                )
            }
        }
    }

    /// Dispatches an enabled-toggle to whichever engine call matches
    /// `target`'s driver kind (Double/Vector/Color/Name) — the one place
    /// bridging `LiveDriverTarget`'s type-erased keypath options to the
    /// engine's generic, kind-specific mutators. Reads the current instance
    /// first since `LiveDriverTarget`'s keypaths resolve a pass/renderer
    /// *name* to its current array index, which can only be answered
    /// against live state (see `LiveDriverTarget.doubleKeyPath(in:)`).
    /// Internal (not `private`) so `SessionReplayer` can reuse the exact
    /// same dispatch when replaying a recorded session — one mutation API,
    /// two callers.
    nonisolated static func applyEnabled(
        _ target: LiveDriverTarget, engine: Engine, instanceName: String, enabled: Bool
    ) {
        guard let instance = engine.spriteInstances.first(where: { $0.def.name == instanceName }) else { return }
        if let kp = target.doubleKeyPath(in: instance) {
            try? engine.setDriverEnabled(instanceName: instanceName, keyPath: kp, enabled: enabled)
        } else if let kp = target.vectorKeyPath(in: instance) {
            try? engine.setDriverEnabled(instanceName: instanceName, keyPath: kp, enabled: enabled)
        } else if let kp = target.colorKeyPath(in: instance) {
            try? engine.setDriverEnabled(instanceName: instanceName, keyPath: kp, enabled: enabled)
        } else if let kp = target.nameKeyPath(in: instance) {
            try? engine.setDriverEnabled(instanceName: instanceName, keyPath: kp, enabled: enabled)
        }
    }

    /// Rate/Range counterpart of `applyEnabled` — name-drivers have no
    /// rate/range concept and are silently skipped.
    nonisolated static func applyRateRange(
        _ target: LiveDriverTarget, engine: Engine, instanceName: String,
        rateX: Double? = nil, rateY: Double? = nil, rangeX: Double? = nil, rangeY: Double? = nil,
        phaseX: Double? = nil, phaseY: Double? = nil
    ) {
        guard let instance = engine.spriteInstances.first(where: { $0.def.name == instanceName }) else { return }
        if let kp = target.doubleKeyPath(in: instance) {
            try? engine.updateDoubleDriverRateRange(instanceName: instanceName, keyPath: kp, rate: rateX, range: rangeX, phase: phaseX)
        } else if let kp = target.vectorKeyPath(in: instance) {
            try? engine.updateVectorDriverRateRange(
                instanceName: instanceName, keyPath: kp, rateX: rateX, rateY: rateY, rangeX: rangeX, rangeY: rangeY,
                phaseX: phaseX, phaseY: phaseY)
        } else if let kp = target.colorKeyPath(in: instance) {
            try? engine.updateColorDriverRateRange(instanceName: instanceName, keyPath: kp, rate: rateX, range: rangeX, phase: phaseX)
        }
    }

    /// Converts a BPM-linked musical multiplier (cycles/bar) into `freqHz`
    /// (plain arithmetic — the multiplier's unit already matches `freqHz`'s
    /// cycles/second once divided through bar duration) and the `phase`
    /// that aligns the driver's cycle-start to `barReferenceFrame`, derived
    /// directly from `DriverEvaluator`'s own oscillator formula
    /// (`t = elapsed * freqHz / fps + phase`) solved for `phase` at
    /// `elapsed == barReferenceFrame`. No tap yet → phase 0 (aligns to
    /// engine start rather than a bar boundary, still deterministic).
    nonisolated static func musicalFreqHzAndPhase(
        multiplier: Double, bpm: Double, beatsPerBar: Int, barReferenceFrame: Int?, targetFPS: Double
    ) -> (freqHz: Double, phase: Double) {
        let freqHz = multiplier * bpm / (60.0 * Double(max(1, beatsPerBar)))
        guard let ref = barReferenceFrame, targetFPS > 0 else { return (freqHz, 0) }
        let raw = -(Double(ref) * freqHz / targetFPS)
        let phase = raw - raw.rounded(.down)
        return (freqHz, phase)
    }

    /// Converts the BPM-linked cycles/second into whatever `applyRateRange`'s
    /// `rate` parameter actually expects for `mode` — `freqHz` directly for
    /// oscillator, but a frame-count period for noise (matching
    /// `DoubleDriver.applyRateRange`'s own per-mode convention). Noise mode
    /// has no phase concept at all (`DriverEvaluator`'s noise case never
    /// reads it), so `phase` comes back `nil` there — tap-to-sync only ever
    /// does anything for oscillator-mode drivers.
    nonisolated static func musicalRateAndPhase(
        mode: String, multiplier: Double, bpm: Double, beatsPerBar: Int, barReferenceFrame: Int?, targetFPS: Double
    ) -> (rate: Double, phase: Double?) {
        let (freqHz, phase) = musicalFreqHzAndPhase(
            multiplier: multiplier, bpm: bpm, beatsPerBar: beatsPerBar,
            barReferenceFrame: barReferenceFrame, targetFPS: targetFPS
        )
        if mode == "noise" {
            let rate = freqHz > 0 ? targetFPS / freqHz : targetFPS
            return (rate, nil)
        }
        return (freqHz, phase)
    }

    func updatePose(_ id: StagedSprite.ID, position: Vector2D, scale: Vector2D, rotation: Double) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].position = position
        stagedSprites[idx].scale    = scale
        stagedSprites[idx].rotation = rotation
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.updatePose(instanceName: id, position: position, scale: scale, rotation: rotation)
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.recordEvent(.poseUpdate(t: frame, instanceName: id, position: position, scale: scale, rotation: rotation))
                }
            }
        }
    }

    func assignRendererSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, stagedSprites.contains(where: { $0.id == id }) else { return }
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.refreshProjectConfig()
            do {
                try engine.updateRendererSet(instanceName: id, rendererSetName: name)
                let frame = engine.currentFrame
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, let idx = self.stagedSprites.firstIndex(where: { $0.id == id }) else { return }
                        self.stagedSprites[idx].rendererSetName = name
                        self.recordEvent(.rendererSetAssign(t: frame, instanceName: id, rendererSetName: name))
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func assignSubdivisionSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, stagedSprites.contains(where: { $0.id == id }) else { return }
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.refreshProjectConfig()
            do {
                try engine.updateSubdivisionSet(instanceName: id, subdivisionSetName: name)
                let frame = engine.currentFrame
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, let idx = self.stagedSprites.firstIndex(where: { $0.id == id }) else { return }
                        self.stagedSprites[idx].subdivisionSetName = name
                        self.recordEvent(.transformSetAssign(t: frame, instanceName: id, subdivisionSetName: name))
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func toggleDriver(_ id: StagedSprite.ID, _ target: LiveDriverTarget, _ enabled: Bool) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].driverEnabled[target] = enabled
        RenderSurfaceNSView.sharedRenderQueue.async {
            Self.applyEnabled(target, engine: engine, instanceName: id, enabled: enabled)
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.recordEvent(.driverEnabledToggle(t: frame, instanceName: id, target: target, enabled: enabled))
                }
            }
        }
    }

    /// Drags `target`'s Rate slider(s) live. `x` is always supplied; `y` only
    /// for a vector driver's oscillator mode (independent per-axis frequency).
    /// Recording happens inside the same coalesced commit as the engine
    /// update (not on every raw drag tick) — see `scheduleDriverUpdate`.
    func updateDriverRate(_ id: StagedSprite.ID, _ target: LiveDriverTarget, x: Double, y: Double? = nil) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              var info = stagedSprites[idx].driverControls[target] else { return }
        info.rateX = x
        if let y { info.rateY = y }
        stagedSprites[idx].driverControls[target] = info
        scheduleDriverUpdate(token: "\(id)|\(target)|rate") { [weak self] in
            Self.applyRateRange(target, engine: engine, instanceName: id, rateX: x, rateY: y)
            let frame = engine.currentFrame
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.recordAutomationPoint(id: id, target: target, quantity: "rate", x: x, y: y, frame: frame)
                }
            }
        }
    }

    /// Drags `target`'s Range slider(s) live.
    func updateDriverRange(_ id: StagedSprite.ID, _ target: LiveDriverTarget, x: Double, y: Double? = nil) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              var info = stagedSprites[idx].driverControls[target] else { return }
        info.rangeX = x
        if let y { info.rangeY = y }
        stagedSprites[idx].driverControls[target] = info
        scheduleDriverUpdate(token: "\(id)|\(target)|range") { [weak self] in
            Self.applyRateRange(target, engine: engine, instanceName: id, rangeX: x, rangeY: y)
            let frame = engine.currentFrame
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.recordAutomationPoint(id: id, target: target, quantity: "range", x: x, y: y, frame: frame)
                }
            }
        }
    }

    /// One or two `driverAutomationPoint` events (X and, for a vector
    /// driver, Y independently) — `axis` is `nil` for a scalar driver's
    /// single value, `"x"`/`"y"` when both sliders are in play.
    private func recordAutomationPoint(id: StagedSprite.ID, target: LiveDriverTarget, quantity: String, x: Double, y: Double?, frame: Int) {
        recordEvent(.driverAutomationPoint(t: frame, instanceName: id, target: target, quantity: quantity, axis: y != nil ? "x" : nil, value: x))
        if let y {
            recordEvent(.driverAutomationPoint(t: frame, instanceName: id, target: target, quantity: quantity, axis: "y", value: y))
        }
    }

    /// Updates the global BPM (all sessions default to 120/4-4 on
    /// `ensureEngine`) and recomputes every driver currently in musical mode.
    func setBPM(_ newValue: Double) {
        guard let engine else { return }
        let newBPM = max(1, newValue)
        bpm = newBPM
        RenderSurfaceNSView.sharedRenderQueue.async {
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recordEvent(.bpmSet(t: frame, bpm: newBPM, beatsPerBar: self.beatsPerBar))
                    self.recomputeAllMusicalDrivers()
                }
            }
        }
    }

    /// Updates the global time signature (beats/bar) and recomputes every
    /// driver currently in musical mode.
    func setBeatsPerBar(_ newValue: Int) {
        guard let engine else { return }
        let newBeats = max(1, newValue)
        beatsPerBar = newBeats
        RenderSurfaceNSView.sharedRenderQueue.async {
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recordEvent(.bpmSet(t: frame, bpm: self.bpm, beatsPerBar: newBeats))
                    self.recomputeAllMusicalDrivers()
                }
            }
        }
    }

    /// The user pressed the downbeat button in time with a bar's first
    /// beat — aligns every musically-linked driver's phase to this frame.
    /// Re-tappable at any time; there is no drift correction between taps.
    func tapDownbeat() {
        guard let engine else { return }
        RenderSurfaceNSView.sharedRenderQueue.async {
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.barReferenceFrame = frame
                    self.recordEvent(.tapSync(t: frame, referenceFrame: frame))
                    self.recomputeAllMusicalDrivers()
                }
            }
        }
    }

    /// Switches `target`'s Rate to (non-nil `multiplier`, cycles/bar) or away
    /// from (nil) BPM-linked musical mode. Range is never musically linked —
    /// only Rate.
    func setMusicalMultiplier(_ id: StagedSprite.ID, _ target: LiveDriverTarget, _ multiplier: Double?) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              var info = stagedSprites[idx].driverControls[target] else { return }
        info.musicalMultiplier = multiplier
        stagedSprites[idx].driverControls[target] = info
        RenderSurfaceNSView.sharedRenderQueue.async {
            let frame = engine.currentFrame
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.recordEvent(.driverMusicalRateAssign(t: frame, instanceName: id, target: target, multiplier: multiplier))
                }
            }
        }
        if let multiplier {
            applyMusicalRate(id: id, target: target, multiplier: multiplier)
        }
    }

    /// Recomputes and re-pushes every currently-musical-linked driver across
    /// all staged sprites — called whenever BPM, time signature, or the tap
    /// reference changes, since all of those affect every such driver at once.
    private func recomputeAllMusicalDrivers() {
        for staged in stagedSprites {
            for (target, info) in staged.driverControls {
                if let multiplier = info.musicalMultiplier {
                    applyMusicalRate(id: staged.id, target: target, multiplier: multiplier)
                }
            }
        }
    }

    /// Computes and pushes one driver's BPM-linked rate/phase.
    /// `engine.globalConfig` is immutable project config (set once at
    /// engine init, never touched by the render loop), so reading
    /// `targetFPS` directly here — unlike `currentFrame` — doesn't need a
    /// render-queue hop.
    private func applyMusicalRate(id: StagedSprite.ID, target: LiveDriverTarget, multiplier: Double) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              let currentInfo = stagedSprites[idx].driverControls[target] else { return }
        let (rate, phase) = Self.musicalRateAndPhase(
            mode: currentInfo.mode, multiplier: multiplier, bpm: bpm, beatsPerBar: beatsPerBar,
            barReferenceFrame: barReferenceFrame, targetFPS: engine.globalConfig.targetFPS
        )
        var info = currentInfo
        info.rateX = rate
        if info.isVector { info.rateY = rate }
        info.musicalMultiplier = multiplier
        stagedSprites[idx].driverControls[target] = info
        RenderSurfaceNSView.sharedRenderQueue.async {
            Self.applyRateRange(target, engine: engine, instanceName: id, rateX: rate, rateY: rate, phaseX: phase, phaseY: phase)
        }
    }

    private func scheduleDriverUpdate(token: String, _ work: @escaping @Sendable () -> Void) {
        pendingDriverTasks[token]?.cancel()
        pendingDriverTasks[token] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            RenderSurfaceNSView.sharedRenderQueue.async { work() }
            self?.pendingDriverTasks[token] = nil
        }
    }
}
