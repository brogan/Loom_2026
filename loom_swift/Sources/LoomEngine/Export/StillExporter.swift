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
    /// - Throws: `StillExporterError.renderFailed` when the engine produces no image.
    ///           `StillExporterError.writeFailed` when the file cannot be written.
    public static func exportPNG(engine: Engine, to url: URL) throws {
        guard let image = engine.makeFrame() else {
            throw StillExporterError.renderFailed
        }
        try write(image: image, to: url, type: UTType.png)
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
