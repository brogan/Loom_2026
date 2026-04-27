import CoreGraphics
import Foundation

// MARK: - Engine

/// High-level driver that couples a `LoomEngine` to a `FrameLoop`.
///
/// ### Typical usage — export / testing
/// ```swift
/// let engine = try Engine(projectDirectory: projectURL)
/// let loop   = ExportFrameLoop(fps: 30)
/// engine.start(with: loop)
/// loop.run(frameCount: 90)           // advance 3 seconds
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
/// `update(deltaTime:)` currently maps each call to one frame advance, making
/// `currentFrame` a reliable integer frame counter regardless of `deltaTime`.
/// The `deltaTime` parameter is reserved for future time-based animation
/// (e.g., slow-motion / speed-scaling) and is forwarded through the call chain
/// so it can be consumed there without an API change.
public final class Engine: @unchecked Sendable {

    // MARK: - Stored state

    /// The underlying scene engine.  Exposed read-only so callers can inspect
    /// per-frame state without driving rendering themselves.
    public private(set) var loomEngine: LoomEngine

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

    // MARK: - Per-frame

    /// Advance the engine one frame.
    ///
    /// `deltaTime` is the elapsed time since the previous call (in seconds).
    /// It is forwarded to `LoomEngine.advance(deltaTime:)` for time-based
    /// keyframe interpolation.
    public func update(deltaTime: Double) {
        loomEngine.advance(deltaTime: deltaTime)
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
    /// Returns `nil` when the canvas dimensions are zero or context creation fails.
    public func makeFrame() -> CGImage? {
        loomEngine.makeFrame()
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
}
