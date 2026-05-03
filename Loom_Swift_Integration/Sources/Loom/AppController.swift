import AppKit
import Foundation
import LoomEngine
import UniformTypeIdentifiers

// MARK: - RenderOutputType

enum RenderOutputType { case still, animation }

@MainActor
final class AppController: ObservableObject, @unchecked Sendable {

    // MARK: - Published: engine + project

    @Published private(set) var engine:             Engine?
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
    @Published var subdivSelectedSpriteID:        String? = nil   // sprite selected in subdivision tab
    @Published var subdivPreviewSetName:          String? = nil   // set currently previewed (may differ from sprite's assigned set)

    // MARK: - Published: export

    @Published var isExporting:             Bool              = false
    @Published var exportProgress:          Double            = 0
    @Published var exportError:             String?
    @Published var showingExportSheet:      Bool              = false
    @Published private(set) var lastRenderOutputType: RenderOutputType? = nil

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

    // Brush editor window — single shared instance, reused across create/edit flows
    var brushEditorWindow: NSWindow? = nil
    var brushEditorState: BrushEditorState? = nil

    // Stamp editor window — RGBA variant, same pattern
    var stampEditorWindow: NSWindow? = nil
    var stampEditorState: StampEditorState? = nil

    private var sentinelTimer:      Timer?
    private var pausedBySentinel:   Bool = false
    private var reloadDebounce:     DispatchWorkItem?
    private var animationCompleted: Bool = false

    // MARK: - Init

    init() {
        loadRecentProjectsFromDefaults()
        openFromCommandLineIfPresent()
    }

    // MARK: - Config mutation (parameter editor)

    /// Mutate the in-memory `projectConfig`, auto-save to `project_config.json`,
    /// and schedule a debounced engine reload so live preview reflects changes.
    func updateProjectConfig(_ fn: (inout ProjectConfig) -> Void) {
        guard var config = projectConfig else { return }
        fn(&config)
        projectConfig = config
        if let url = projectURL {
            try? ProjectLoader.save(config, to: url)
        }
        scheduleEngineReload()
    }

    private func scheduleEngineReload() {
        reloadDebounce?.cancel()
        let wasPlaying = playbackState == .playing
        let work = DispatchWorkItem { [weak self] in
            guard let self, let url = self.projectURL else { return }
            self.loadError          = nil
            self.animationCompleted = false
            self.loadEngine(from: url)
            self.playbackState = wasPlaying ? .playing : .stopped
        }
        reloadDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Project management

    // MARK: - Project creation / open (called from menu and toolbar)

    func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Loom Project"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = "MyProject"
        panel.canCreateDirectories = true
        panel.directoryURL = Self.defaultProjectsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        createProject(at: url)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt       = "Open Project"
        panel.directoryURL = Self.defaultProjectsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(projectDirectory: url)
    }

