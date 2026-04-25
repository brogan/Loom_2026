import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

// MARK: - VideoExporter

/// Renders an engine animation to a video file using `AVAssetWriter`.
///
/// ```swift
/// let exporter = VideoExporter()
/// let settings = VideoExporter.Settings(fps: 30, duration: 5.0, outputURL: url)
/// try await exporter.export(engine: engine, settings: settings) { progress in
///     print("Export progress: \(Int(progress * 100))%")
/// }
/// ```
///
/// ### Frame ordering
/// `export` calls `engine.update(deltaTime:)` then captures a frame for each
/// index in `0 ..< totalFrames`.  The engine is advanced inside the export loop;
/// its state on entry is treated as "just before frame 0."
///
/// ### Coordinate-system note
/// `CGContext` is bottom-left-origin; video pixel buffers are top-left (raster order).
/// Internally each frame is obtained from `Engine.makeFrame()` (a correctly-oriented
/// `CGImage`) and then drawn into the pixel buffer via a Y-flip transform, giving
/// correct video orientation without modifying the engine's rendering path.
public final class VideoExporter {

    // MARK: - Settings

    public struct Settings {
        /// Frames per second. Default: 30.
        public var fps: Int

        /// Total duration in seconds.
        public var duration: Double

        /// Video codec. Default: `.h264`.
        public var codec: AVVideoCodecType

        /// Destination file URL (`.mov` container).
        public var outputURL: URL

        public init(
            fps: Int = 30,
            duration: Double,
            codec: AVVideoCodecType = .h264,
            outputURL: URL
        ) {
            self.fps       = fps
            self.duration  = duration
            self.codec     = codec
            self.outputURL = outputURL
        }

        /// Total frame count derived from `duration × fps` (minimum 1).
        public var totalFrames: Int { max(1, Int(duration * Double(fps))) }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Export

    /// Render `engine` to a video file described by `settings`.
    ///
    /// - Parameters:
    ///   - engine: The engine to render. Its frame loop (if any) is **not** driven
    ///     by this method; `update` is called internally for each video frame.
    ///   - settings: Output codec, fps, duration, and destination URL.
    ///   - progress: Optional callback invoked after each frame is written.
    ///     Receives a value in `(0, 1]`; 1.0 indicates the final frame was written.
    ///     Called on the same actor/executor as `export`.
    ///
    /// - Throws: Any `AVFoundation` error from the asset writer, or
    ///   `VideoExporterError.setupFailed` if the writer cannot be initialised.
    public func export(
        engine: Engine,
        settings: Settings,
        progress: ((Double) -> Void)? = nil
    ) async throws {

        let size        = engine.canvasSize
        let w           = Int(size.width)
        let h           = Int(size.height)
        let fps         = settings.fps
        let totalFrames = settings.totalFrames

        // ── Clean up any pre-existing file ───────────────────────────────────
        try? FileManager.default.removeItem(at: settings.outputURL)

        // ── AVAssetWriter setup ──────────────────────────────────────────────
        let writer = try AVAssetWriter(
            outputURL: settings.outputURL,
            fileType: .mov
        )

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  settings.codec.rawValue,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
        ]
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: w,
            kCVPixelBufferHeightKey          as String: h,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw VideoExporterError.setupFailed("Cannot add video input to writer")
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw VideoExporterError.setupFailed("Pixel buffer pool unavailable after startWriting")
        }

        // ── Frame loop ───────────────────────────────────────────────────────
        let dt = 1.0 / Double(fps)

        for frameIndex in 0..<totalFrames {

            // 1. Advance the engine one frame.
            engine.update(deltaTime: dt)

            // 2. Render to a CGImage (correctly oriented, bottom-left origin).
            guard let cgImage = engine.makeFrame() else { continue }

            // 3. Allocate a pixel buffer from the pool.
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pb = pixelBuffer else { continue }

            // 4. Draw the CGImage into the pixel buffer.
            //    Engine.makeFrame() returns a CGImage that is already in top-left
            //    raster order (the Y-flip is applied inside renderImpl).  Drawing it
            //    directly into a plain CGContext (no extra transform) maps:
            //      image row 0 → CGContext y=0 (bottom) → buffer offset 0 → video row 0 (top) ✓
            //    A second Y-flip would re-invert the image and produce upside-down video.
            CVPixelBufferLockBaseAddress(pb, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pb) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                let bitmapInfo  = CGImageAlphaInfo.premultipliedFirst.rawValue
                               | CGBitmapInfo.byteOrder32Little.rawValue
                if let ctx = CGContext(
                    data:             baseAddress,
                    width:            w,
                    height:           h,
                    bitsPerComponent: 8,
                    bytesPerRow:      bytesPerRow,
                    space:            CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:       bitmapInfo
                ) {
                    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            // 5. Wait until the writer can accept a new sample.
            //    Even with expectsMediaDataInRealTime = false, AVFoundation can
            //    apply backpressure while it processes its internal encode queue.
            //    Task.yield() returns control to the Swift concurrency runtime so
            //    AVFoundation's internal processing can make progress.
            while !writerInput.isReadyForMoreMediaData {
                await Task.yield()
            }

            // 6. Append pixel buffer with presentation timestamp.
            let pts = CMTime(value: CMTimeValue(frameIndex),
                             timescale: CMTimeScale(fps))
            adaptor.append(pb, withPresentationTime: pts)

            // 6. Report progress: value in (0, 1].
            let p = Double(frameIndex + 1) / Double(totalFrames)
            progress?(p)
        }

        // ── Finish writing ───────────────────────────────────────────────────
        writerInput.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        if let error = writer.error {
            throw error
        }
    }
}

// MARK: - VideoExporterError

public enum VideoExporterError: Error {
    /// The `AVAssetWriter` could not be configured as required.
    case setupFailed(String)
}
