import AppKit
import SwiftUI
import LoomEngine

// MARK: - RenderSurfaceView (SwiftUI wrapper)

struct RenderSurfaceView: NSViewRepresentable, Equatable {

    let engine:               Engine
    var playbackState:        PlaybackState
    var seekFrame:            Int?            = nil
    var onFrameTick:          (Int) -> Void    = { _ in }
    var onAnimationComplete:  (() -> Void)?    = nil
    var onRenderProgress:     (Double?) -> Void = { _ in }
    /// Queried when the animation reaches its end, on the same NSView-owned
    /// context that's about to reset/resume it — lets a loop restart happen
    /// as one atomic, completion-driven sequence instead of round-tripping
    /// through `playbackState`'s reactive `.stopped`→`.playing` dance (which
    /// SwiftUI can coalesce away entirely, silently skipping the engine
    /// reset in between — see `RenderSurfaceNSView.tick()`).
    var shouldLoopOnComplete: (() -> Bool)?    = nil
    /// True for a rehearsal surface (the Live tab) that has no natural end of
    /// its own — its engine's frame clock just keeps advancing for as long as
    /// the tab is open, unrelated to whatever finite length the *project's*
    /// own keyframes/`endFrame` happen to define. Without this, `tick()`'s
    /// isDone check (`engine.currentFrame >= engine.maxAnimationFrames`) is
    /// keyed off that same project-derived length, so a Live session left
    /// running long enough would eventually "complete" and permanently stop
    /// ticking — worse, `shouldLoopOnComplete` isn't a fix here, since its
    /// mechanism restarts by fully reloading the engine from disk, which
    /// would silently discard every sprite/pose staged live in memory.
    var ignoresAnimationEnd: Bool               = false

    // SwiftUI uses == to decide whether to call updateNSView.
    // Closures aren't Equatable; we only diff on the properties that actually drive
    // engine/state changes. Closure changes are always applied in updateNSView anyway.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.engine === rhs.engine
            && lhs.playbackState == rhs.playbackState
            && lhs.seekFrame     == rhs.seekFrame
    }

    func makeNSView(context: Context) -> RenderSurfaceNSView {
        let view = RenderSurfaceNSView(engine: engine, onFrameTick: onFrameTick)
        view.onAnimationComplete  = onAnimationComplete
        view.onRenderProgress     = onRenderProgress
        view.shouldLoopOnComplete = shouldLoopOnComplete
        view.ignoresAnimationEnd  = ignoresAnimationEnd
        applyState(playbackState, to: view, isInitial: true)
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceNSView, context: Context) {
        nsView.onFrameTick         = onFrameTick
        nsView.onAnimationComplete = onAnimationComplete
        nsView.onRenderProgress    = onRenderProgress
        nsView.shouldLoopOnComplete = shouldLoopOnComplete
        nsView.ignoresAnimationEnd  = ignoresAnimationEnd
        if nsView.engine !== engine {
            nsView.replaceEngine(engine)
            applyState(playbackState, to: nsView, isInitial: false)
        } else {
            if playbackState != nsView.appliedPlaybackState {
                applyState(playbackState, to: nsView, isInitial: false)
            }
            if let frame = seekFrame, frame != nsView.lastSeekFrame {
                nsView.lastSeekFrame = frame
                nsView.seekToFrame(frame)
            }
        }
    }

    private func applyState(_ state: PlaybackState, to view: RenderSurfaceNSView, isInitial: Bool) {
        view.appliedPlaybackState = state
        switch state {
        case .playing: view.startRendering()
        case .paused:  view.stopRendering()
        case .stopped: view.stopRendering(); view.resetAndRenderFirstFrame()
        }
    }
}

// MARK: - RenderSurfaceNSView

final class RenderSurfaceNSView: NSView {

    // Owned exclusively by renderQueue after init; nonisolated(unsafe) because
    // NSView is @MainActor but engine must be accessed off-main for rendering.
    nonisolated(unsafe) fileprivate var engine: Engine

