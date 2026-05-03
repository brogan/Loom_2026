import AppKit
import SwiftUI
import LoomEngine

// MARK: - RenderSurfaceView (SwiftUI wrapper)

struct RenderSurfaceView: NSViewRepresentable {

    let engine:               Engine
    var playbackState:        PlaybackState
    var onFrameTick:          (Int) -> Void    = { _ in }
    var onAnimationComplete:  (() -> Void)?    = nil

    func makeNSView(context: Context) -> RenderSurfaceNSView {
        let view = RenderSurfaceNSView(engine: engine, onFrameTick: onFrameTick)
        view.onAnimationComplete = onAnimationComplete
        applyState(playbackState, to: view, isInitial: true)
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceNSView, context: Context) {
        nsView.onFrameTick         = onFrameTick
        nsView.onAnimationComplete = onAnimationComplete
        if nsView.engine !== engine { nsView.replaceEngine(engine) }
        applyState(playbackState, to: nsView, isInitial: false)
    }

    private func applyState(_ state: PlaybackState, to view: RenderSurfaceNSView, isInitial: Bool) {
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

    // Serial queue: all engine mutation and CGImage production happen here.
    private let renderQueue = DispatchQueue(label: "com.loom.render", qos: .userInteractive)

    // Main-thread only below this line ↓
    private var latestFrame:      CGImage?
    private var lastTick:         CFTimeInterval = 0
    private var renderPending:    Bool           = false
    private var accumulatedDt:    CFTimeInterval = 0
    // Incremented whenever the engine or project is replaced; lets in-flight
    // renders on renderQueue detect that their result is stale.
    private var renderGeneration: Int            = 0

    var onFrameTick:         (Int) -> Void
    var onAnimationComplete: (() -> Void)?

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

    // MARK: - Engine replacement

    func replaceEngine(_ newEngine: Engine) {
        stopRendering()
        renderGeneration += 1
        let gen = renderGeneration
        clearDisplay()
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.engine = newEngine
            guard let frame = self.engine.makeFrame() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.renderGeneration == gen else { return }
                self.updateLayer(with: frame)
            }
        }
    }

    func resetAndRenderFirstFrame() {
        stopRendering()
        renderGeneration += 1
        let gen = renderGeneration
        clearDisplay()
        renderQueue.async { [weak self] in
            guard let self else { return }
            try? self.engine.reset()
            guard let frame = self.engine.makeFrame() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.renderGeneration == gen else { return }
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

        renderQueue.async { [weak self] in
            guard let self else { return }
            self.engine.update(deltaTime: totalDt)
            let frameNum = self.engine.currentFrame
            let isDone   = self.checkAnimationDone()
            guard let frame = self.engine.makeFrame() else {
                DispatchQueue.main.async { [weak self] in self?.renderPending = false }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Discard stale renders produced before a replaceEngine/reset.
                guard self.renderGeneration == gen else {
                    self.renderPending = false
                    return
                }
                self.renderPending = false
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
