import Foundation

// MARK: - FrameLoop protocol

/// A source of frame-tick events that drives `Engine.update`.
///
/// Conforming types differ in timing strategy:
/// - `DisplayLinkFrameLoop` — wall-clock driven via `CADisplayLink` (live preview)
/// - `ExportFrameLoop`      — synchronous, fixed-rate (batch export / testing)
///
/// ### Thread safety
/// Must be created, started, and stopped from a single thread.
/// `DisplayLinkFrameLoop` must use the main thread.
public protocol FrameLoop: AnyObject {

    /// Begin delivering tick events.  Repeated calls replace the existing callback.
    func start(onTick: @escaping (_ deltaTime: Double) -> Void)

    /// Stop delivering tick events and release the callback.
    func stop()
}

// MARK: - ExportFrameLoop

/// A synchronous frame loop that delivers a fixed `deltaTime` per tick.
///
/// Useful for batch export and unit testing: call `run(frameCount:)` to drive
/// the engine for an exact number of frames without a display link or timer.
///
/// ```swift
/// let loop = ExportFrameLoop(fps: 30)
/// engine.start(with: loop)
/// loop.run(frameCount: 90)   // advance 3 seconds at 30 fps
/// engine.stop()
/// ```
public final class ExportFrameLoop: FrameLoop, @unchecked Sendable {

    /// Frames per second used to compute `deltaTime = 1.0 / fps`.
    public let fps: Double

    private var callback: ((_ deltaTime: Double) -> Void)?

    public init(fps: Double = 30) {
        self.fps = fps
    }

    /// Register the tick callback.  Must be called before `run(frameCount:)`.
    public func start(onTick: @escaping (_ deltaTime: Double) -> Void) {
        callback = onTick
    }

    /// Release the tick callback.
    public func stop() {
        callback = nil
    }

    /// Drive the loop synchronously for `frameCount` frames.
    ///
    /// Each tick receives `deltaTime = 1.0 / fps`.
    /// `start(onTick:)` must have been called first; a no-op otherwise.
    public func run(frameCount: Int) {
        guard let cb = callback, frameCount > 0 else { return }
        let dt = 1.0 / fps
        for _ in 0..<frameCount { cb(dt) }
    }
}

// MARK: - DisplayLinkFrameLoop

// CADisplayLink(target:selector:) is available on iOS/tvOS.
// macOS live preview will be wired up in the Phase 9 app shell
// using the platform's native display-link entry point.
#if os(iOS) || os(tvOS)
import QuartzCore

/// A display-link–driven frame loop for live preview on iOS/tvOS.
///
/// Wraps `CADisplayLink` and delivers wall-clock delta times to the engine.
/// The first tick after `start` is skipped (used to seed the timestamp) so
/// animation always begins from a clean `deltaTime`.
///
/// ### Thread safety
/// Must be created, started, and stopped from the **main thread**.
public final class DisplayLinkFrameLoop: NSObject, FrameLoop, @unchecked Sendable {

    private var displayLink:   CADisplayLink?
    private var callback:      ((_ deltaTime: Double) -> Void)?
    private var lastTimestamp: CFTimeInterval = 0

    override public init() { super.init() }

    /// Attach a `CADisplayLink` to `RunLoop.main` and begin ticking.
    public func start(onTick: @escaping (_ deltaTime: Double) -> Void) {
        stop()
        callback      = onTick
        lastTimestamp = 0
        let link      = CADisplayLink(target: self,
                                      selector: #selector(handleTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink   = link
    }

    /// Invalidate the display link and release the callback.
    public func stop() {
        displayLink?.invalidate()
        displayLink   = nil
        callback      = nil
        lastTimestamp = 0
    }

    @objc private func handleTick(_ link: CADisplayLink) {
        let now = link.timestamp
        guard lastTimestamp > 0 else { lastTimestamp = now; return }
        let dt        = now - lastTimestamp
        lastTimestamp = now
        callback?(dt)
    }
}
#endif