    // Shared serial queue: all preview surfaces serialize engine mutation and
    // CGImage production, including during tab switches while an old surface may
    // still be finishing an in-flight render. Internal (not private) so one-shot
    // engine access from elsewhere (e.g. `AppController.saveStill`/`saveSVG`) can
    // synchronize with it too — `Engine`/`LoomEngine` are explicitly not
    // thread-safe, so any direct `engine.makeFrame()` off this queue races
    // whatever in-flight render this queue is running.
    static let sharedRenderQueue = DispatchQueue(label: "com.loom.render", qos: .userInteractive)
    private var renderQueue: DispatchQueue { Self.sharedRenderQueue }

    // Main-thread only below this line ↓
    private var latestFrame:      CGImage?
    private var lastTick:         CFTimeInterval = 0
    private var renderPending:    Bool           = false
    private var seekPending:      Bool           = false
    private var queuedSeekFrame:  Int?           = nil
    private var accumulatedDt:    CFTimeInterval = 0
    // Incremented whenever the engine or project is replaced; lets in-flight
    // renders on renderQueue detect that their result is stale.
    private var renderGeneration: Int            = 0
    private var renderProgressToken: Int         = 0
    private var renderProgressVisible: Bool      = false
    private var pendingRenderProgress: Double?   = nil

    private let slowRenderProgressDelay: TimeInterval = 0.5

    var onFrameTick:          (Int) -> Void
    var onAnimationComplete:  (() -> Void)?
    var onRenderProgress:     (Double?) -> Void = { _ in }
    var shouldLoopOnComplete: (() -> Bool)?
    // Read from `checkAnimationDone()` on renderQueue — same unsynchronized-
    // but-safe-in-practice pattern as `engine` above (set on main, read off
    // it; a torn read of a single Bool is not a real-world hazard here).
    nonisolated(unsafe) var ignoresAnimationEnd: Bool = false
    var appliedPlaybackState: PlaybackState = .stopped
    var lastSeekFrame:        Int?          = nil

    nonisolated(unsafe) private var renderTimer: Timer?

    init(engine: Engine, onFrameTick: @escaping (Int) -> Void) {
        self.engine      = engine
        self.onFrameTick = onFrameTick
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func makeBackingLayer() -> CALayer {
        let l = CALayer()
        l.contentsGravity = .resizeAspect
        l.backgroundColor = CGColor(gray: 0, alpha: 1)
        return l
    }

    // MARK: - Timer lifecycle

    func startRendering() {
        guard renderTimer == nil else { return }
        lastTick    = CACurrentMediaTime()
        // Closure-based timer: no strong reference to self → no retain cycle.
        renderTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Timer fires on RunLoop.main, so main-actor isolation holds.
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(renderTimer!, forMode: .common)
    }

    func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    // Stop the timer automatically when the view leaves the window (tab switch).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRendering() }
    }

    // MARK: - Seek

    /// Seek to `frame` and render a single frame to display.
    /// The render timer must be stopped before calling (scrub pauses playback).
    func seekToFrame(_ frame: Int) {
        queuedSeekFrame = frame
        guard !seekPending else { return }
        renderNextQueuedSeek()
    }

