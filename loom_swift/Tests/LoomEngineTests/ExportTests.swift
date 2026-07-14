import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LoomEngine

// MARK: - Fixture / helpers

private var fixtureDir052: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_052")
}

/// Creates a unique temp-directory URL with the given file extension.
/// The file is not yet created; a `defer { cleanup(url) }` in the calling test
/// removes it after the test runs.
private func tempURL(ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("LoomExportTest_\(UUID().uuidString).\(ext)")
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - StillExporter — PNG tests

final class StillExporterPNGTests: XCTestCase {

    func testExportPNGCreatesFile() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url    = tempURL(ext: "png")
        defer { cleanup(url) }

        try StillExporter.exportPNG(engine: engine, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "exportPNG should create a file at the given URL")
    }

    func testExportPNGFileIsNonEmpty() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url    = tempURL(ext: "png")
        defer { cleanup(url) }

        try StillExporter.exportPNG(engine: engine, to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "PNG file should not be empty")
    }

    func testExportPNGDimensions() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url    = tempURL(ext: "png")
        defer { cleanup(url) }

        try StillExporter.exportPNG(engine: engine, to: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image  = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Could not read back exported PNG")
            return
        }
        XCTAssertEqual(image.width,  1080)
        XCTAssertEqual(image.height, 1080)
    }

    func testExportPNGAfterAdvancesSucceeds() throws {
        var engine = try Engine(projectDirectory: fixtureDir052)
        // Advance a few frames first — export should still work.
        for _ in 0..<10 { engine.update(deltaTime: 1.0 / 30) }
        let url = tempURL(ext: "png")
        defer { cleanup(url) }

        try StillExporter.exportPNG(engine: engine, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportPNGMultipleTimesProducesMultipleFiles() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url1   = tempURL(ext: "png")
        let url2   = tempURL(ext: "png")
        defer { cleanup(url1); cleanup(url2) }

        try StillExporter.exportPNG(engine: engine, to: url1)
        try StillExporter.exportPNG(engine: engine, to: url2)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path))
    }
}

// MARK: - StillExporter — crop tests (2026-07-14)

