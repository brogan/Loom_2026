import CoreGraphics
import CoreImage
import Foundation
import ImageIO
#if canImport(AppKit)
import AppKit
#endif

// MARK: - LoomEngine

/// Top-level facade for the Loom animation engine.
///
/// ### Typical usage
/// ```swift
/// var engine = try LoomEngine(projectDirectory: projectURL)
/// // For each frame:
/// engine.advance()
/// if let image = engine.makeFrame() { display(image) }
/// ```
///
/// ### Coordinate system
/// World space: origin at canvas centre, Y-up.
/// `makeFrame()` / `render(into:)` handle the Y-flip internally; callers
/// provide a clean `CGContext` with no pre-existing transform.
///
/// ### Accumulation mode
/// When `GlobalConfig.drawBackgroundOnce` is `true` the engine keeps a
/// persistent canvas.  The background is painted once on the first
/// `makeFrame()` call; subsequent calls draw sprites on top of the
/// accumulated canvas, and the overlay color fades old content — producing
/// Loom's characteristic "motion trail" effect.
///
/// ### Thread safety
/// Not thread-safe.  Drive from a single thread or actor.
public struct LoomEngine: @unchecked Sendable {

    // MARK: - Stored state

    private var scene:          SpriteScene
    private let config:         ProjectConfig

    // Shared CIContext — expensive to create, safe to reuse across frames.
    // nonisolated(unsafe): CIContext is internally thread-safe for createCGImage.
    private nonisolated(unsafe) static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let viewTransform:  ViewTransform
    private let backgroundImage: CGImage?   // nil when backgroundImagePath is empty or unreadable
    private let brushImages:    [String: CGImage]  // keyed by filename, from <project>/brushes/
    private let stampImages:    [String: CGImage]  // keyed by filename, from <project>/stamps/
    private var rng:            SystemRandomNumberGenerator
    private var frameCount:     Int
    /// Accumulated fractional frame count (= sum of deltaTime × targetFPS across all advances).
    /// Used as the meander-phase clock so brush animation is frame-rate independent.
    private var elapsedFrames:  Double

    /// Set to `true` by `advance` when at least one sprite crossed a virtual-frame boundary.
    ///
    /// `makeAccumulatedFrame` gates sprite rendering on this flag so that the 60 fps
    /// display timer doesn't accumulate more sprite layers per second than the virtual
    /// frame rate (typically 30 fps).  This ensures animated-still output is identical
    /// for fast (small) and slow (large) canvases.
    private var sceneAdvancedThisFrame: Bool = true

    /// Persistent canvas for accumulation-mode rendering (`drawBackgroundOnce = true`).
    ///
    /// In accumulation mode each `makeFrame()` call renders onto the same canvas,
    /// so the overlay color progressively fades old content (Loom's trail effect).
    private var accumulationCanvas: AccumulationCanvas?
    private var brushProgressiveStates: [String: BrushProgressiveState] = [:]

    // MARK: - Init

    /// Load a complete project from `projectDirectory` and prepare it for rendering.
    ///
    /// - Throws: `ProjectLoaderError` if config files are missing,
    ///           `SpriteSceneError` if polygon files are not found.
    public init(projectDirectory: URL) throws {
        let cfg = try ProjectLoader.load(projectDirectory: projectDirectory)
        let scn = try SpriteScene(config: cfg, projectDirectory: projectDirectory)

        let gc = cfg.globalConfig
        let canvasW = Double(gc.width  * gc.qualityMultiple)
        let canvasH = Double(gc.height * gc.qualityMultiple)

        let quality         = max(1, gc.qualityMultiple)
        let rawBrushImages  = LoomEngine.loadBrushImages(projectDirectory: projectDirectory)
        let scaledBrushImages = quality > 1
            ? LoomEngine.scaleImages(rawBrushImages, by: quality) : rawBrushImages

        self.config             = cfg
        self.scene              = scn
        self.viewTransform      = ViewTransform(canvasSize: CGSize(width: canvasW, height: canvasH))
        self.backgroundImage    = LoomEngine.loadImage(path: gc.backgroundImagePath)
        self.brushImages        = LoomEngine.preblurBrushImages(scaledBrushImages, config: cfg.renderingConfig, qualityMultiple: quality)
        self.stampImages        = LoomEngine.loadPNGImages(directory: projectDirectory.appendingPathComponent("stamps"))
        self.rng                = SystemRandomNumberGenerator()
        self.frameCount         = 0
        self.elapsedFrames      = 0.0
        self.accumulationCanvas = nil
        self.brushProgressiveStates = [:]
#if canImport(AppKit)
        self.scene.svgImages = LoomEngine.loadSVGImages(projectDirectory: projectDirectory)
#endif
    }