    private func createProject(at url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try ProjectLoader.save(ProjectConfig(), to: url)
            open(projectDirectory: url)
        } catch {
            loadError = "Could not create project: \(error.localizedDescription)"
        }
    }

    func open(projectDirectory: URL) {
        projectURL         = projectDirectory
        loadError          = nil
        animationCompleted = false
        loadEngine(from: projectDirectory)
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
        addToRecent(projectDirectory)
        startSentinelTimer()
        clearSelections()
    }

    func reload() {
        guard let url = projectURL else { return }
        loadError          = nil
        animationCompleted = false
        loadEngine(from: url)
        playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped
    }

    // MARK: - Playback

    func play() {
        guard engine != nil else { return }
        pausedBySentinel = false
        if animationCompleted {
            animationCompleted = false
            // Transition through .stopped so the view resets the engine and clears
            // the canvas before the new play pass starts.
            playbackState = .stopped
            DispatchQueue.main.async { [weak self] in
                self?.playbackState = .playing
            }
        } else {
            playbackState = .playing
        }
    }

    func pause() {
        guard engine != nil else { return }
        pausedBySentinel   = false
        animationCompleted = false
        playbackState      = .paused
    }

    func stop() {
        guard engine != nil else { return }
        animationCompleted = false
        playbackState      = .stopped
    }

    func animationDidComplete() {
        animationCompleted = true
        // Use .paused so the timer stops but the canvas is preserved for the user to see.
        playbackState      = .paused
    }

    // MARK: - Export coordination

    func beginExport() {
        lastRenderOutputType = .animation
        isExporting          = true
        exportProgress       = 0
        exportError          = nil
    }

    func endExport(error: Error? = nil) {
        exportError = error.map { $0.localizedDescription }
        isExporting = false
    }

    // MARK: - Still export (toolbar button)

    func saveStill() {
        guard let engine = engine else { return }
        let name = engine.globalConfig.name.isEmpty
            ? (projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType.png]
        panel.nameFieldStringValue = "\(name)_\(f.string(from: Date())).png"
        panel.directoryURL         = stillRendersDirectory()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            try? StillExporter.exportPNG(engine: engine, to: url)
            self?.lastRenderOutputType = .still
        }
    }

    // MARK: - Renders directories

    func animationRendersDirectory() -> URL? { existingRendersDir(["animation", "animations"]) }
    func stillRendersDirectory()     -> URL? { existingRendersDir(["still", "stills"]) }

    /// Returns the renders subdirectory for the most recently performed render.
    /// Falls back to whichever subdirectory exists if no render has been done yet.
    func lastUsedRendersDirectory() -> URL? {
        switch lastRenderOutputType {
        case .still:     return stillRendersDirectory()     ?? animationRendersDirectory()
        case .animation: return animationRendersDirectory() ?? stillRendersDirectory()
        case nil:        return animationRendersDirectory() ?? stillRendersDirectory()
        }
    }

    // MARK: - Recent projects

    func removeFromRecent(_ url: URL) {
        recentProjects.removeAll { $0 == url }
        persistRecentProjects()
    }

    // MARK: - Geometry CRUD

    func deleteGeometry(key: String) {
        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let folder  = String(parts[0])
        let name    = String(parts[1])
        updateProjectConfig { [weak self] cfg in
            switch folder {
            case "polygonSets", "regularPolygons":
                if let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == name }) {
                    let def = cfg.polygonConfig.library.polygonSets[idx]
                    if let base = self?.projectURL, !def.filename.isEmpty {
                        let dir = def.folder == "polygonSet" || def.folder.isEmpty ? "polygonSets" : def.folder
                        try? FileManager.default.removeItem(at: base.appendingPathComponent(dir).appendingPathComponent(def.filename))
                    }
                    cfg.polygonConfig.library.polygonSets.remove(at: idx)
                }
            case "curveSets":
                if let idx = cfg.curveConfig.library.curveSets.firstIndex(where: { $0.name == name }) {
                    let def = cfg.curveConfig.library.curveSets[idx]
                    if let base = self?.projectURL, !def.filename.isEmpty {
                        try? FileManager.default.removeItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename))
                    }
                    cfg.curveConfig.library.curveSets.remove(at: idx)
                }
            case "pointSets":
                if let idx = cfg.pointConfig.library.pointSets.firstIndex(where: { $0.name == name }) {
                    let def = cfg.pointConfig.library.pointSets[idx]
                    if let base = self?.projectURL, !def.filename.isEmpty {
                        try? FileManager.default.removeItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename))
                    }
                    cfg.pointConfig.library.pointSets.remove(at: idx)
                }
            default: break
            }
        }
        if selectedGeometryKey == key { selectedGeometryKey = nil }
    }

    func duplicateGeometry(key: String) {
        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let folder  = String(parts[0])
        let name    = String(parts[1])
        updateProjectConfig { [weak self] cfg in
            switch folder {
            case "polygonSets", "regularPolygons":
                guard var def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name }) else { return }
                def.name = "\(name)_copy"
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let dir = def.folder == "polygonSet" || def.folder.isEmpty ? "polygonSets" : def.folder
                    let srcURL = base.appendingPathComponent(dir).appendingPathComponent(def.filename)
                    let newFilename = "\(def.name).xml"
                    try? FileManager.default.copyItem(at: srcURL, to: base.appendingPathComponent(dir).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.polygonConfig.library.polygonSets.append(def)
            case "curveSets":
                guard var def = cfg.curveConfig.library.curveSets.first(where: { $0.name == name }) else { return }
                def.name = "\(name)_copy"
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let newFilename = "\(def.name).xml"
                    try? FileManager.default.copyItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename),
                                                      to: base.appendingPathComponent(def.folder).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.curveConfig.library.curveSets.append(def)
            case "pointSets":
                guard var def = cfg.pointConfig.library.pointSets.first(where: { $0.name == name }) else { return }
                def.name = "\(name)_copy"
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let newFilename = "\(def.name).xml"
                    try? FileManager.default.copyItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename),
                                                      to: base.appendingPathComponent(def.folder).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.pointConfig.library.pointSets.append(def)
            default: break
            }
        }
    }

    func renameGeometry(key: String, to newName: String) {
        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let folder  = String(parts[0])
        let oldName = String(parts[1])
        updateProjectConfig { [weak self] cfg in
            switch folder {
            case "polygonSets", "regularPolygons":
                guard let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == oldName }) else { return }
                var def = cfg.polygonConfig.library.polygonSets[idx]
                def.name = newName
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let dir = def.folder == "polygonSet" || def.folder.isEmpty ? "polygonSets" : def.folder
                    let newFilename = "\(newName).xml"
                    try? FileManager.default.moveItem(at: base.appendingPathComponent(dir).appendingPathComponent(def.filename),
                                                      to: base.appendingPathComponent(dir).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.polygonConfig.library.polygonSets[idx] = def
                cfg.shapeConfig.library.shapeSets = cfg.shapeConfig.library.shapeSets.map { ss in
                    var ss = ss
                    ss.shapes = ss.shapes.map { s in var s = s; if s.polygonSetName == oldName { s.polygonSetName = newName }; return s }
                    return ss
                }
            case "curveSets":
                guard let idx = cfg.curveConfig.library.curveSets.firstIndex(where: { $0.name == oldName }) else { return }
                var def = cfg.curveConfig.library.curveSets[idx]
                def.name = newName
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let newFilename = "\(newName).xml"
                    try? FileManager.default.moveItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename),
                                                      to: base.appendingPathComponent(def.folder).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.curveConfig.library.curveSets[idx] = def
                cfg.shapeConfig.library.shapeSets = cfg.shapeConfig.library.shapeSets.map { ss in
                    var ss = ss
                    ss.shapes = ss.shapes.map { s in var s = s; if s.openCurveSetName == oldName { s.openCurveSetName = newName }; return s }
                    return ss
                }
            case "pointSets":
                guard let idx = cfg.pointConfig.library.pointSets.firstIndex(where: { $0.name == oldName }) else { return }
                var def = cfg.pointConfig.library.pointSets[idx]
                def.name = newName
                if let base = self?.projectURL, !def.filename.isEmpty {
                    let newFilename = "\(newName).xml"
                    try? FileManager.default.moveItem(at: base.appendingPathComponent(def.folder).appendingPathComponent(def.filename),
                                                      to: base.appendingPathComponent(def.folder).appendingPathComponent(newFilename))
                    def.filename = newFilename
                }
                cfg.pointConfig.library.pointSets[idx] = def
                cfg.shapeConfig.library.shapeSets = cfg.shapeConfig.library.shapeSets.map { ss in
                    var ss = ss
                    ss.shapes = ss.shapes.map { s in var s = s; if s.pointSetName == oldName { s.pointSetName = newName }; return s }
                    return ss
                }
            default: break
            }
        }
        selectedGeometryKey = "\(folder)/\(newName)"
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
        subdivSelectedSpriteID        = nil
        subdivPreviewSetName          = nil
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
        lastRenderOutputType = .still
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