/// A 4×4 RGBA image, one solid color per quadrant, built directly from a raw
/// byte buffer (row 0 = the image's top row — a `CGImage`'s only convention,
/// with no separate "flip" flag) rather than via any `CGContext` drawing, so
/// the fixture's own top/bottom is unambiguous and independent of anything
/// `StillExporter.crop` itself does.
private func quadrantImage() -> CGImage {
    let w = 4, h = 4
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let red:   (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
    let green: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)
    let blue:  (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
    let white: (UInt8, UInt8, UInt8, UInt8) = (255, 255, 255, 255)
    for y in 0..<h {
        for x in 0..<w {
            let idx = (y * w + x) * 4
            let color = (y < h / 2, x < w / 2) == (true, true)  ? red
                       : (y < h / 2, x < w / 2) == (true, false) ? green
                       : (y < h / 2, x < w / 2) == (false, true) ? blue
                       : white
            data[idx] = color.0; data[idx + 1] = color.1
            data[idx + 2] = color.2; data[idx + 3] = color.3
        }
    }
    let context = CGContext(
        data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

private func averageColor(_ image: CGImage) -> (UInt8, UInt8, UInt8, UInt8) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(
        data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var sums = [Int](repeating: 0, count: 4)
    for p in 0..<(w * h) {
        for c in 0..<4 { sums[c] += Int(data[p * 4 + c]) }
    }
    let n = w * h
    return (UInt8(sums[0] / n), UInt8(sums[1] / n), UInt8(sums[2] / n), UInt8(sums[3] / n))
}

final class StillExporterCropTests: XCTestCase {

    func testCropTopLeftQuadrantIsRed() {
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertNotNil(cropped)
        let (r, g, b, _) = averageColor(cropped!)
        XCTAssertEqual(r, 255); XCTAssertEqual(g, 0); XCTAssertEqual(b, 0)
    }

    func testCropTopRightQuadrantIsGreen() {
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 2, y: 0, width: 2, height: 2))
        let (r, g, b, _) = averageColor(cropped!)
        XCTAssertEqual(r, 0); XCTAssertEqual(g, 255); XCTAssertEqual(b, 0)
    }

    func testCropBottomLeftQuadrantIsBlue() {
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 0, y: 2, width: 2, height: 2))
        let (r, g, b, _) = averageColor(cropped!)
        XCTAssertEqual(r, 0); XCTAssertEqual(g, 0); XCTAssertEqual(b, 255)
    }

    func testCropBottomRightQuadrantIsWhite() {
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 2, y: 2, width: 2, height: 2))
        let (r, g, b, _) = averageColor(cropped!)
        XCTAssertEqual(r, 255); XCTAssertEqual(g, 255); XCTAssertEqual(b, 255)
    }

    func testCropFullImageMatchesOriginalAverage() {
        // A no-op crop (the whole image) should reproduce the same overall
        // average as the source — a coarse but real end-to-end sanity check
        // distinct from the quadrant-identity tests above.
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let (r, g, b, a) = averageColor(cropped!)
        let (origR, origG, origB, origA) = averageColor(image)
        XCTAssertEqual(r, origR); XCTAssertEqual(g, origG)
        XCTAssertEqual(b, origB); XCTAssertEqual(a, origA)
    }

    func testCropOffCenterRegionSpanningQuadrantsAveragesCorrectly() {
        // A 2×2 region centered on the image (columns/rows 1-2) straddles all
        // four quadrants exactly once each — its average should be the mean of
        // all four colors, a check that doesn't depend on the crop aligning
        // with any single quadrant boundary (unlike the four tests above).
        let image = quadrantImage()
        let cropped = StillExporter.crop(image, to: CGRect(x: 1, y: 1, width: 2, height: 2))
        let (r, g, b, _) = averageColor(cropped!)
        // (red + green + blue + white) / 4 per channel, integer division:
        // R=(255+0+0+255)/4=127, G=(0+255+0+255)/4=127, B=(0+0+255+255)/4=127.
        XCTAssertEqual(r, 127); XCTAssertEqual(g, 127); XCTAssertEqual(b, 127)
    }

    func testExportPNGWithCropPixelRectWritesOnlyTheCroppedRegion() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url = tempURL(ext: "png")
        defer { cleanup(url) }

        let full = engine.canvasSize
        let cropRect = CGRect(x: 0, y: 0, width: full.width / 2, height: full.height / 2)
        try StillExporter.exportPNG(engine: engine, to: url, cropPixelRect: cropRect)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image  = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("Could not read back exported PNG")
        }
        XCTAssertEqual(image.width, Int(cropRect.width))
        XCTAssertEqual(image.height, Int(cropRect.height))
    }
}

// MARK: - StillExporter — JPEG tests

final class StillExporterJPEGTests: XCTestCase {

    func testExportJPEGCreatesFile() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url    = tempURL(ext: "jpg")
        defer { cleanup(url) }

        try StillExporter.exportJPEG(engine: engine, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportJPEGDimensions() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let url    = tempURL(ext: "jpg")
        defer { cleanup(url) }

        try StillExporter.exportJPEG(engine: engine, to: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image  = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Could not read back exported JPEG")
            return
        }
        XCTAssertEqual(image.width,  1080)
        XCTAssertEqual(image.height, 1080)
    }
}

// MARK: - VideoExporter tests

final class VideoExporterTests: XCTestCase {

    // MARK: File existence and size