    // MARK: - Public accessors

    /// The project's global configuration.
    public var globalConfig: GlobalConfig { config.globalConfig }

    /// Canvas size in pixels (width × qualityMultiple, height × qualityMultiple).
    public var canvasSize: CGSize { viewTransform.canvasSize }

    /// All sprite instances in the scene (base geometry + def, no animation applied).
    public var spriteInstances: [SpriteInstance] { scene.instances }

#if canImport(AppKit)
    /// Insert or replace a single image in the sprite image cache without a full project reload.
    /// Called after the user picks a new image file via the cycle editor so the live canvas
    /// reflects the change immediately.
    public mutating func registerSpriteImage(_ image: NSImage, filename: String) {
        scene.svgImages[filename] = image
    }
#endif

    /// Current project frame on the same clock used for driver keyframe evaluation.
    public var currentFrame: Int {
        max(0, Int(elapsedFrames.rounded(.down)))
    }

    /// The effective animation length in frames, or 0 if unbounded.
    ///
    /// Returns `globalConfig.duration` when set (> 0). Falls back to the latest
    /// finite sprite or camera keyframe end frame, which is 0 when everything is
    /// unlimited/static.
    public var maxAnimationFrames: Int {
        let d = globalConfig.endFrame
        if d > 0 { return d }
        let spriteEnd = scene.instances.reduce(0) { max($0, $1.def.animation.totalDraws) }
        return max(spriteEnd, globalConfig.camera.animationEndFrame)
    }

    // MARK: - Advance

    /// Step all sprite animations one frame forward and increment `currentFrame`.
    ///
    /// - Parameter deltaTime: Wall-clock seconds since the previous call.
    ///   Defaults to `1.0 / targetFPS` so callers that don't have a real clock
    ///   (export, testing) get the correct fixed-rate behaviour without change.
    public mutating func advance(deltaTime: Double? = nil) {
        let fps = config.globalConfig.targetFPS
        let dt  = deltaTime ?? (1.0 / max(1.0, fps))
        let nextElapsedFrames = elapsedFrames + dt * max(1.0, fps)
        // Global animating flag is the master switch: when false, all sprite animation
        // is suppressed and the scene is held at its initial (frame-0) state.
        if config.globalConfig.animating {
            sceneAdvancedThisFrame = scene.advance(
                deltaTime:     dt,
                targetFPS:     fps,
                globalElapsed: nextElapsedFrames,
                using:         &rng
            )
        } else {
            sceneAdvancedThisFrame = false
        }
        elapsedFrames = nextElapsedFrames
        frameCount    += 1
    }

    // MARK: - Seek