    private func renderNextQueuedSeek() {
        guard let frame = queuedSeekFrame else {
            seekPending = false
            onRenderProgress(nil)
            return
        }
        queuedSeekFrame = nil
        seekPending = true
        renderGeneration += 1
        let gen = renderGeneration
        let progressToken = beginRenderProgress(initial: 0.10)
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.engine.seek(toFrame: frame)
            DispatchQueue.main.async { [weak self] in self?.updateRenderProgress(0.35, token: progressToken) }
            guard let img = self.engine.makeFrame() else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.seekPending = false
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                    self.renderNextQueuedSeek()
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.renderGeneration == gen else {
                    self.seekPending = false
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                    self.renderNextQueuedSeek()
                    return
                }
                if self.queuedSeekFrame == nil {
                    self.finishRenderProgress(token: progressToken)
                    self.onFrameTick(frame)
                    self.updateLayer(with: img)
                } else {
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                }
                self.seekPending = false
                self.renderNextQueuedSeek()
            }
        }
    }

    // MARK: - Engine replacement

    func replaceEngine(_ newEngine: Engine) {
        stopRendering()
        seekPending = false
        queuedSeekFrame = nil
        renderGeneration += 1
        let gen = renderGeneration
        clearDisplay()
        let progressToken = beginRenderProgress(initial: 0.20)
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.engine = newEngine
            guard let frame = self.engine.makeFrame() else {
                DispatchQueue.main.async { [weak self] in
                    self?.finishRenderProgress(token: progressToken, showCompletion: false)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.renderGeneration == gen else {
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                    return
                }
                self.finishRenderProgress(token: progressToken)
                self.updateLayer(with: frame)
            }
        }
    }

    /// `completion` fires on the main thread once the reset has actually
    /// taken effect (engine reloaded, first post-reset frame either drawn or
    /// abandoned as stale) — the deterministic alternative to inferring
    /// "reset happened" from a `playbackState` value that SwiftUI may never
    /// actually render (see `tick()`'s isDone handling, where this matters:
    /// a loop restart must not resume ticking before the reset lands, or the
    /// engine's un-reset, still-past-the-end clock makes `checkAnimationDone()`
    /// true again immediately, permanently wedging playback and — since audio
    /// sync and any Clamp-mode driver both depend on the frame clock actually
    /// going back below the animation's length — silently freezing them too).
    func resetAndRenderFirstFrame(completion: (@Sendable () -> Void)? = nil) {
        stopRendering()
        seekPending = false
        queuedSeekFrame = nil
        renderGeneration += 1
        let gen = renderGeneration
        // Do NOT clearDisplay() here: keep showing the last frame while the engine
        // resets so there is no black flash on loop restart or manual stop.
        // clearDisplay() is only called if the engine cannot produce a frame at all.
        let progressToken = beginRenderProgress(initial: 0.20)
        renderQueue.async { [weak self] in
            guard let self else { return }
            try? self.engine.reset()
            guard let frame = self.engine.makeFrame() else {
                DispatchQueue.main.async { [weak self] in
                    self?.clearDisplay()   // nothing to show — clear to avoid stale image
                    self?.finishRenderProgress(token: progressToken, showCompletion: false)
                    completion?()
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.renderGeneration == gen else {
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                    return
                }
                self.finishRenderProgress(token: progressToken)
                self.updateLayer(with: frame)
                completion?()
            }
        }
    }

    // MARK: - Frame loop

    private func tick() {
        let now  = CACurrentMediaTime()
        // The main timeline clamps hard (100ms) to avoid a big visual jump
        // after being backgrounded — fine there, since nothing is being
        // timestamped against this clock. Live's clock is different: every
        // recorded event's `t` (and, via `sessionEnd`, a session's whole
        // duration) is read directly off `engine.currentFrame`, so any real
        // time this clamp silently drops makes the session's frame count
        // under-count true elapsed wall time — exactly what made rendered
        // takes play faster than the live session actually did. Brief
        // main-thread stalls (a picker, a burst of staged-sprite events)
        // are routine mid-session, so Live gets a much more generous clamp:
        // still a backstop against a truly pathological gap (e.g. the
        // machine sleeping), but well above anything a normal UI stall
        // should hit.
        let maxDt = ignoresAnimationEnd ? 2.0 : (1.0 / 10)
        let dt   = min(now - lastTick, maxDt)
        lastTick = now

        // If the previous frame is still rendering, accumulate time and skip.
        if renderPending { accumulatedDt += dt; return }

        renderPending = true
        let totalDt = dt + accumulatedDt
        accumulatedDt = 0
        let gen = renderGeneration
        let progressToken = beginRenderProgress(initial: 0.10)

        renderQueue.async { [weak self] in
            guard let self else { return }
            // Accumulation mode: sub-step into qualityMultiple passes so a high-res
            // canvas (quality > 1, slower render) gets the same sprite-layer density
            // per virtual frame as a 1× canvas.  Step count is fixed at qualityMultiple
            // to avoid a feedback loop (time-based counts spiral as renders slow down).
            let gc      = self.engine.globalConfig
            let quality = max(1, gc.qualityMultiple)
            if gc.drawBackgroundOnce && quality > 1 {
                let stepDt = totalDt / Double(quality)
                for _ in 0..<quality {
                    self.engine.stepAndAccumulate(deltaTime: stepDt)
                }
            } else {
                self.engine.update(deltaTime: totalDt)
            }
            DispatchQueue.main.async { [weak self] in self?.updateRenderProgress(0.30, token: progressToken) }
            let frameNum = self.engine.currentFrame
            let isDone   = self.checkAnimationDone()
            guard let frame = self.engine.makeFrame() else {
                DispatchQueue.main.async { [weak self] in
                    self?.renderPending = false
                    self?.finishRenderProgress(token: progressToken, showCompletion: false)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Discard stale renders produced before a replaceEngine/reset.
                guard self.renderGeneration == gen else {
                    self.renderPending = false
                    self.finishRenderProgress(token: progressToken, showCompletion: false)
                    return
                }
                self.renderPending = false
                self.finishRenderProgress(token: progressToken)
                self.onFrameTick(frameNum)
                if isDone {
                    self.stopRendering()
                    if self.shouldLoopOnComplete?() == true {
                        // Reset-then-resume as one completion-driven sequence — see
                        // resetAndRenderFirstFrame's doc comment for why this can't
                        // go through playbackState's reactive .stopped→.playing path.
                        self.resetAndRenderFirstFrame { [weak self] in
                            MainActor.assumeIsolated { self?.startRendering() }
                        }
                    } else {
                        self.onAnimationComplete?()
                    }
                }
                self.updateLayer(with: frame)
            }
        }
    }

    // Called from renderQueue; engine is exclusively owned there.
    nonisolated private func checkAnimationDone() -> Bool {
        guard !ignoresAnimationEnd else { return false }
        let maxFrames = engine.maxAnimationFrames
        guard maxFrames > 0 else { return false }
        return engine.currentFrame >= maxFrames
    }

    // MARK: - Display helpers (main thread)

    private func clearDisplay() {
        latestFrame = nil
        if let l = layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            l.contents = nil
            CATransaction.commit()
        }
    }

    private func beginRenderProgress(initial: Double) -> Int {
        renderProgressToken += 1
        let token = renderProgressToken
        pendingRenderProgress = initial
        renderProgressVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + slowRenderProgressDelay) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.renderProgressToken == token,
                      let progress = self.pendingRenderProgress
                else { return }
                self.renderProgressVisible = true
                self.onRenderProgress(progress)
            }
        }
        return token
    }

    private func updateRenderProgress(_ progress: Double, token: Int) {
        guard renderProgressToken == token else { return }
        pendingRenderProgress = progress
        if renderProgressVisible {
            onRenderProgress(progress)
        }
    }

    private func finishRenderProgress(token: Int, showCompletion: Bool = true) {
        guard renderProgressToken == token else { return }
        renderProgressToken += 1
        pendingRenderProgress = nil
        if renderProgressVisible {
            if showCompletion {
                onRenderProgress(1.0)
            }
            onRenderProgress(nil)
        }
        renderProgressVisible = false
    }

    private func updateLayer(with frame: CGImage) {
        latestFrame = frame
        if let l = layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            l.contents = frame
            CATransaction.commit()
        } else {
            setNeedsDisplay(bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = latestFrame,
              let ctx   = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(frame, in: bounds)
    }

    deinit {
        renderTimer?.invalidate()
    }
}
