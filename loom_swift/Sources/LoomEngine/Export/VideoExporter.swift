import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import os

// MARK: - VideoExporter

/// Renders an engine animation to a video file using `AVAssetWriter`.
///
/// ```swift
/// let exporter = VideoExporter()
/// let settings = VideoExporter.Settings(fps: 30, endFrame: 150, outputURL: url)
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

    private static let log = Logger(subsystem: "com.loom.engine", category: "VideoExporter")

    // MARK: - Settings

    public struct Settings {
        /// Frames per second. Default: 30.
        public var fps: Int

        /// First frame to include in the export (0-based). Default: 0.
        public var startFrame: Int

        /// Last frame to include (exclusive upper bound). Must be > startFrame.
        public var endFrame: Int

        /// Video codec. Default: `.h264`.
        public var codec: AVVideoCodecType

        /// Destination file URL (`.mov` container).
        public var outputURL: URL

        /// Optional source audio file to mux into the exported video as a
        /// second track. `nil` (the default) produces a silent video,
        /// matching this type's original behaviour.
        public var audioURL: URL?

        /// The audio file's start offset, in frames, relative to the same
        /// absolute timeline frame numbering `startFrame`/`endFrame` use
        /// (i.e. the same convention as `AudioController.offsetFrames` in
        /// the app layer). Ignored when `audioURL` is `nil`.
        public var audioOffsetFrames: Int

        public init(
            fps: Int = 30,
            startFrame: Int = 0,
            endFrame: Int,
            codec: AVVideoCodecType = .h264,
            outputURL: URL,
            audioURL: URL? = nil,
            audioOffsetFrames: Int = 0
        ) {
            self.fps               = fps
            self.startFrame        = max(0, startFrame)
            self.endFrame          = endFrame
            self.codec             = codec
            self.outputURL         = outputURL
            self.audioURL          = audioURL
            self.audioOffsetFrames = audioOffsetFrames
        }

        /// Number of frames to capture.
        public var totalFrames: Int { max(1, endFrame - max(0, startFrame)) }

        /// Duration in seconds derived from frame range and fps.
        public var durationSeconds: Double { Double(totalFrames) / Double(fps) }
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
    ///   - onBeforeFrame: Optional callback invoked with the absolute frame
    ///     index (`settings.startFrame`-relative — i.e. the same frame
    ///     numbering `engine.currentFrame` uses) immediately before that
    ///     frame's `engine.update(deltaTime:)` call. Lets a caller mutate the
    ///     engine mid-export — e.g. replaying a recorded session's events at
    ///     their exact frame numbers — without this method needing to know
    ///     anything about what's driving those mutations.
    ///
    /// - Throws: Any `AVFoundation` error from the asset writer, or
    ///   `VideoExporterError.setupFailed` if the writer cannot be initialised.
    public func export(
        engine: Engine,
        settings: Settings,
        progress: ((Double) -> Void)? = nil,
        onBeforeFrame: (@Sendable (Int) -> Void)? = nil
    ) async throws {

        let size        = engine.canvasSize
        let w           = Int(size.width)
        let h           = Int(size.height)
        let fps         = settings.fps
        let totalFrames = settings.totalFrames

        // ── Pre-flight resolution check ──────────────────────────────────────
        // H.264 and HEVC hardware encoders on macOS have fixed maximum frame
        // dimensions. Exceeding them doesn't degrade gracefully — VideoToolbox
        // fails immediately with an undocumented internal OSStatus (-10279
        // observed) that gives no indication of the real cause, and it does so
        // on every attempt regardless of frame count or app restart. `canvasSize`
        // already has the project's Quality multiplier baked in, so a modest
        // base canvas at a high Quality setting can silently produce an export
        // resolution far larger than the "Size" field in the export sheet
        // suggests — check and fail with a clear message before ever touching
        // the asset writer.
        if let maxDimension = Self.maxSupportedDimension(for: settings.codec),
           w > maxDimension || h > maxDimension {
            let quality = engine.globalConfig.qualityMultiple
            throw VideoExporterError.setupFailed(
                "Export resolution \(w)×\(h)px exceeds the \(maxDimension)px-per-side limit "
                + "of \(settings.codec.rawValue) encoding on this Mac. This size already includes "
                + "the project's Quality multiplier (\(quality)×) — lower Quality in the Global "
                + "tab, reduce the canvas size, or choose a different codec, then retry."
            )
        }

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

        // ── Optional audio track ─────────────────────────────────────────────
        // Must be added to the writer before startWriting() — both inputs have
        // to be attached up front, even though audio samples aren't actually
        // appended until after the video loop finishes below.
        var audioComponents: (
            reader: AVAssetReader, output: AVAssetReaderTrackOutput,
            input: AVAssetWriterInput, ptsShiftSeconds: Double
        )?
        if let audioURL = settings.audioURL {
            audioComponents = try await Self.setupAudioInput(audioURL: audioURL, settings: settings, writer: writer)
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw VideoExporterError.setupFailed("Pixel buffer pool unavailable after startWriting")
        }

        // ── Frame loop ───────────────────────────────────────────────────────
        let dt         = 1.0 / Double(fps)
        let startFrame = settings.startFrame

        // Pre-advance to startFrame without capturing any output.
        for _ in 0..<startFrame {
            engine.update(deltaTime: dt)
        }

        // Start the audio track's read alongside the video loop rather than
        // after it. AVAssetWriter shares internal buffering/backpressure
        // across all of a writer's inputs — if one input (audio) receives
        // zero samples for the entire duration the other (video) is being
        // fed, the writer throttles the active input's isReadyForMoreMediaData
        // to prevent the tracks' presentation times from diverging without
        // bound, which stalls the video loop forever (observed: hung
        // indefinitely partway through, e.g. frame 29 of 820). Draining a
        // few ready audio samples per video frame keeps both tracks
        // advancing together instead of fully serializing one after the other.
        let audioShiftTime = audioComponents.map { CMTime(seconds: $0.ptsShiftSeconds, preferredTimescale: 600) }
        // Set once copyNextSampleBuffer first returns nil (audio content
        // exhausted) and audio.input.markAsFinished() has been called for it —
        // guards against calling markAsFinished twice, and lets later code
        // skip an input that's already done.
        var audioFinished = false
        if let audio = audioComponents {
            guard audio.reader.startReading() else {
                throw VideoExporterError.setupFailed(
                    "Could not start reading audio: \(audio.reader.error?.localizedDescription ?? "unknown error")"
                )
            }
            Self.log.info("Audio setup: shiftSeconds=\(audioComponents?.ptsShiftSeconds ?? 0, privacy: .public) totalFrames=\(totalFrames, privacy: .public) fps=\(fps, privacy: .public)")
        }

        // Wrapped in do/catch so any mid-loop failure can call writer.cancelWriting()
        // before propagating. Per AVAssetWriter's documented contract, releasing the
        // writer without calling cancelWriting() after a failed/abandoned session can
        // leave its VideoToolbox encoder session un-torn-down — which was silently
        // true here before this fix. A dangling encoder session from one failed
        // export can then cause the *next* export attempt to fail immediately (the
        // hardware encoder XPC service has a limited number of concurrent sessions),
        // which is indistinguishable from the original failure without this cleanup.
        do {
            for frameIndex in 0..<totalFrames {

                // 0. Let a caller mutate the engine for this exact frame
                //    (e.g. session replay) before it advances.
                onBeforeFrame?(startFrame + frameIndex)

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
                //    Also bail out if the writer has already failed — without this,
                //    a failed writer can leave isReadyForMoreMediaData permanently
                //    false and this loop would spin forever instead of surfacing
                //    the error.
                while !writerInput.isReadyForMoreMediaData {
                    if writer.status == .failed {
                        throw VideoExporterError.writeFailed(
                            frameIndex: frameIndex, totalFrames: totalFrames, underlying: writer.error
                        )
                    }
                    await Task.yield()
                }

                // 6. Append pixel buffer with presentation timestamp. append's Bool
                //    result and the writer's status must both be checked here — this
                //    is the only point at which a mid-export failure (disk full,
                //    encoder session lost, etc.) is actually detectable. Ignoring it
                //    (as this used to) makes the loop plough through every remaining
                //    frame reporting fake progress, so a failure at frame 40 of 3600
                //    only surfaces after the other 3560 frames were rendered for
                //    nothing, with no indication of when or why it actually broke.
                let pts = CMTime(value: CMTimeValue(frameIndex),
                                 timescale: CMTimeScale(fps))
                let appended = adaptor.append(pb, withPresentationTime: pts)
                guard appended, writer.status != .failed else {
                    throw VideoExporterError.writeFailed(
                        frameIndex: frameIndex, totalFrames: totalFrames, underlying: writer.error
                    )
                }

                // 7. Opportunistically append any audio samples currently ready,
                //    so the audio track keeps advancing alongside the video
                //    track instead of sitting completely unfed until the video
                //    loop finishes (see the comment above the loop for why that
                //    stalls the writer). Non-blocking: only appends samples the
                //    writer input is already ready for, right now.
                //
                //    Critical: if the audio track's real content runs out
                //    before the video does (copyNextSampleBuffer returns nil),
                //    audio.input MUST be marked finished right here. Leaving
                //    it un-fed AND un-finished reproduces the exact same
                //    writer backpressure stall this loop exists to avoid —
                //    the writer has no way to know the silence is
                //    intentional rather than a track that's merely behind —
                //    and it will throttle the still-active video input
                //    indefinitely once its buffer margin runs out (observed:
                //    hangs deterministically at the frame where the audio
                //    file's usable range ends, e.g. frame 813 of 820).
                if let audio = audioComponents, let shiftTime = audioShiftTime, !audioFinished {
                    while audio.input.isReadyForMoreMediaData {
                        guard let sampleBuffer = audio.output.copyNextSampleBuffer() else {
                            audio.input.markAsFinished()
                            audioFinished = true
                            Self.log.info("Audio exhausted mid-loop at video frameIndex=\(frameIndex, privacy: .public) of \(totalFrames, privacy: .public); marked finished")
                            break
                        }
                        let retimed = try Self.retimed(sampleBuffer, by: shiftTime)
                        guard audio.input.append(retimed), writer.status != .failed else {
                            throw VideoExporterError.writeFailed(
                                frameIndex: frameIndex, totalFrames: totalFrames, underlying: writer.error
                            )
                        }
                    }
                }

                // 8. Report progress: value in (0, 1].
                let p = Double(frameIndex + 1) / Double(totalFrames)
                progress?(p)
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: settings.outputURL)
            throw error
        }

        // Mark video finished *before* flushing any remaining audio below —
        // this was the cause of a second deadlock (observed hanging at frame
        // 813 of 820, right at the tail end of export): trailing audio
        // samples whose presentation time falls at/after the video's last
        // appended frame can't be accepted by the writer until it knows
        // definitively that no more video is coming. Leaving the video input
        // un-finished while the audio flush loop waits on
        // isReadyForMoreMediaData is a circular wait — the writer is holding
        // audio back to preserve correct interleaving against video data
        // that, as far as it knows, might still arrive.
        writerInput.markAsFinished()

        // ── Audio track (optional) — flush anything left unread ────────────
        // The opportunistic drain above only appends samples that were ready
        // during a video frame; this finishes off whatever remains (audio
        // track longer than the video's per-frame draining kept pace with)
        // now that nothing else is competing for the writer. Skipped
        // entirely if the in-loop drain already exhausted and finished the
        // audio input (the common case for a shorter-than-video track).
        if let audio = audioComponents, let shiftTime = audioShiftTime, !audioFinished {
            do {
                while let sampleBuffer = audio.output.copyNextSampleBuffer() {
                    let retimed = try Self.retimed(sampleBuffer, by: shiftTime)

                    while !audio.input.isReadyForMoreMediaData {
                        if writer.status == .failed {
                            throw VideoExporterError.writeFailed(
                                frameIndex: totalFrames - 1, totalFrames: totalFrames, underlying: writer.error
                            )
                        }
                        await Task.yield()
                    }
                    guard audio.input.append(retimed), writer.status != .failed else {
                        throw VideoExporterError.writeFailed(
                            frameIndex: totalFrames - 1, totalFrames: totalFrames, underlying: writer.error
                        )
                    }
                }
                audio.input.markAsFinished()
                audioFinished = true
                if audio.reader.status == .failed {
                    throw VideoExporterError.setupFailed(
                        "Audio read failed: \(audio.reader.error?.localizedDescription ?? "unknown error")"
                    )
                }
            } catch {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: settings.outputURL)
                throw error
            }
        }

        // ── Finish writing ───────────────────────────────────────────────────
        // audio input is already marked finished by one of the two paths
        // above whenever audioComponents is non-nil — never call
        // markAsFinished a second time here.
        Self.log.info("Export finishing: audioFinished=\(audioFinished, privacy: .public)")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        if let error = writer.error {
            throw VideoExporterError.writeFailed(
                frameIndex: totalFrames - 1, totalFrames: totalFrames, underlying: error
            )
        }
    }

    // MARK: - Audio track setup

    /// Prepares an audio track for muxing into `writer`: locates the source
    /// file's audio track, computes the trim/shift needed to align it against
    /// the video's frame range, and adds a paired `AVAssetWriterInput` to
    /// `writer`. Must be called (and its returned input added) before
    /// `writer.startWriting()`.
    ///
    /// Returns `nil` — not an error — when the audio file has no overlap at
    /// all with the exported frame range (e.g. the audio's offset places it
    /// entirely after the export's end frame), in which case the export
    /// simply proceeds with no audio track.
    ///
    /// The source is decoded to linear PCM rather than passed through
    /// unchanged: imported audio can be wav/mp3/m4a/flac/aac/caf, and `.mov`
    /// doesn't natively support all of those as a compressed track, so
    /// decode-then-re-encode-to-AAC is the only path that's broadly
    /// compatible regardless of the source format.
    private static func setupAudioInput(
        audioURL: URL,
        settings: Settings,
        writer: AVAssetWriter
    ) async throws -> (
        reader: AVAssetReader, output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput, ptsShiftSeconds: Double
    )? {
        let asset = AVURLAsset(url: audioURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoExporterError.setupFailed("Selected audio file has no audio track: \(audioURL.lastPathComponent)")
        }
        let assetDuration = try await asset.load(.duration).seconds

        // Same timeline-frame ↔ audio-file-time relationship the app's
        // AudioController.syncTransport uses for live playback: video PTS 0
        // corresponds to absolute frame settings.startFrame; the audio file's
        // own time 0 corresponds to absolute frame settings.audioOffsetFrames.
        // ptsShiftSeconds is the constant that maps audio-file time onto
        // output PTS: outputPTS = fileTime + ptsShiftSeconds.
        let ptsShiftSeconds = Double(settings.audioOffsetFrames - settings.startFrame) / Double(settings.fps)
        let audioStartSec = max(0, -ptsShiftSeconds)
        let audioEndSec   = min(assetDuration, settings.durationSeconds - ptsShiftSeconds)
        guard audioEndSec > audioStartSec else { return nil }

        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        guard reader.canAdd(output) else {
            throw VideoExporterError.setupFailed("Cannot read audio track from \(audioURL.lastPathComponent)")
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: audioStartSec, preferredTimescale: 600),
            end:   CMTime(seconds: audioEndSec,   preferredTimescale: 600)
        )

        var sampleRate: Double = 44_100
        var channels:   UInt32 = 2
        if let description = try await audioTrack.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            sampleRate = asbd.mSampleRate
            channels   = max(1, asbd.mChannelsPerFrame)
        }
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderBitRateKey: 192_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw VideoExporterError.setupFailed("Cannot add audio input to writer")
        }
        writer.add(input)

        return (reader, output, input, ptsShiftSeconds)
    }

    /// Returns a copy of `sampleBuffer` with every timing entry's presentation
    /// (and decode, if valid) timestamp shifted by `shift`.
    private static func retimed(_ sampleBuffer: CMSampleBuffer, by shift: CMTime) throws -> CMSampleBuffer {
        var neededCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &neededCount)
        var timingInfo = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: neededCount)
        let readStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer, entryCount: neededCount, arrayToFill: &timingInfo, entriesNeededOut: nil
        )
        guard readStatus == noErr else {
            throw VideoExporterError.setupFailed("Failed reading audio sample timing")
        }
        for i in 0..<timingInfo.count {
            timingInfo[i].presentationTimeStamp = CMTimeAdd(timingInfo[i].presentationTimeStamp, shift)
            if timingInfo[i].decodeTimeStamp.isValid {
                timingInfo[i].decodeTimeStamp = CMTimeAdd(timingInfo[i].decodeTimeStamp, shift)
            }
        }
        var newBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        guard createStatus == noErr, let result = newBuffer else {
            throw VideoExporterError.setupFailed("Failed to retime audio sample")
        }
        return result
    }

    // MARK: - Codec limits

    /// Maximum supported width/height (in pixels) for `codec`, or `nil` if unknown/unbounded.
    ///
    /// H.264 and HEVC are backed by fixed-capability hardware encoder blocks on Apple
    /// Silicon; these figures are the documented/observed per-side ceilings. ProRes has
    /// no such hard limit (it isn't restricted to a dedicated hardware encoder block in
    /// the same way), so it is left unchecked here — a real failure there still surfaces
    /// through the normal write-failure path with AVFoundation's own diagnostic.
    private static func maxSupportedDimension(for codec: AVVideoCodecType) -> Int? {
        switch codec {
        case .h264: return 4096
        case .hevc: return 8192
        default:    return nil
        }
    }
}

