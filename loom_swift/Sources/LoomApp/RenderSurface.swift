import AppKit
import SwiftUI
import LoomEngine

// MARK: - RenderSurfaceView (SwiftUI wrapper)

/// A SwiftUI view that displays a running `Engine` animation.
///
/// Drives a 60 fps `Timer` whose behaviour is controlled by `playbackState`:
///   - `.playing`  — timer runs; engine advances each tick.
///   - `.paused`   — timer stopped; current frame frozen on screen.
///   - `.stopped`  — timer stopped; engine reset to frame 0; first frame rendered.
///
/// Pass `isPaused = true` (via `.paused` / `.stopped`) during video export so
/// the engine is driven exclusively by the exporter.
struct RenderSurfaceView: NSViewRepresentable {

    let engine:        Engine
    var playbackState: PlaybackState
    /// Called on every tick with the engine's current frame count.
    var onFrameTick:   (Int) -> Void = { _ in }

    func makeNSView(context: Context) -> RenderSurfaceNSView {
        let view = RenderSurfaceNSView(engine: engine, onFrameTick: onFrameTick)
        applyState(playbackState, to: view, isInitial: true)
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceNSView, context: Context) {
        nsView.onFrameTick = onFrameTick
        applyState(playbackState, to: nsView, isInitial: false)
    }

    private func applyState(_ state: PlaybackState,
                             to view: RenderSurfaceNSView,
                             isInitial: Bool) {
        switch state {
        case .playing:
            view.startRendering()
        case .paused:
            view.stopRendering()
        case .stopped:
            view.stopRendering()
            view.resetAndRenderFirstFrame()
        }
    }
}

// MARK: - RenderSurfaceNSView

final class RenderSurfaceNSView: NSView {

    // MARK: - Properties

    private let engine:    Engine
    private var lastTick:  CFTimeInterval = 0
    private var latestFrame: CGImage?

    /// Called each tick with the engine's current frame index.
    var onFrameTick: (Int) -> Void

    nonisolated(unsafe) private var renderTimer: Timer?

    // MARK: - Init

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

    // MARK: - Render loop

    func startRendering() {
        guard renderTimer == nil else { return }
        lastTick    = CACurrentMediaTime()
        renderTimer = Timer(timeInterval: 1.0 / 60,
                            target:       self,
                            selector:     #selector(tick),
                            userInfo:     nil,
                            repeats:      true)
        RunLoop.main.add(renderTimer!, forMode: .common)
    }

    func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    /// Reset the engine to frame 0 and display the initial frame.
    /// Called when playback state transitions to `.stopped`.
    func resetAndRenderFirstFrame() {
        try? engine.reset()
        renderFrame()
    }

    // MARK: - Frame tick

    @objc private func tick() {
        let now  = CACurrentMediaTime()
        let dt   = min(now - lastTick, 1.0 / 10)
        lastTick = now

        engine.update(deltaTime: dt)
        onFrameTick(engine.currentFrame)
        renderFrame()
    }

    /// Render the engine's current state and push it to the CALayer.
    private func renderFrame() {
        guard let frame = engine.makeFrame() else { return }
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

    // MARK: - Fallback software draw

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = latestFrame,
              let ctx   = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(frame, in: bounds)
    }

    // MARK: - Cleanup

    deinit {
        renderTimer?.invalidate()
        renderTimer = nil
    }
}
