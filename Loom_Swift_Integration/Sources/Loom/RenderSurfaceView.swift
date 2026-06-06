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
        view.onAnimationComplete = onAnimationComplete
        view.onRenderProgress    = onRenderProgress
        applyState(playbackState, to: view, isInitial: true)
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceNSView, context: Context) {
        nsView.onFrameTick         = onFrameTick
        nsView.onAnimationComplete = onAnimationComplete
        nsView.onRenderProgress    = onRenderProgress
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
    // still be finishing an in-flight render.
    private static let sharedRenderQueue = DispatchQueue(label: "com.loom.render", qos: .userInteractive)
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

    func resetAndRenderFirstFrame() {
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

    // MARK: - Frame loop

    private func tick() {
        let now  = CACurrentMediaTime()
        let dt   = min(now - lastTick, 1.0 / 10)
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
            // Sub-step totalDt into virtual-frame-sized increments so that slow
            // high-resolution canvases accumulate the same sprite-layer density per
            // virtual second as fast low-resolution ones.  Each sub-step advances the
            // scene and paints one sprite pass with its own RNG state onto the canvas.
            let fps      = max(1.0, Double(self.engine.globalConfig.targetFPS))
            let frameDt  = 1.0 / fps
            let steps    = max(1, Int((totalDt / frameDt).rounded()))
            let stepDt   = totalDt / Double(steps)
            for _ in 0..<steps {
                self.engine.stepAndAccumulate(deltaTime: stepDt)
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
                if isDone { self.stopRendering(); self.onAnimationComplete?() }
                self.updateLayer(with: frame)
            }
        }
    }

    // Called from renderQueue; engine is exclusively owned there.
    nonisolated private func checkAnimationDone() -> Bool {
        let maxFrames = engine.maxAnimationFrames
        guard maxFrames > 0 else { return false }
        // Global duration takes priority: stop when frameCount reaches it.
        if engine.globalConfig.endFrame > 0 {
            return engine.currentFrame >= maxFrames
        }
        // Legacy: stop when all sprite draw cycles have completed.
        return engine.spriteInstances.allSatisfy { inst in
            let td = inst.def.animation.totalDraws
            return td == 0 || inst.state.drawCycle >= td
        }
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