// MARK: - VideoExporterError

public enum VideoExporterError: Error, LocalizedError {
    /// The `AVAssetWriter` could not be configured as required.
    case setupFailed(String)

    /// A frame failed to write to the asset writer — either detected mid-loop
    /// (append returned false, or the writer's status went `.failed`) or at
    /// `finishWriting` (in which case `frameIndex` is `totalFrames - 1`, the
    /// exact frame isn't recoverable at that point). `underlying` is
    /// `AVAssetWriter.error` at the time of failure, when available; its
    /// `NSUnderlyingErrorKey` chain (disk space, encoder session, etc.) is
    /// surfaced too, since the top-level AVFoundation message alone is often
    /// a generic "The operation could not be completed."
    case writeFailed(frameIndex: Int, totalFrames: Int, underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case .setupFailed(let message):
            return message
        case .writeFailed(let frameIndex, let totalFrames, let underlying):
            var message = "Video export failed while writing frame \(frameIndex + 1) of \(totalFrames)."
            if let underlying {
                message += " " + underlying.localizedDescription
                var probe: Error? = (underlying as NSError).userInfo[NSUnderlyingErrorKey] as? Error
                while let inner = probe {
                    message += " (\(inner.localizedDescription))"
                    probe = (inner as NSError).userInfo[NSUnderlyingErrorKey] as? Error
                }
            }
            return message
        }
    }
}
