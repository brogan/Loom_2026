import CoreGraphics
import CoreImage
import Foundation
import ImageIO

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
    private let viewTransform:  ViewTransform
    private let backgroundImage: CGImage?   // nil when backgroundImagePath is empty or unreadable
    private let brushImages:    [String: CGImage]  // keyed by filename, from <project>/brushes/
    private let stampImages:    [String: CGImage]  // keyed by filename, from <project>/stamps/
    private var rng:            SystemRandomNumberGenerator
    private var frameCount:     Int
    /// Accumulated fractional frame count (= sum of deltaTime × targetFPS across all advances).
    /// Used as the meander-phase clock so brush animation is frame-rate independent.
    private var elapsedFrames:  Double

    /// Persistent canvas for accumulation-mode rendering (`drawBackgroundOnce = true`).
    ///
    /// In accumulation mode each `makeFrame()` call renders onto the same canvas,
    /// so the overlay color progressively fades old content (Loom's trail effect).
    private var accumulationCanvas: AccumulationCanvas?

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
    }

    // MARK: - Public accessors

    /// The project's global configuration.
    public var globalConfig: GlobalConfig { config.globalConfig }

    /// Canvas size in pixels (width × qualityMultiple, height × qualityMultiple).
    public var canvasSize: CGSize { viewTransform.canvasSize }

    /// Number of times `advance()` has been called.
    public var currentFrame: Int { frameCount }

    // MARK: - Advance

    /// Step all sprite animations one frame forward and increment `currentFrame`.
    ///
    /// - Parameter deltaTime: Wall-clock seconds since the previous call.
    ///   Defaults to `1.0 / targetFPS` so callers that don't have a real clock
    ///   (export, testing) get the correct fixed-rate behaviour without change.
    public mutating func advance(deltaTime: Double? = nil) {
        let fps = config.globalConfig.targetFPS
        let dt  = deltaTime ?? (1.0 / max(1.0, fps))
        // Global animating flag is the master switch: when false, all sprite animation
        // is suppressed and the scene is held at its initial (frame-0) state.
        if config.globalConfig.animating {
            scene.advance(deltaTime: dt, targetFPS: fps, using: &rng)
        }
        elapsedFrames += dt * max(1.0, fps)
        frameCount    += 1
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
    public func render(into context: CGContext) {
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

        if config.globalConfig.drawBackgroundOnce {
            return makeAccumulatedFrame(width: w, height: h)
        } else {
            return makeFreshFrame(width: w, height: h)
        }
    }

    // MARK: - Private render implementation

    private func renderImpl(into context: CGContext, drawBackground: Bool) {
        let w = viewTransform.canvasSize.width
        let h = viewTransform.canvasSize.height

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
        // the same frame (render is non-mutating; subdivision consumes RNG).
        var spriteRNG = rng
        scene.render(into: context, viewTransform: viewTransform,
                     brushImages: brushImages, stampImages: stampImages,
                     elapsedFrames: elapsedFrames, using: &spriteRNG)

        // ── 3. Overlay pass ──────────────────────────────────────────────────
        // NOTE: overlayColor is loaded from XML but Scala's MySketch.draw never
        // calls drawOverlay, so the overlay is effectively unused in the reference
        // implementation.  Skipped here to match Scala output.  When a proper
        // trail/fade effect is needed this is where it belongs.

        context.restoreGState()
    }

    // MARK: - makeFrame helpers

    /// Renders onto a persistent canvas (accumulation / trail mode).
    private mutating func makeAccumulatedFrame(width w: Int, height h: Int) -> CGImage? {
        let isFirstFrame = accumulationCanvas == nil
        if isFirstFrame {
            print("[LoomEngine] creating AccumulationCanvas \(w)×\(h) drawBackgroundOnce=\(config.globalConfig.drawBackgroundOnce)")
            guard let canvas = AccumulationCanvas(width: w, height: h) else {
                print("[LoomEngine] AccumulationCanvas init FAILED")
                return nil
            }
            accumulationCanvas = canvas
        }
        guard let canvas = accumulationCanvas else { return nil }
        // First frame: draw background so the canvas starts opaque.
        // Subsequent frames: skip background to accumulate on previous content.
        renderImpl(into: canvas.ctx, drawBackground: isFirstFrame)
        let img = canvas.ctx.makeImage()
        if isFirstFrame {
            print("[LoomEngine] first frame makeImage() → \(img != nil ? "\(img!.width)×\(img!.height)" : "nil")")
        }
        return img
    }

    /// Creates and renders to a fresh canvas each call (independent-frame mode).
    private func makeFreshFrame(width w: Int, height h: Int) -> CGImage? {
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
        loadPNGImages(directory: projectDirectory.appendingPathComponent("brushes"))
    }

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
