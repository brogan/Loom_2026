import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Engine

/// High-level driver that couples a `LoomEngine` to a `FrameLoop`.
///
/// ### Typical usage — export / testing
/// ```swift
/// let engine = try Engine(projectDirectory: projectURL)
/// let loop   = ExportFrameLoop(fps: engine.globalConfig.targetFPS)  // match the project's fps
/// engine.start(with: loop)
/// loop.run(frameCount: 90)           // advance 90 project frames
/// let image = engine.makeFrame()     // render the current state
/// engine.stop()
/// ```
///
/// ### Typical usage — live preview (macOS / iOS)
/// ```swift
/// let engine = try Engine(projectDirectory: projectURL)
/// let loop   = DisplayLinkFrameLoop()
/// engine.start(with: loop)
/// // In your draw callback:
/// engine.draw(into: context)
/// // On teardown:
/// engine.stop()
/// ```
///
/// ### Thread safety
/// Not thread-safe.  Drive from a single thread or actor (typically the main thread
/// when used with `DisplayLinkFrameLoop`).
///
/// ### Delta-time and frame counting
/// `deltaTime` is **real elapsed seconds**, not a frame count. `update(deltaTime:)`
/// forwards it to `LoomEngine.advance`, which converts it to project-frame units by
/// multiplying by the project's own `globalConfig.targetFPS`: each call advances
/// `currentFrame`'s underlying clock by `deltaTime * targetFPS`, and `currentFrame`
/// is that clock floored to an `Int`. This is genuine time-based accumulation, not a
/// per-call counter — passing `deltaTime = 1.0 / targetFPS` advances exactly one
/// project frame *for that project's own targetFPS*; a mismatched fps assumption
/// (e.g. a hardcoded `1.0/30` against a project authored at a different rate)
/// silently advances by a fractional, non-1 amount per call. Drive `ExportFrameLoop`
/// and any manual `update(deltaTime:)` calls with the project's actual
/// `globalConfig.targetFPS`, not an assumed constant, unless deliberately performing
/// frame-rate conversion.
public final class Engine: @unchecked Sendable {

    // MARK: - Stored state

    /// The underlying scene engine.  Exposed read-only so callers can inspect
    /// per-frame state without driving rendering themselves.
    public private(set) var loomEngine: LoomEngine

    /// All sprite instances in the scene (base geometry + def, no animation applied).
    public var spriteInstances: [SpriteInstance] { loomEngine.spriteInstances }

    /// The project directory this engine was loaded from, if any.
    /// Used by `reset()` to reinitialise the engine from scratch.
    public let projectDirectory: URL?

    private var activeLoop: (any FrameLoop)?

    // MARK: - Init

    /// Load a project from `projectDirectory` and prepare it for rendering.
    ///
    /// - Throws: `ProjectLoaderError` or `SpriteSceneError` on load failure.
    public init(projectDirectory: URL) throws {
        loomEngine           = try LoomEngine(projectDirectory: projectDirectory)
        self.projectDirectory = projectDirectory
    }

    /// Inject an already-constructed `LoomEngine` (useful in tests).
    public init(loomEngine: LoomEngine) {
        self.loomEngine      = loomEngine
        self.projectDirectory = nil
    }

    // MARK: - Reset

    /// Reinitialise the engine from its project directory, resetting animation
    /// back to frame 0.  Used by video export to start capture from the beginning.
    ///
    /// - Throws: `ProjectLoaderError` or `SpriteSceneError` if the project
    ///   cannot be re-read from disk.  Has no effect when this engine was created
    ///   from a `LoomEngine` value directly (no project URL stored).
    public func reset() throws {
        guard let url = projectDirectory else { return }
        loomEngine = try LoomEngine(projectDirectory: url)
    }

    // MARK: - FrameLoop control

    /// Wire up `loop` and begin delivering frame ticks.
    ///
    /// Each tick calls `update(deltaTime:)`.  Replaces any previously active loop.
    public func start(with loop: any FrameLoop) {
        activeLoop?.stop()
        activeLoop = loop
        loop.start { [weak self] deltaTime in
            self?.update(deltaTime: deltaTime)
        }
    }

    /// Stop the active frame loop and release it.
    public func stop() {
        activeLoop?.stop()
        activeLoop = nil
    }

    // MARK: - Seek

    /// Jump the engine to `frame` without playing through intermediate frames.
    /// Call `makeFrame()` afterwards to render the requested position.
    public func seek(toFrame frame: Int) {
        loomEngine.seek(toFrame: frame)
    }

    // MARK: - Per-frame

    /// Advance the engine's animation clock by `deltaTime` real seconds.
    ///
    /// See the class-level "Delta-time and frame counting" section: this is
    /// time-based, not a flat +1-frame-per-call counter. Forwarded to
    /// `LoomEngine.advance(deltaTime:)`.
    public func update(deltaTime: Double) {
        loomEngine.advance(deltaTime: deltaTime)
    }

    /// Advance one virtual-frame step and accumulate the result onto the persistent
    /// canvas without applying softness blur.  Use for sub-stepping large dt intervals.
    public func stepAndAccumulate(deltaTime: Double? = nil) {
        loomEngine.stepAndAccumulate(deltaTime: deltaTime)
    }

    /// Draw the current frame into `context`.
    ///
    /// The context must have no pre-existing transform; the Y-flip required by
    /// the rendering engine is applied internally.
    public func draw(into context: CGContext) {
        loomEngine.render(into: context)
    }

    /// Render the current frame to a new `CGImage`.
    ///
    /// - Parameter transparentBackground: skip filling `GlobalConfig
    ///   .backgroundColor`/`backgroundImage`, so pixels not covered by any drawn
    ///   geometry stay transparent instead — for exporting an image meant to be
    ///   composited over other content. Only takes effect outside accumulation
    ///   mode (`GlobalConfig.drawBackgroundOnce`); see `LoomEngine.makeFrame`.
    ///
    /// Returns `nil` when the canvas dimensions are zero or context creation fails.
    public func makeFrame(transparentBackground: Bool = false) -> CGImage? {
        loomEngine.makeFrame(transparentBackground: transparentBackground)
    }

    // MARK: - Forwarded accessors

    /// Number of times `update` has been called.
    public var currentFrame: Int    { loomEngine.currentFrame }

    /// Canvas size in pixels.
    public var canvasSize: CGSize   { loomEngine.canvasSize }

    /// The project's global configuration.
    public var globalConfig: GlobalConfig { loomEngine.globalConfig }

    /// Maximum `totalDraws` across all sprites; 0 when every sprite is unlimited.
    /// Use this to determine how many virtual frames a synchronous animated-still export needs.
    public var maxAnimationFrames: Int { loomEngine.maxAnimationFrames }

    /// Push a new lighting config into the live scene without a full project reload.
    /// Call this on every lighting inspector edit for immediate visual feedback.
    public func updateLightingConfig(_ lc: LightingConfig) {
        loomEngine.updateLightingConfig(lc)
    }
}

#if canImport(AppKit)
extension Engine {
    /// Insert or replace a single image in the sprite image cache without a full project reload.
    /// Called after a new image file is copied to `svgs/sprites/` so the live canvas
    /// reflects the change immediately.
    public func registerSpriteImage(_ image: NSImage, filename: String) {
        loomEngine.registerSpriteImage(image, filename: filename)
    }
}
#endif
