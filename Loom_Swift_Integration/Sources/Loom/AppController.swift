import Foundation
import LoomEngine

@MainActor
final class AppController: ObservableObject, @unchecked Sendable {

    // MARK: - Published: engine + project

    @Published private(set) var engine:         Engine?
    @Published private(set) var projectConfig:  ProjectConfig?
    @Published private(set) var projectURL:     URL?
    @Published private(set) var loadError:      String?
    @Published private(set) var recentProjects: [URL]         = []
    @Published private(set) var playbackState:  PlaybackState = .playing

    // MARK: - Published: navigation

    @Published var selectedTab: AppTab = .global

    // MARK: - Published: per-tab selection

    @Published var selectedGeometryKey:           String? = nil
    @Published var selectedSubdivisionIndex:      Int?    = nil
    @Published var selectedSubdivisionParamIndex: Int?    = nil   // within selected set
    @Published var selectedSpriteID:              String? = nil
    @Published var selectedRendererIndex:         Int?    = nil
    @Published var selectedRendererItemIndex:     Int?    = nil   // within selected set

    // MARK: - Published: export

    @Published var isExporting:         Bool   = false
    @Published var exportProgress:      Double = 0
    @Published var exportError:         String?
    @Published var showingExportSheet:  Bool   = false

    // MARK: - Constants

    private static let recentKey = "li.recentProjects"
    private static let maxRecent = 10

    static var defaultProjectsDirectory: URL {
        let candidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loom_projects")
        return FileManager.default.fileExists(atPath: candidate.path)
            ? candidate
            : FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Private

    private var sentinelTimer:    Timer?
    private var pausedBySentinel: Bool = false

    // MARK: - Init

    init() {
        loadRecentProjectsFromDefaults()
        openFromCommandLineIfPresent()
    }

    // MARK: - Config mutation (parameter editor)

    /// Mutate the in-memory `projectConfig` and auto-save to `project_config.json`.
    ///
    /// The engine does NOT reload automatically; the saved JSON is picked up on the
    /// next engine reload (manual or via `.reload` sentinel).
    func updateProjectConfig(_ fn: (inout ProjectConfig) -> Void) {
        guard var config = projectConfig else { return }
        fn(&config)
        projectConfig = config
        if let url = projectURL {
            try? ProjectLoader.save(config, to: url)
        }
    }

    // MARK: - Project management

    func open(projectDirectory: URL) {
        projectURL = projectDirectory
        loadError  = nil
        loadEngine(from: projectDirectory)
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
        addToRecent(projectDirectory)
        startSentinelTimer()
        clearSelections()
    }

    func reload() {
        guard let url = projectURL else { return }
        loadError = nil
        loadEngine(from: url)
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
    }

    // MARK: - Playback

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

    // MARK: - Renders directories

    func animationRendersDirectory() -> URL? { existingRendersDir(["animation", "animations"]) }
    func stillRendersDirectory()     -> URL? { existingRendersDir(["still", "stills"]) }

    // MARK: - Recent projects

    func removeFromRecent(_ url: URL) {
        recentProjects.removeAll { $0 == url }
        persistRecentProjects()
    }

    // MARK: - Private: loading

    private func loadEngine(from url: URL) {
        do {
            engine        = try Engine(projectDirectory: url)
            projectConfig = try? ProjectLoader.load(projectDirectory: url)
            loadError     = nil
        } catch {
            engine        = nil
            projectConfig = nil
            loadError     = error.localizedDescription
        }
    }

    private func clearSelections() {
        selectedGeometryKey           = nil
        selectedSubdivisionIndex      = nil
        selectedSubdivisionParamIndex = nil
        selectedSpriteID              = nil
        selectedRendererIndex         = nil
        selectedRendererItemIndex     = nil
    }

    // MARK: - Private: renders dir

    private func existingRendersDir(_ candidates: [String]) -> URL? {
        guard let base = projectURL else { return nil }
        let rendersBase = base.appendingPathComponent("renders")
        for name in candidates {
            let dir = rendersBase.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        if FileManager.default.fileExists(atPath: rendersBase.path) { return rendersBase }
        return base
    }

    // MARK: - Private: recent projects

    private func addToRecent(_ url: URL) {
        var list = recentProjects.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > Self.maxRecent { list = Array(list.prefix(Self.maxRecent)) }
        recentProjects = list
        persistRecentProjects()
    }

    private func persistRecentProjects() {
        UserDefaults.standard.set(recentProjects.map { $0.path }, forKey: Self.recentKey)
    }

    private func loadRecentProjectsFromDefaults() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        recentProjects = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func openFromCommandLineIfPresent() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--project"), idx + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[idx + 1])
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        open(projectDirectory: url)
    }

    // MARK: - Private: sentinel timer (interim — supports bezier_py .reload)

    private func startSentinelTimer() {
        sentinelTimer?.invalidate()
        sentinelTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSentinelFiles() }
        }
    }

    private func checkSentinelFiles() {
        guard let dir = projectURL else { return }
        let fm = FileManager.default

        let reloadURL = dir.appendingPathComponent(".reload")
        if fm.fileExists(atPath: reloadURL.path) {
            try? fm.removeItem(at: reloadURL)
            reload()
        }

        let pauseURL   = dir.appendingPathComponent(".pause")
        let shouldPause = fm.fileExists(atPath: pauseURL.path)
        if shouldPause && playbackState == .playing {
            pausedBySentinel = true
            playbackState    = .paused
        } else if !shouldPause && playbackState == .paused && pausedBySentinel {
            pausedBySentinel = false
            playbackState    = .playing
        }

        let stillURL = dir.appendingPathComponent(".capture_still")
        if fm.fileExists(atPath: stillURL.path) {
            try? fm.removeItem(at: stillURL)
            saveSentinelStill()
        }

        let videoURL = dir.appendingPathComponent(".capture_video")
        if fm.fileExists(atPath: videoURL.path) {
            try? fm.removeItem(at: videoURL)
            showingExportSheet = true
        }
    }

    private func saveSentinelStill() {
        guard let eng = engine, let projURL = projectURL else { return }
        let dir  = stillRendersDirectory() ?? projURL
        let name = eng.globalConfig.name.isEmpty ? projURL.lastPathComponent : eng.globalConfig.name
        let f    = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let url  = dir.appendingPathComponent("\(name)_\(f.string(from: Date())).png")

        if eng.globalConfig.animating {
            guard let exportEngine = try? Engine(projectDirectory: projURL) else {
                try? StillExporter.exportPNG(engine: eng, to: url); return
            }
            let maxFrames = exportEngine.maxAnimationFrames
            if maxFrames > 0 {
                let dt = 1.0 / max(1.0, exportEngine.globalConfig.targetFPS)
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
