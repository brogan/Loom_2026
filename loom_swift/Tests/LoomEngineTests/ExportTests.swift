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

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "export should create a .mov file")
    }

    func testExportFileIsNonEmpty() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    // MARK: Settings.totalFrames

    func testTotalFramesAt30fps1s() {
        let s = VideoExporter.Settings(fps: 30, duration: 1.0,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 30)
    }

    func testTotalFramesAt24fps3s() {
        let s = VideoExporter.Settings(fps: 24, duration: 3.0,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 72)
    }

    func testTotalFramesMinimumIsOne() {
        let s = VideoExporter.Settings(fps: 30, duration: 0.0,
                                       outputURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(s.totalFrames, 1)
    }

    // MARK: Engine frame count after export

    func testEngineAdvancedByTotalFrames() async throws {
        let engine   = try Engine(projectDirectory: fixtureDir052)
        let exporter = VideoExporter()
        let url      = tempURL(ext: "mov")
        defer { cleanup(url) }

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        // export drives engine.update 30 times for 1s at 30fps.
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
        let settings  = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
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
        let settings     = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
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
        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
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

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
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

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
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

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        let asset    = AVURLAsset(url: url)
        let tracks   = try await asset.loadTracks(withMediaType: .video)
        let track    = try XCTUnwrap(tracks.first)
        let size     = try await track.load(.naturalSize)

        XCTAssertEqual(size.width,  1080, accuracy: 1)
        XCTAssertEqual(size.height, 1080, accuracy: 1)
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

        let settings = VideoExporter.Settings(fps: 30, duration: 1.0, outputURL: url)
        try await exporter.export(engine: engine, settings: settings)

        // Verify the file is now a valid video (much larger than the placeholder).
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000,
                             "export should have replaced the placeholder with a real video")
    }
}
