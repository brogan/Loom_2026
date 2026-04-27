import Foundation
import LoomEngine

// MARK: - PlaybackState

enum PlaybackState { case playing, paused, stopped }

// MARK: - EngineController

/// Central model object for the Loom application.
///
/// Owns the `Engine`, manages project loading/reloading, watches the project
/// directory for changes written by the Python editor, and coordinates export
/// state so the render surface can pause while a video is being written.
@MainActor
final class EngineController: ObservableObject, @unchecked Sendable {

    // MARK: - Published state

    @Published private(set) var engine:              Engine?
    @Published private(set) var projectURL:          URL?
    @Published private(set) var loadError:           String?
    @Published private(set) var isExporting:         Bool           = false
    @Published          var    exportProgress:       Double         = 0
    @Published          var    exportError:          String?
    @Published private(set) var recentProjects:      [URL]          = []
    @Published private(set) var playbackState:       PlaybackState  = .playing
    /// Set to `true` by the sentinel timer when `.capture_video` is detected;
    /// ContentView observes this to present the ExportSheet.
    @Published          var    requestingExportSheet: Bool           = false

    // MARK: - Constants

    private static let recentProjectsDefaultsKey = "recentProjects"
    private static let maxRecentProjects         = 10

    /// Default directory for the open-project panel.
    /// Falls back to the user's home directory if `~/.loom_projects` doesn't exist.
    static var defaultProjectsDirectory: URL {
        let candidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loom_projects")
        return FileManager.default.fileExists(atPath: candidate.path)
            ? candidate
            : FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Private

    private var sentinelTimer:    Timer?
    /// True only when the `.pause` sentinel file caused the current pause.
    /// Prevents the sentinel timer from overriding a pause initiated by the user.
    private var pausedBySentinel: Bool = false

    // MARK: - Init

    init() {
        loadRecentProjectsFromDefaults()
        openFromCommandLineIfPresent()
    }

    // MARK: - Project management

    func open(projectDirectory: URL) {
        projectURL = projectDirectory
        loadError  = nil
        loadEngine(from: projectDirectory)
        // Respect the project's animating flag: non-animating projects render one
        // frame and stop; animating projects begin playing immediately.
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
        addToRecent(projectDirectory)
        startSentinelTimer()
    }

    func reload() {
        guard let url = projectURL else { return }
        loadError = nil
        loadEngine(from: url)
        // Mirror open(): honour the freshly-loaded animating flag so that
        // toggling animation mode in the editor and reloading takes effect.
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
    }

    // MARK: - Playback controls

    func play() {
        guard engine != nil else { return }
        pausedBySentinel = false
        playbackState    = .playing
    }

    func pause() {
        guard engine != nil else { return }
        pausedBySentinel = false
        playbackState    = .paused
    }

    /// Stop and reset to frame 0.  The `RenderSurfaceNSView` observes the state
    /// change and calls `engine.reset()` + renders one frame to update the display.
    func stop() {
        guard engine != nil else { return }
        playbackState = .stopped
    }

    // MARK: - Export coordination

    func beginExport() {
        isExporting    = true
        exportProgress = 0
        exportError    = nil
    }

    func endExport(error: Error? = nil) {
        exportError = error.map { $0.localizedDescription }
        isExporting = false
    }

    // MARK: - Renders directory helpers

    /// Returns the first existing renders subdirectory matching candidate names,
    /// or `nil` if none exist.  Never creates directories.
    func animationRendersDirectory() -> URL? {
        existingRendersDir(candidates: ["animation", "animations"])
    }

    func stillRendersDirectory() -> URL? {
        existingRendersDir(candidates: ["still", "stills"])
    }

    // MARK: - Recent projects

    func removeFromRecent(_ url: URL) {
        recentProjects.removeAll { $0 == url }
        persistRecentProjects()
    }

    // MARK: - Private helpers

    private func loadEngine(from url: URL) {
        do {
            engine    = try Engine(projectDirectory: url)
            loadError = nil
        } catch {
            engine    = nil
            loadError = error.localizedDescription
        }
    }

    private func existingRendersDir(candidates: [String]) -> URL? {
        guard let base = projectURL else { return nil }
        let rendersBase = base.appendingPathComponent("renders")
        for name in candidates {
            let dir = rendersBase.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        // Fall back to the renders root itself if it exists, else project root.
        if FileManager.default.fileExists(atPath: rendersBase.path) { return rendersBase }
        return base
    }

    private func addToRecent(_ url: URL) {
        var list = recentProjects.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > Self.maxRecentProjects { list = Array(list.prefix(Self.maxRecentProjects)) }
        recentProjects = list
        persistRecentProjects()
    }

    private func persistRecentProjects() {
        UserDefaults.standard.set(
            recentProjects.map { $0.path },
            forKey: Self.recentProjectsDefaultsKey
        )
    }

    private func loadRecentProjectsFromDefaults() {
        let paths = UserDefaults.standard.stringArray(
            forKey: Self.recentProjectsDefaultsKey
        ) ?? []
        recentProjects = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func openFromCommandLineIfPresent() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--project"), idx + 1 < args.count else { return }
        let path = args[idx + 1]
        let url  = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        open(projectDirectory: url)
    }

    /// Poll the project directory every 500 ms for sentinel files written by the
    /// Loom Editor — mirrors Scala's `DrawPanel.checkSentinelFiles()` timer.
    private func startSentinelTimer() {
        sentinelTimer?.invalidate()
        sentinelTimer = Timer.scheduledTimer(withTimeInterval: 0.5,
                                             repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; re-enter the main-actor domain.
            MainActor.assumeIsolated { self?.checkSentinelFiles() }
        }
    }

    private func checkSentinelFiles() {
        guard let dir = projectURL else { return }
        let fm = FileManager.default

        // .reload — delete then reload engine
        let reloadURL = dir.appendingPathComponent(".reload")
        if fm.fileExists(atPath: reloadURL.path) {
            try? fm.removeItem(at: reloadURL)
            reload()
        }

        // .pause — presence means paused; absence means playing.
        // Only the sentinel resumes a sentinel-driven pause; user-initiated
        // pauses are left alone so the Play/Pause button works correctly.
        let pauseURL   = dir.appendingPathComponent(".pause")
        let shouldPause = fm.fileExists(atPath: pauseURL.path)
        if shouldPause && playbackState == .playing {
            pausedBySentinel = true
            playbackState    = .paused
        } else if !shouldPause && playbackState == .paused && pausedBySentinel {
            pausedBySentinel = false
            playbackState    = .playing
        }

        // .capture_still — delete then save a PNG to renders/stills/
        let stillURL = dir.appendingPathComponent(".capture_still")
        if fm.fileExists(atPath: stillURL.path) {
            try? fm.removeItem(at: stillURL)
            saveSentinelStill()
        }

        // .capture_video — delete then ask ContentView to show ExportSheet
        let videoURL = dir.appendingPathComponent(".capture_video")
        if fm.fileExists(atPath: videoURL.path) {
            try? fm.removeItem(at: videoURL)
            requestingExportSheet = true
        }
    }

    private func saveSentinelStill() {
        guard let eng = engine, let projURL = projectURL else { return }
        let dir = stillRendersDirectory() ?? projURL
        let name = eng.globalConfig.name.isEmpty
            ? (projURL.lastPathComponent)
            : eng.globalConfig.name
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let url = dir.appendingPathComponent("\(name)_\(f.string(from: Date())).png")

        if eng.globalConfig.animating {
            // For animated projects, create a fresh engine and run it synchronously
            // to the end of the animation.  This produces a deterministic accumulated
            // still that is independent of canvas size and display-timer speed, so
            // large and small renders look identical after the same number of draw cycles.
            guard let exportEngine = try? Engine(projectDirectory: projURL) else {
                try? StillExporter.exportPNG(engine: eng, to: url)
                return
            }
            let maxFrames = exportEngine.maxAnimationFrames
            if maxFrames > 0 {
                let fps = exportEngine.globalConfig.targetFPS
                let dt  = 1.0 / max(1.0, fps)
                for _ in 0..<maxFrames {
                    exportEngine.update(deltaTime: dt)
                    _ = exportEngine.makeFrame()
                }
            }
            try? StillExporter.exportPNG(engine: exportEngine, to: url)
        } else {
            try? StillExporter.exportPNG(engine: eng, to: url)
        }
    }
}