    /// Jump to an arbitrary frame without playing through the intermediate frames.
    ///
    /// After calling `seek`, call `makeFrame()` to render the requested position.
    /// Works correctly for driver-based animations (stateless evaluation).
    /// For legacy jitter/keyframe animations the sprite draw-cycle is set directly,
    /// so the result is visually approximate (renderer-cycling state is not replayed).
    public mutating func seek(toFrame frame: Int) {
        let fps            = max(1.0, config.globalConfig.targetFPS)
        let globalElapsed  = Double(frame)
        frameCount             = frame
        elapsedFrames          = globalElapsed
        accumulationCanvas     = nil        // force fresh render at seek position
        brushProgressiveStates = [:]
        sceneAdvancedThisFrame = true
        var rng = SystemRandomNumberGenerator()
        for i in scene.instances.indices {
            let inst = scene.instances[i]
            // Per-sprite elapsed mirrors the global clock for a simple seek.
            // (elapsedTime * fps == perSpriteElapsed, matching advanceInstance's formula.)
            let perSpriteElapsed = globalElapsed
            scene.instances[i].state.drawCycle            = frame
            scene.instances[i].state.elapsedTime          = globalElapsed / fps
            scene.instances[i].state.frameTimeAccumulator = 0
            scene.instances[i].state.transform = TransformAnimator.transform(
                for:           inst.def.animation,
                elapsedFrames: perSpriteElapsed,
                globalElapsed: globalElapsed,
                targetFPS:     fps,
                spriteIndex:   i,
                using:         &rng
            )
        }
    }

    // MARK: - Render

    /// Draw the current frame into `context`.
    ///
    /// The context must have no pre-existing transform; `render` applies the
    /// Y-flip required by `RenderEngine` internally.
    ///
    /// Drawing order:
    /// 1. Background (color or image) — skipped on frames 1+ when `drawBackgroundOnce` is true.
    /// 2. All sprite polygons via `SpriteScene.render`.
    /// 3. Overlay color (every frame, if `overlayColor.a > 0`).
    ///
    /// When calling `render(into:)` directly (rather than via `makeFrame()`),
    /// the background is drawn whenever `drawBackgroundOnce` is false, or on
    /// the first advance cycle (`frameCount == 1`).
    public mutating func render(into context: CGContext) {
        let drawBg = !config.globalConfig.drawBackgroundOnce || frameCount <= 1
        renderImpl(into: context, drawBackground: drawBg)
    }

    // MARK: - Frame convenience

    /// Render the current frame to a new `CGImage`.
    ///
    /// - When `drawBackgroundOnce` is **true** (accumulation mode): a persistent
    ///   canvas is created on the first call (background pre-filled), then reused
    ///   on every subsequent call so the overlay color can fade old content.
    ///   The returned image reflects the accumulated state.
    ///
    /// - When `drawBackgroundOnce` is **false** (independent-frame mode): a fresh
    ///   canvas is allocated, the background and sprites are drawn from scratch,
    ///   and the canvas is discarded after each call.  Suitable for still-image
    ///   rendering or frame-by-frame video export without trail effects.
    ///
    /// Returns `nil` when the canvas dimensions are zero or context creation fails.
    public mutating func makeFrame() -> CGImage? {
        let w = Int(viewTransform.canvasSize.width)
        let h = Int(viewTransform.canvasSize.height)
        guard w > 0, h > 0 else { return nil }

        let raw: CGImage?
        if config.globalConfig.drawBackgroundOnce {
            raw = makeAccumulatedFrame(width: w, height: h)
        } else {
            raw = makeFreshFrame(width: w, height: h)
        }
        guard let raw else { return nil }
        guard config.globalConfig.renderSoftness > 0 else { return raw }
        return applyRenderSoftness(to: raw) ?? raw
    }

