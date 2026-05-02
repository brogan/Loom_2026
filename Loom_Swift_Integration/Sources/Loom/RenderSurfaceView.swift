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
        nsView.onFrameTick          = onFrameTick
        nsView.onAnimationComplete  = onAnimationComplete
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

    fileprivate var engine: Engine
    private var lastTick:   CFTimeInterval = 0
    private var latestFrame: CGImage?

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
        l.contentsGravity  = .resizeAspect
        l.backgroundColor  = CGColor(gray: 0, alpha: 1)
        return l
    }

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

    func replaceEngine(_ newEngine: Engine) {
        stopRendering()
        engine = newEngine
        clearDisplay()
        renderFrame()
    }

    func resetAndRenderFirstFrame() {
        try? engine.reset()
        clearDisplay()
        renderFrame()
    }

    private func clearDisplay() {
        latestFrame = nil
        if let l = layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            l.contents = nil
            CATransaction.commit()
        }
    }

    @objc private func tick() {
        let now  = CACurrentMediaTime()
        let dt   = min(now - lastTick, 1.0 / 10)
        lastTick = now
        engine.update(deltaTime: dt)
        onFrameTick(engine.currentFrame)
        renderFrame()
        checkAnimationComplete()
    }

    private func checkAnimationComplete() {
        let maxFrames = engine.maxAnimationFrames
        guard maxFrames > 0 else { return }
        let allDone = engine.spriteInstances.allSatisfy { inst in
            let td = inst.def.animation.totalDraws
            return td == 0 || inst.state.drawCycle >= td
        }
        guard allDone else { return }
        stopRendering()
        onAnimationComplete?()
    }

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

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = latestFrame,
              let ctx   = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(frame, in: bounds)
    }

    deinit {
        renderTimer?.invalidate()
        renderTimer = nil
    }
}
