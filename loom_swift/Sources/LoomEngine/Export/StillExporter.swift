import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - StillExporter

/// Renders one engine frame to an image file on disk.
///
/// ```swift
/// try StillExporter.exportPNG(engine: engine, to: outputURL)
/// ```
public enum StillExporter {

    /// Render the current engine state and write a PNG file to `url`.
    ///
    /// The engine is not advanced; call `engine.update(deltaTime:)` beforehand
    /// if you want a specific frame.
    ///
    /// - Parameter transparentBackground: write the background as transparent
    ///   rather than `GlobalConfig.backgroundColor`/`backgroundImage`, for
    ///   compositing the still over other content. PNG-only (JPEG has no alpha
    ///   channel, so `exportJPEG` doesn't take this parameter — a "transparent"
    ///   JPEG would just show through as black). See `Engine.makeFrame`.
    /// - Parameter cropPixelRect: when non-nil, crops the rendered frame to this
    ///   rect before writing — pixel units, origin at the top-left, Y increasing
    ///   downward (the same screen-space convention `ViewTransform` documents,
    ///   not `CGContext`'s native bottom-left/Y-up one). 2026-07-14, for
    ///   exporting a sub-region of the canvas (e.g. matching an external app's
    ///   document size) without a separate crop pass in another tool.
    /// - Throws: `StillExporterError.renderFailed` when the engine produces no image,
    ///   or when `cropPixelRect` produces an empty/invalid result.
    ///   `StillExporterError.writeFailed` when the file cannot be written.
    public static func exportPNG(
        engine: Engine, to url: URL,
        transparentBackground: Bool = false,
        cropPixelRect: CGRect? = nil
    ) throws {
        guard var image = engine.makeFrame(transparentBackground: transparentBackground) else {
            throw StillExporterError.renderFailed
        }
        if let cropPixelRect {
            guard let cropped = crop(image, to: cropPixelRect) else {
                throw StillExporterError.renderFailed
            }
            image = cropped
        }
        try write(image: image, to: url, type: UTType.png)
    }

    /// Crops `image` to `rect`, specified in the image's own pixel space with
    /// the origin at the top-left and Y increasing downward (2026-07-14).
    ///
    /// `CGContext.draw(_:in:)` orients an image "right side up" in the final
    /// result regardless of the destination context's own flip state — unlike
    /// path/stroke drawing, which needs an explicit flip transform to render
    /// top-left-origin coordinates correctly (see `RenderEngine`'s Y-flip
    /// setup). So extracting a top-left-relative sub-rect means drawing the
    /// *whole* source image into a small unflipped destination context, offset
    /// so the desired sub-region lands at the destination's own origin: with
    /// `cropBottomY` the crop rect's bottom edge (still measured top-down from
    /// the source image's top), the vertical draw offset is `cropBottomY -
    /// imageHeight` — verified directly by `StillExporterCropTests` against a
    /// four-quadrant fixture image rather than left as an unverified derivation.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let outW = Int(rect.width.rounded())
        let outH = Int(rect.height.rounded())
        guard outW > 0, outH > 0 else { return nil }
        guard let context = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let imageHeight = CGFloat(image.height)
        let cropBottomY = rect.minY + rect.height
        let yOffset = cropBottomY - imageHeight
        context.draw(image, in: CGRect(
            x: -rect.minX, y: yOffset,
            width: CGFloat(image.width), height: imageHeight
        ))
        return context.makeImage()
    }

    /// Render the current engine state and write a JPEG file to `url`.
    ///
    /// - Parameter quality: Compression quality in the range 0.0 (most compressed)
    ///   to 1.0 (least compressed). Default is 0.9.
    /// - Throws: `StillExporterError.renderFailed` / `.writeFailed`.
    public static func exportJPEG(engine: Engine, to url: URL, quality: Double = 0.9) throws {
        guard let image = engine.makeFrame() else {
            throw StillExporterError.renderFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        try write(image: image, to: url, type: UTType.jpeg, properties: properties)
    }

    // MARK: - Private

    private static func write(
        image: CGImage,
        to url: URL,
        type: UTType,
        properties: [CFString: Any]? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1, nil
        ) else {
            throw StillExporterError.writeFailed
        }
        CGImageDestinationAddImage(destination, image,
                                   properties.map { $0 as CFDictionary })
        guard CGImageDestinationFinalize(destination) else {
            throw StillExporterError.writeFailed
        }
    }
}

// MARK: - StillExporterError

public enum StillExporterError: Error, Equatable {
    /// The engine could not produce a `CGImage` (canvas size is zero or context creation failed).
    case renderFailed
    /// `CGImageDestination` could not be created or finalized at the given URL.
    case writeFailed
}