    /// Applies a Gaussian blur of radius `renderSoftness × qualityMultiple` pixels.
    /// Returns nil if the blur cannot be applied (falls back to the original frame).
    private func applyRenderSoftness(to image: CGImage) -> CGImage? {
        let radius = config.globalConfig.renderSoftness
                   * Double(max(1, config.globalConfig.qualityMultiple))
        let input  = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur",
                                    parameters: [kCIInputImageKey:  input,
                                                 kCIInputRadiusKey: radius]),
              let output = filter.outputImage
        else { return nil }
        // CIGaussianBlur expands the extent; crop back to the original canvas bounds.
        let cropped = output.cropped(to: input.extent)
        return Self.ciContext.createCGImage(cropped, from: input.extent)
    }

    // MARK: - Private render implementation

    private mutating func renderImpl(into context: CGContext, drawBackground: Bool) {
        let w = viewTransform.canvasSize.width
        let h = viewTransform.canvasSize.height
        // Apply animated camera to a fresh ViewTransform each frame.
        let activeTransform = cameraTransform()

        // Apply Y-flip: worldToScreen is top-left Y-down; CGContext is bottom-left Y-up.
        context.saveGState()
        context.translateBy(x: 0, y: h)
        context.scaleBy(x: 1, y: -1)

        // ── 1. Background pass ───────────────────────────────────────────────
        if drawBackground {
            if let img = backgroundImage {
                // Draw image in base (non-flipped) coordinates so it appears upright.
                context.saveGState()
                context.concatenate(context.ctm.inverted())
                context.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                context.restoreGState()
            } else {
                context.setFillColor(config.globalConfig.backgroundColor.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
        }

        // ── 2. Sprite pass ───────────────────────────────────────────────────
        // Snapshot RNG so repeated render() calls produce identical output for
        // the same frame; subdivision consumes RNG locally.
        var spriteRNG = rng
        scene.render(into: context, viewTransform: activeTransform,
                     brushImages: brushImages, stampImages: stampImages,
                     elapsedFrames: elapsedFrames,
                     perspectiveStrength: config.globalConfig.camera.perspectiveStrength,
                     progressiveBrushStates: &brushProgressiveStates,
                     progressiveBrushEnabled: config.globalConfig.animating,
                     using: &spriteRNG)

        // ── 3. Overlay / border pass ─────────────────────────────────────────
        drawOverlayAndBorder(into: context, width: w, height: h)

        context.restoreGState()
    }

    private func drawOverlayAndBorder(into context: CGContext, width w: Double, height h: Double) {
        let overlay = config.globalConfig.overlayColor
        if overlay.a > 0 {
            context.saveGState()
            context.setFillColor(overlay.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.restoreGState()
        }

        let borderWidth = max(0.0, config.globalConfig.borderWidth)
                       * Double(max(1, config.globalConfig.qualityMultiple))
        guard borderWidth > 0 else { return }

        context.saveGState()
        context.setStrokeColor(config.globalConfig.borderColor.cgColor)
        context.setLineWidth(CGFloat(borderWidth))
        let inset = borderWidth / 2.0
        context.stroke(CGRect(
            x: inset,
            y: inset,
            width: max(0.0, w - borderWidth),
            height: max(0.0, h - borderWidth)
        ))
        context.restoreGState()
    }

    // MARK: - makeFrame helpers

    /// Renders onto a persistent canvas (accumulation / trail mode).
    ///
    /// Sprite rendering is gated on `sceneAdvancedThisFrame` so that the 60 fps display
    /// timer does not accumulate more sprite layers per second than the virtual frame rate.
    /// Without this gate, a fast (small) canvas would show many more accumulated draw
    /// cycles than a slow (large) canvas over the same wall-clock duration.
    private mutating func makeAccumulatedFrame(width w: Int, height h: Int) -> CGImage? {
        let isFirstFrame = accumulationCanvas == nil
        if isFirstFrame {
            guard let canvas = AccumulationCanvas(width: w, height: h) else { return nil }
            accumulationCanvas = canvas
        }
        guard let canvas = accumulationCanvas else { return nil }
        // Draw background on the first frame.  On subsequent frames, render sprites
        // only when the scene has actually advanced a virtual frame this tick.
        if isFirstFrame || sceneAdvancedThisFrame {
            renderImpl(into: canvas.ctx, drawBackground: isFirstFrame)
            sceneAdvancedThisFrame = false
        }
        return canvas.ctx.makeImage()
    }

    /// Advance the scene one virtual-frame step and accumulate the result onto the
    /// persistent canvas without applying softness blur.
    ///
    /// Use this for sub-stepping large delta-time intervals so that slow high-resolution
    /// canvases receive the same number of distinct sprite-layer passes per virtual second
    /// as fast low-resolution ones.  Call `makeFrame()` once after all sub-steps to obtain
    /// the display image with blur applied.
    public mutating func stepAndAccumulate(deltaTime: Double? = nil) {
        advance(deltaTime: deltaTime)
        let w = Int(viewTransform.canvasSize.width)
        let h = Int(viewTransform.canvasSize.height)
        guard w > 0, h > 0, config.globalConfig.drawBackgroundOnce else { return }
        _ = makeAccumulatedFrame(width: w, height: h)
    }

    /// Creates and renders to a fresh canvas each call (independent-frame mode).
    private mutating func makeFreshFrame(width w: Int, height h: Int) -> CGImage? {
        let bytesPerRow = w * 4
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: h * bytesPerRow)
        defer { buf.deallocate() }
        buf.initialize(repeating: 0, count: h * bytesPerRow)

        guard let ctx = CGContext(
            data:             buf,
            width:            w,
            height:           h,
            bitsPerComponent: 8,
            bytesPerRow:      bytesPerRow,
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        renderImpl(into: ctx, drawBackground: true)
        return ctx.makeImage()
    }

    // MARK: - Camera

    /// Returns a `ViewTransform` with the camera animation applied for the current frame.
    /// When camera is disabled returns `viewTransform` unchanged.
    private func cameraTransform() -> ViewTransform {
        let cam = config.globalConfig.camera
        guard cam.enabled else { return viewTransform }

        let fps   = max(1.0, config.globalConfig.targetFPS)
        let track = cam.tracking.enabled
            ? DriverEvaluator.evaluate(cam.tracking, globalElapsed: elapsedFrames, targetFPS: fps, spriteIndex: 0)
            : Vector2D.zero
        let pan   = cam.pan.enabled
            ? DriverEvaluator.evaluate(cam.pan,      globalElapsed: elapsedFrames, targetFPS: fps, spriteIndex: 0)
            : Vector2D.zero
        let z     = cam.zoom.enabled
            ? DriverEvaluator.evaluate(cam.zoom,     globalElapsed: elapsedFrames, targetFPS: fps, spriteIndex: 0)
            : 1.0
        let rot   = cam.rotation.enabled
            ? DriverEvaluator.evaluate(cam.rotation, globalElapsed: elapsedFrames, targetFPS: fps, spriteIndex: 0)
            : 0.0
        let tracked = rotated(track, degrees: rot)

        return ViewTransform(
            canvasSize: viewTransform.canvasSize,
            offset:     Vector2D(x: viewTransform.offset.x + pan.x - tracked.x * max(0.01, z),
                                 y: viewTransform.offset.y + pan.y + tracked.y * max(0.01, z)),
            zoom:       max(0.01, z),
            rotation:   rot
        )
    }

    private func rotated(_ v: Vector2D, degrees: Double) -> Vector2D {
        guard degrees != 0 else { return v }
        let rad = degrees * .pi / 180.0
        let cosR = cos(rad)
        let sinR = sin(rad)
        return Vector2D(x: v.x * cosR - v.y * sinR,
                        y: v.x * sinR + v.y * cosR)
    }

    // MARK: - Private helpers

    private static func loadImage(path: String) -> CGImage? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image  = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    /// Load all PNG files from `<projectDirectory>/brushes/`.
    private static func loadBrushImages(projectDirectory: URL) -> [String: CGImage] {
        loadPNGImages(directory: projectDirectory.appendingPathComponent("brushes")).compactMapValues {
            brushMaskImage(from: $0)
        }
    }

#if canImport(AppKit)
    /// Load all image files (SVG, PNG, JPG, TIFF, GIF) from `<projectDirectory>/svgs/sprites/`,
    /// keyed by filename. NSImage handles all formats natively.
    private static func loadSVGImages(projectDirectory: URL) -> [String: NSImage] {
        let directory = projectDirectory.appendingPathComponent("svgs/sprites")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [:] }
        let supported: Set<String> = ["svg", "png", "jpg", "jpeg", "tiff", "tif", "gif", "webp"]
        var result: [String: NSImage] = [:]
        for url in entries where supported.contains(url.pathExtension.lowercased()) {
            if let img = NSImage(contentsOf: url) {
                result[url.lastPathComponent] = img
            }
        }
        return result
    }
#endif

    /// Load all PNG files from `directory`, keyed by filename.
    /// Returns an empty dict when the directory does not exist or cannot be read.
    private static func loadPNGImages(directory: URL) -> [String: CGImage] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: CGImage] = [:]
        for url in entries where url.pathExtension.lowercased() == "png" {
            let cfURL = url as CFURL
            guard let src = CGImageSourceCreateWithURL(cfURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            result[url.lastPathComponent] = img
        }
        return result
    }

    /// Convert brush PNGs into luminance masks before CoreGraphics clipping.
    ///
    /// Brush images may be saved as either true greyscale PNGs or opaque RGBA
    /// black/white PNGs. `clip(to:mask:)` can otherwise treat RGBA alpha as the
    /// mask and tint the full rectangular image, producing a visible square.
    static func brushMaskImage(from image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let rgbaBytesPerRow = w * 4
        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: h * rgbaBytesPerRow)
        rgba.initialize(repeating: 0, count: h * rgbaBytesPerRow)
        defer { rgba.deallocate() }

        guard let rgbaCtx = CGContext(
            data: rgba,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: rgbaBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        rgbaCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hasTransparentPixels = false
        for i in stride(from: 3, to: h * rgbaBytesPerRow, by: 4) where rgba[i] < 250 {
            hasTransparentPixels = true
            break
        }

        let maskBytesPerRow = w
        let mask = UnsafeMutablePointer<UInt8>.allocate(capacity: h * maskBytesPerRow)
        mask.initialize(repeating: 0, count: h * maskBytesPerRow)
        defer { mask.deallocate() }

        for y in 0..<h {
            for x in 0..<w {
                let src = y * rgbaBytesPerRow + x * 4
                let dst = y * maskBytesPerRow + x
                if hasTransparentPixels {
                    mask[dst] = rgba[src + 3]
                } else {
                    let r = Double(rgba[src])
                    let g = Double(rgba[src + 1])
                    let b = Double(rgba[src + 2])
                    mask[dst] = UInt8(max(0, min(255, Int((0.299 * r + 0.587 * g + 0.114 * b).rounded()))))
                }
            }
        }

        guard let maskCtx = CGContext(
            data: mask,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: maskBytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return maskCtx.makeImage()
    }

    /// Pre-blur brush images for every unique `blurRadius > 0` found in `config`.
    ///
    /// Blurred variants are stored alongside the originals using a composite key
    /// Pre-blur brush images for every unique `blurRadius > 0` found in `config`.
    ///
    /// Images passed in are already scaled by `qualityMultiple`.  The blur is applied
    /// at `radius * qualityMultiple` (matching Scala's `BrushConfig.scalePixelValues`
    /// which scales blurRadius by quality before calling `BrushLibrary.getBrush`).
    ///
    /// Blurred variants are stored alongside the originals using a composite key
    /// `"<filename>@<scaledRadius>"` — the same value that `BrushConfig.scaled(by:)`
    /// produces for `blurRadius` at render time, so the lookup always hits.
    private static func preblurBrushImages(
        _ images: [String: CGImage],
        config: RenderingConfig,
        qualityMultiple: Int
    ) -> [String: CGImage] {
        // Collect unique logical blur radii from all brush renderers.
        var logicalRadii: Set<Int> = []
        for set in config.library.rendererSets {
            for renderer in set.renderers {
                if let r = renderer.brushConfig?.blurRadius, r > 0 {
                    logicalRadii.insert(r)
                }
            }
        }
        guard !logicalRadii.isEmpty else { return images }

        var result = images
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        for (filename, cgImage) in images {
            for logicalRadius in logicalRadii {
                // Scale blur radius by quality to match Scala's behaviour.
                let scaledRadius = logicalRadius * qualityMultiple
                guard let blurred = LoomEngine.boxBlur(cgImage, radius: scaledRadius,
                                                        ciContext: ciContext) else { continue }
                // Key uses the scaled radius — matches BrushConfig.scaled(by: quality).blurRadius.
                result["\(filename)@\(scaledRadius)"] = blurred
            }
        }
        return result
    }

    /// Scale all images in `dict` by integer `factor` using bicubic resampling.
    ///
    /// Matches Scala's `BrushLibrary.scaleImage` which scales brush PNGs by
    /// `qualityMultiple` before blurring so that pixel-space blur radii are
    /// proportional to the actual image dimensions at any quality setting.
    private static func scaleImages(_ images: [String: CGImage], by factor: Int) -> [String: CGImage] {
        var result: [String: CGImage] = [:]
        for (name, img) in images {
            let newW = img.width  * factor
            let newH = img.height * factor
            let isGray = img.colorSpace?.model == .monochrome
            let colorSpace = isGray
                ? CGColorSpaceCreateDeviceGray()
                : CGColorSpaceCreateDeviceRGB()
            let bitmapInfo: UInt32 = isGray ? 0 : CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(
                data:             nil,
                width:            newW,
                height:           newH,
                bitsPerComponent: 8,
                bytesPerRow:      0,
                space:            colorSpace,
                bitmapInfo:       bitmapInfo
            ) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: newW, height: newH))
            if let scaled = ctx.makeImage() { result[name] = scaled }
        }
        return result
    }

    /// Box blur matching Scala's `ConvolveOp` with a uniform `(2r+1)×(2r+1)` kernel.
    ///
    /// `CIBoxBlur.inputRadius` is the half-width of the box, which produces the same
    /// kernel dimensions as Scala's `radius * 2 + 1` size.
    ///
    /// Core Image may convert a grayscale input to RGBA internally.  We explicitly
    /// render the result back into a DeviceGray context so the output CGImage remains
    /// a single-channel grayscale image, which is required for `clip(to:rect:mask:)`
    /// to read pixel values as mask intensities rather than the alpha channel.
    private static func boxBlur(_ image: CGImage, radius: Int,
                                 ciContext: CIContext) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIBoxBlur") else { return nil }
        filter.setValue(ciImage,       forKey: kCIInputImageKey)
        filter.setValue(Float(radius), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // Crop to the original extent — CIBoxBlur expands bounds by the radius.
        let cropped = output.cropped(to: ciImage.extent)

        // Render to an intermediate CGImage (may be RGBA at this point).
        guard let intermediate = ciContext.createCGImage(cropped, from: cropped.extent) else { return nil }

        // Re-draw into a DeviceGray context so clip(to:rect:mask:) reads luminance as mask.
        let w = image.width, h = image.height
        guard let grayCtx = CGContext(
            data:             nil,
            width:            w,
            height:           h,
            bitsPerComponent: 8,
            bytesPerRow:      0,
            space:            CGColorSpaceCreateDeviceGray(),
            bitmapInfo:       0
        ) else { return nil }
        grayCtx.draw(intermediate, in: CGRect(x: 0, y: 0, width: w, height: h))
        return grayCtx.makeImage()
    }
}

// MARK: - AccumulationCanvas

/// Heap-backed bitmap canvas whose lifetime is managed as a Swift class.
///
/// Allocating the pixel buffer via `UnsafeMutablePointer.allocate` ensures the
/// memory address is stable for the lifetime of the canvas — a requirement of
/// the `CGContext(data:...)` API, which holds a raw pointer to the buffer.
private final class AccumulationCanvas: @unchecked Sendable {

    let ctx: CGContext
    private let buffer: UnsafeMutablePointer<UInt8>

    init?(width: Int, height: Int) {
        let bytesPerRow = width * 4
        let count = height * bytesPerRow
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buf.initialize(repeating: 0, count: count)

        guard let c = CGContext(
            data:             buf,
            width:            width,
            height:           height,
            bitsPerComponent: 8,
            bytesPerRow:      bytesPerRow,
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            buf.deallocate()
            return nil
        }
        buffer = buf
        ctx    = c
    }

    deinit {
        buffer.deallocate()
    }
}