    func testExport30FramesCreatesFile() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "export should create a .mov file")
    }

    func testExportFileIsNonEmpty() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    // MARK: Settings.totalFrames

    func testTotalFramesAt30fps1s() {
        let s = VideoExporter.Settings(fps: 30, endFrame: 30,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 30)
    }

    func testTotalFramesAt24fps3s() {
        let s = VideoExporter.Settings(fps: 24, endFrame: 72,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 72)
    }

    func testTotalFramesMinimumIsOne() {
        let s = VideoExporter.Settings(fps: 30, endFrame: 0,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 1)
    }

    // MARK: Engine frame count after export

    /// `VideoExporter.export` steps the engine with `dt = 1/settings.fps` per frame;
    /// `Engine.update` converts `dt` to project-frame units via the project's own
    /// `targetFPS`. "N video frames == N project frames" only holds when the export
    /// fps matches the project's fps, so `settings.fps` is set from the engine's own
    /// config here rather than a hardcoded 30 (Test_052 defaults to targetFPS 24).
    func testEngineAdvancedByTotalFrames() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let fps      = Int(engine.globalConfig.targetFPS)
        let settings = VideoExporter.Settings(fps: fps, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        // export drives engine.update 30 times, matching the project's own fps.
        XCTAssertEqual(engine.currentFrame, 30,
                       "export should have advanced the engine by totalFrames")
    }

    // MARK: Progress callback

    func testProgressCallbackCalledOncePerFrame() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        var callCount = 0
        let settings  = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings) { _ in
            callCount += 1
        }

        XCTAssertEqual(callCount, 30,
                       "progress callback should be called once per frame (30 at 30fps/1s)")
    }

    func testProgressFinalValueIsOne() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        var lastProgress = 0.0
        let settings     = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings) { p in
            lastProgress = p
        }

        XCTAssertEqual(lastProgress, 1.0, accuracy: 1e-9,
                       "final progress value should be exactly 1.0")
    }

    func testProgressValuesAreMonotonicallyIncreasing() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        var values   = [Double]()
        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings) { p in
            values.append(p)
        }

        for i in 1..<values.count {
            XCTAssertGreaterThan(values[i], values[i - 1],
                                 "progress values must be strictly increasing")
        }
    }

    // MARK: AVAsset metadata

    func testExportedVideoHasApproximatelyCorrectDuration() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let asset    = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        // Allow ±2 frames worth of tolerance for container rounding.
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 2.0 / 30.0,
                       "exported duration should be approximately 1 second")
    }

    func testExportedVideoHasVideoTrack() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let asset  = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "exported file should have at least one video track")
    }

    func testExportedVideoDimensions() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let asset    = AVURLAsset(url: url)
        let tracks   = try await asset.loadTracks(withMediaType: .video)
        let track    = try XCTUnwrap(tracks.first)
        let size     = try await track.load(.naturalSize)

        XCTAssertEqual(size.width,  1080, accuracy: 1)
        XCTAssertEqual(size.height, 1080, accuracy: 1)
    }

    // MARK: Pre-flight resolution check

    /// Canvas size is `(width, height) × qualityMultiple`; a modest base canvas at a
    /// high Quality setting can exceed H.264's hardware encoder limit even though the
    /// export sheet's "Size" field never shows the inflated number. Without a pre-flight
    /// check this fails deep inside VideoToolbox with an undocumented OSStatus and no
    /// indication that Quality is the cause — this test locks in the guard that catches
    /// it before the asset writer is ever touched.
    func testExportThrowsSetupFailedWhenResolutionExceedsH264Limit() async throws {
        let tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoomExportResTest_\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixtureDir052, to: tempProjectDir)
        defer { try? FileManager.default.removeItem(at: tempProjectDir) }

        // Test_052's base canvas is 1080×1080; QualityMultiple 5 → 5400×5400,
        // which exceeds H.264's 4096px-per-side limit.
        let configURL = tempProjectDir.appendingPathComponent("configuration/global_config.xml")
        let xml = try String(contentsOf: configURL, encoding: .utf8)
            .replacingOccurrences(of: "<QualityMultiple>1</QualityMultiple>",
                                   with: "<QualityMultiple>5</QualityMultiple>")
        try xml.write(to: configURL, atomically: true, encoding: .utf8)

        let engine   = try Engine(projectDirectory: tempProjectDir)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, endFrame: 5, codec: .h264, outputURL: url)

        do {
            try await exporter.export(engine: engine, settings: settings)
            XCTFail("expected VideoExporterError.setupFailed for a resolution exceeding H.264's limit")
        } catch let error as VideoExporterError {
            guard case .setupFailed(let message) = error else {
                XCTFail("expected .setupFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("5400"), "message should name the actual (post-Quality) resolution: \(message)")
            XCTAssertTrue(message.contains("Quality"), "message should point at the Quality multiplier as the likely cause: \(message)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "no output file should be left behind when the pre-flight check rejects the export")
    }

    // MARK: Overwrite existing file

    func testExportOverwritesExistingFile() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        // Write a placeholder first.
        try "placeholder".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let settings = VideoExporter.Settings(fps: 30, endFrame: 30, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        // Verify the file is now a valid video (much larger than the placeholder).
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000,
                             "export should have replaced the placeholder with a real video")
    }
}
