import AppKit
import Foundation
import LoomEngine
import UniformTypeIdentifiers

// MARK: - RenderOutputType

enum RenderOutputType { case still, animation }

enum GeometryEditorTool: String {
    case standalonePoints = "Create Points"
    case points = "Points"
    case edges = "Edges"
    case openCurves = "Open Curves"
    case polygons = "Polygons"
    case pointByPoint = "Point By Point"
    case meshExtend = "Mesh Extend"
    case knife = "Knife"
    case freehand = "Freehand"
    case pressureTrace = "Pressure Trace"
    case panView = "Pan View"
    case displacementExtrude = "Extrude (Displacement)"
    case scaleExtrude = "Extrude (Scale)"
}

struct GeometryMeshExtendDraft: Equatable {
    var layerID: EditableGeometryID
    var itemID: EditableGeometryID
    var segmentID: EditableGeometryID
    var isPolygon: Bool
    var startAnchorID: EditableGeometryID
    var controlOutID: EditableGeometryID
    var controlInID: EditableGeometryID
    var endAnchorID: EditableGeometryID
    var start: Vector2D
    var controlOut: Vector2D
    var controlIn: Vector2D
    var end: Vector2D
    var apex: Vector2D
    var confirmedAnchors: [Vector2D] = []
    var activeEdgeStartIndex: Int = 1
    var isPreviewActive: Bool = false
}

struct GeometryKnifeLine: Equatable {
    var start: Vector2D
    var end: Vector2D
}

struct GeometryExtrudeDraft: Equatable {
    enum Mode: Equatable { case displacement, scale }
    var mode: Mode
    var startPoint: Vector2D
    var currentPoint: Vector2D

    var dragDelta: Vector2D { currentPoint - startPoint }

    var scaleFactor: Double {
        let d = currentPoint - startPoint
        // right (+x) and up (−y in editor coords) both increase scale
        let proj = d.x - d.y
        let normalized = proj / 0.25
        let clamped = max(-0.95, min(3.0, normalized))
        return clamped >= 0 ? 1.0 + clamped : max(0.05, 1.0 + clamped)
    }
}

struct GeometryClipboardEntry {
    var polygons: [EditableClosedPolygon]
    var openCurves: [EditableOpenCurve]
    var standalonePoints: [EditableStandalonePoint]
    var centroid: Vector2D
}

enum GeometryTransformPivot: String {
    case localCentre = "Local centre"
    case commonCentre = "Common centre"
    case absoluteCentre = "Absolute centre"
}

enum GeometryEditorGridDetail: String, CaseIterable, Identifiable {
    case quadrants = "Quadrants"
    case standard = "Standard"
    case fine = "Fine"

    var id: String { rawValue }
}

struct GeometryEditorLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var isEditable: Bool

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, isEditable: Bool = true) {
        self.id        = id
        self.name      = name
        self.isVisible = isVisible
        self.isEditable = isEditable
    }
}

enum GeometryEditorSaveState: Equatable {
    case unchanged
    case unsaved
    case saved
}

@MainActor
final class AppController: ObservableObject, @unchecked Sendable {

    // MARK: - Published: engine + project

    @Published private(set) var engine:             Engine?
    @Published private(set) var engineCanvasSize:   CGSize = CGSize(width: 1, height: 1)
    @Published private(set) var projectConfig:  ProjectConfig?
    @Published private(set) var projectURL:     URL?
    @Published private(set) var loadError:      String?
    @Published private(set) var recentProjects: [URL]         = []
    @Published private(set) var playbackState:  PlaybackState = .playing

    // MARK: - Published: navigation

    @Published var selectedTab: AppTab = .global
    @Published var showingGeometryEditorLeaveWarning: Bool = false

    // MARK: - Published: per-tab selection

    @Published var selectedGeometryKey:           String? = nil
    @Published var appStatusMessage:              String  = "Ready"
    @Published var isCollectingRenders:           Bool    = false
    @Published var isGeometryEditorActive:        Bool    = false
    @Published var geometryEditorTool:            GeometryEditorTool = .points
    @Published var geometryEditorDocument:        EditableGeometryDocument? = nil { didSet { refreshGeometryEditorSaveState() } }
    @Published private(set) var geometryEditorIsModified: Bool = false
    @Published private(set) var geometryEditorSaveState: GeometryEditorSaveState = .unchanged
    @Published var geometryEditorLoadError:       String? = nil
    @Published var geometryEditorReloadNonce:     Int     = 0
    @Published var geometryEditorSelection:       EditableGeometrySelection = .empty
    @Published var geometryEditorHistory:         EditableGeometryHistory = EditableGeometryHistory()
    @Published var geometryEditorDraftPoints:     [Vector2D] = [] { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorFreehandPoints:  [Vector2D] = [] { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorFreehandPressures: [Double] = []
    @Published var geometryEditorFreehandDetail:  Double = 0.2
    @Published var geometryEditorPressureTracePoints: [Vector2D] = [] { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorPressureTracePressures: [Double] = []
    @Published var geometryEditorMeshExtendDraft: GeometryMeshExtendDraft? = nil { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorKnifeLine:       GeometryKnifeLine? = nil
    @Published var geometryEditorKnifeCutsAllVisibleLayers: Bool = false
    @Published var geometryEditorExtrudeDraft:    GeometryExtrudeDraft? = nil { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorClipboard:       GeometryClipboardEntry? = nil
    @Published var geometryEditorLastClickPosition: Vector2D = .zero
    @Published var geometryEditorViewZoom:        Double = 1.0
    @Published var geometryEditorViewCentre:      Vector2D = .zero
    @Published var geometryEditorShowsGrid:       Bool = true
    @Published var geometryEditorShowsControlPoints: Bool = true
    @Published var geometryEditorGridDetail:      GeometryEditorGridDetail = .standard
    @Published var geometryEditorReferenceImage:  NSImage? = nil
    @Published var geometryEditorReferenceImageURL: URL? = nil
    @Published var geometryEditorShowsReferenceImage: Bool = true
    @Published var geometryEditorReferenceImageOpacity: Double = 0.34
    @Published var geometryEditorLayers:          [GeometryEditorLayer] = [GeometryEditorLayer(name: "Layer 1")] { didSet { refreshGeometryEditorSaveState() } }
    @Published var geometryEditorAnchorOnlyEdit:  Bool = false
    @Published var geometryEditorAutoWeld:        Bool = true
    @Published var geometryEditorWeldTolerance:   Double = 0.5
    @Published var geometryEditorAutoWeldSegmentIDs: Set<EditableGeometryID> = []
    @Published var selectedGeometryEditorLayerID: UUID?   = nil
    @Published var selectedSubdivisionIndex:      Int?    = nil
    @Published var selectedSubdivisionParamIndex: Int?    = nil   // within selected set
    @Published var selectedSpriteID:              String? = nil
    @Published var selectedTimelineKF:            TimelineKFSelection? = nil
    @Published var selectedRendererTimelineKF:    RendererTimelineKFSelection? = nil
    @Published var selectedCameraKF:              CameraKFSelection?   = nil
    @Published var currentTimelineFrame:          Int                  = 0
    @Published var loopPlayback:                  Bool                 = false
    // Deduplicated: only fires objectWillChange when the value actually changes,
    // preventing spurious re-renders on every hover event.
    private var _hoverHelpText: String = ""
    var hoverHelpText: String {
        get { _hoverHelpText }
        set {
            guard newValue != _hoverHelpText else { return }
            objectWillChange.send()
            _hoverHelpText = newValue
        }
    }
    @Published var showScrubBar:                  Bool                 = false
    @Published var selectedRendererIndex:         Int?    = nil
    @Published var selectedRendererItemIndex:     Int?    = nil   // within selected set
    @Published var subdivSelectedSpriteID:        String? = nil   // sprite selected in subdivision tab
    @Published var subdivPreviewSetName:          String? = nil   // set currently previewed (may differ from sprite's assigned set)
    @Published var renderingSelectedSpriteID:     String? = nil   // sprite selected in rendering tab
    @Published var renderingPreviewSetName:       String? = nil   // renderer set currently previewed (may differ from sprite's assigned set)

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

    private var sentinelTimer:         Timer?
    private var pausedBySentinel:      Bool  = false
    private var isAutoRelinking:       Bool  = false
    private var lastAutoRelinkCheck:   Date  = .distantPast
    private var reloadDebounce:     DispatchWorkItem?
    private var configCommitItem:   DispatchWorkItem?
    private let configSaveQueue = DispatchQueue(label: "loom.config.save", qos: .utility)
    private var animationCompleted: Bool = false
    private var geometryTransformGestureBase: EditableGeometrySnapshot?
    private var geometryEditorPendingAutoWeldPairs: [(EditableGeometryID, EditableGeometryID)] = []
    private var geometryEditorCleanFingerprint: String?
    private var geometryEditorCleanKey: String?
    private var geometryEditorHasSavedCleanState: Bool = false
    private var pendingGeometryEditorLeaveTab: AppTab?

    private struct GeometrySegmentReference {
        var layerIndex: Int
        var isPolygon: Bool
        var itemIndex: Int
        var segmentIndex: Int
        var layerID: EditableGeometryID
        var itemID: EditableGeometryID
        var segment: EditableCubicSegment
    }

    private struct GeometryPointReference {
        var id: EditableGeometryID
        var position: Vector2D
    }

    private struct GeometryWeldThresholds {
        var midpointDistance: Double
        var endpointPairDistance: Double
        var minimumDirectionDot: Double
    }

    private struct GeometrySegmentEndpoints {
        var start: Vector2D
        var end: Vector2D
    }

    private struct GeometryKnifeIntersection {
        var segmentIndex: Int
        var t: Double
        var point: Vector2D

        var globalT: Double { Double(segmentIndex) + t }
    }

    private struct GeometryWeldPointSnapshot {
        var id: EditableGeometryID
        var position: Vector2D
    }

    enum GeometryEditorCleanSource {
        case loaded
        case saved
    }

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
        projectConfig = config          // immediate: fires @Published for UI reactivity
        scheduleConfigCommit(config)    // debounced save + reload
    }

    func updateCustomAlgorithm(_ alg: CustomSubdivisionAlgorithm, setIdx: Int, paramIdx: Int) {
        updateProjectConfig { cfg in
            guard setIdx  < cfg.subdivisionConfig.paramsSets.count,
                  paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count
            else { return }
            cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].customAlgorithm = alg
        }
    }

    /// Returns the editable layer names from the polygon file backing the given sprite.
    /// Empty when the file is XML, not found, or has only one (unnamed) layer.
    func morphLayerNames(setIdx: Int, spriteIdx: Int) -> [String] {
        guard let cfg = projectConfig,
              let projectURL,
              let sprite  = cfg.spriteConfig.library.spriteSets[safe: setIdx]?.sprites[safe: spriteIdx],
              let shapeDef = cfg.shapeConfig.library.shapeSets
                  .first(where: { $0.name == sprite.shapeSetName })?
                  .shapes.first(where: { $0.name == sprite.shapeName }),
              shapeDef.sourceType == .polygonSet,
              let polyDef = cfg.polygonConfig.library.polygonSets
                  .first(where: { $0.name == shapeDef.polygonSetName }),
              polyDef.filename.lowercased().hasSuffix(".json")
        else { return [] }
        let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
            ? "polygonSets" : polyDef.folder
        let url = projectURL.appendingPathComponent(folder).appendingPathComponent(polyDef.filename)
        guard let doc = try? EditableGeometryJSONLoader.load(url: url) else { return [] }
        return doc.layers.compactMap { $0.name.isEmpty ? nil : $0.name }
    }

    func requestTabSelection(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        if selectedTab == .geometry,
           isGeometryEditorActive,
           geometryEditorRequiresLeaveWarning {
            pendingGeometryEditorLeaveTab = tab
            showingGeometryEditorLeaveWarning = true
            return
        }
        selectedTab = tab
    }

    func requestExitGeometryEditor() {
        if geometryEditorRequiresLeaveWarning {
            pendingGeometryEditorLeaveTab = nil
            showingGeometryEditorLeaveWarning = true
        } else {
            exitGeometryEditor()
        }
    }

    var geometryEditorLeaveWarningTitle: String {
        geometryEditorDocumentIsPersisted ? "Unsaved Geometry Changes" : "Geometry Not Saved"
    }

    var geometryEditorLeaveWarningMessage: String {
        if geometryEditorDocumentIsPersisted {
            return "\"\(currentPolygonSetName ?? "Geometry")\" has changes that have not been saved."
        }
        return "This geometry has not been saved yet. Save it before leaving, or discard your work."
    }

    func saveAndContinueAfterGeometryEditorWarning() {
        if saveGeometryEditorDocument(named: "") {
            continueAfterGeometryEditorWarning(exitEditor: true)
        }
    }

    func discardAndContinueAfterGeometryEditorWarning() {
        continueAfterGeometryEditorWarning(exitEditor: true)
    }

    func cancelGeometryEditorLeaveWarning() {
        pendingGeometryEditorLeaveTab = nil
        showingGeometryEditorLeaveWarning = false
    }

    private func continueAfterGeometryEditorWarning(exitEditor: Bool) {
        let destination = pendingGeometryEditorLeaveTab
        pendingGeometryEditorLeaveTab = nil
        showingGeometryEditorLeaveWarning = false
        if exitEditor || destination != nil {
            exitGeometryEditor()
        }
        if let destination {
            selectedTab = destination
        }
    }

    /// Writes config to disk on a background queue then rebuilds the engine on the main queue.
    /// Immediately flush any pending debounced save to disk. Does not reload the engine.
    func saveNow() {
        guard let url = projectURL, let config = projectConfig else { return }
        configCommitItem?.cancel()
        configCommitItem = nil
        configSaveQueue.async {
            try? ProjectLoader.save(config, to: url)
        }
    }

    /// Debounced so rapid slider events coalesce into one save+reload cycle.
    private func scheduleConfigCommit(_ config: ProjectConfig) {
        configCommitItem?.cancel()
        reloadDebounce?.cancel()
        guard let url = projectURL else { return }
        let wasPlaying = playbackState == .playing
        let item = DispatchWorkItem { [weak self] in
            try? ProjectLoader.save(config, to: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.loadError          = nil
                self.animationCompleted = false
                self.loadEngine(from: url)
                self.playbackState = wasPlaying ? .playing : .stopped
            }
        }
        configCommitItem = item
        configSaveQueue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    // MARK: - Geometry editor shell

    // MARK: - Morph target lock

    /// True when the currently open polygon set is designated as a morph target source.
    var isCurrentGeometryMorphTargetLocked: Bool {
        guard let geoName = currentPolygonSetName else { return false }
        return projectConfig?.polygonConfig.library.polygonSets
            .first(where: { $0.name == geoName })?.isMorphTarget ?? false
    }

    func toggleCurrentGeometryMorphTargetLock() {
        guard let geoName = currentPolygonSetName else { return }
        updateProjectConfig { cfg in
            guard let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == geoName })
            else { return }
            cfg.polygonConfig.library.polygonSets[idx].isMorphTarget.toggle()
        }
    }

    private var currentPolygonSetName: String? {
        guard let key = selectedGeometryKey, key.hasPrefix("polygonSets/") else { return nil }
        return String(key.dropFirst("polygonSets/".count))
    }

    /// True when the current polygon set has already been written to disk at least once.
    var geometryEditorDocumentIsPersisted: Bool {
        guard let name = currentPolygonSetName else { return false }
        return !(projectConfig?.polygonConfig.library.polygonSets
            .first(where: { $0.name == name })?.filename.isEmpty ?? true)
    }

    func enterGeometryEditor() {
        ensureGeometryEditorLayerSelection()
        isGeometryEditorActive = true
    }

    func exitGeometryEditor() {
        isGeometryEditorActive = false
        geometryEditorTool = .points
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        cancelGeometryExtrudeDraft()
    }

    func ensureGeometryEditorLayerSelection() {
        if geometryEditorLayers.isEmpty {
            geometryEditorLayers = [GeometryEditorLayer(name: "Layer 1")]
        }
        if selectedGeometryEditorLayerID == nil ||
            !geometryEditorLayers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            selectedGeometryEditorLayerID = geometryEditorLayers.first?.id
        }
        if var document = geometryEditorDocument {
            document.ensureActiveLayer()
            if let selectedGeometryEditorLayerID,
               document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
                document.activeLayerID = selectedGeometryEditorLayerID
            } else {
                selectedGeometryEditorLayerID = document.activeLayerID
            }
            geometryEditorDocument = document
        }
    }

    func syncGeometryEditorLayers(from layers: [EditableGeometryLayer]) {
        guard !layers.isEmpty else {
            ensureGeometryEditorLayerSelection()
            return
        }
        geometryEditorLayers = layers.map { layer in
            GeometryEditorLayer(
                id: layer.id,
                name: layer.name,
                isVisible: layer.isVisible,
                isEditable: layer.isEditable
            )
        }
        ensureGeometryEditorLayerSelection()
    }

    func selectGeometryEditorLayer(id: UUID?) {
        selectedGeometryEditorLayerID = id
        if geometryEditorSelection.layerID != id {
            geometryEditorSelection = .empty
        }
        guard let id,
              var document = geometryEditorDocument,
              document.layers.contains(where: { $0.id == id })
        else { return }
        document.activeLayerID = id
        geometryEditorDocument = document
    }

    func focusGeometryEditorLayer(id: UUID?) {
        selectedGeometryEditorLayerID = id
        if geometryEditorSelection.layerID != id {
            geometryEditorSelection = .empty
        }
        guard let id,
              var document = geometryEditorDocument,
              document.layers.contains(where: { $0.id == id })
        else { return }
        document.activeLayerID = id
        for index in document.layers.indices {
            document.layers[index].isEditable = document.layers[index].id == id
        }
        geometryEditorDocument = document
        syncGeometryEditorLayers(from: document.layers)
        pruneGeometryEditorSelection(in: document)
    }

    func setGeometryEditorDocument(
        _ document: EditableGeometryDocument?,
        loadError: String? = nil,
        resetHistory: Bool = false,
        cleanSource: GeometryEditorCleanSource? = nil
    ) {
        var prunedDocument = document
        prunedDocument?.pruneWeldGroups()
        geometryEditorDocument = prunedDocument
        geometryEditorLoadError = loadError
        if let loadError {
            LoomLogger.warning("Geometry editor load error: \(loadError)")
        }
        if resetHistory {
            geometryEditorHistory = EditableGeometryHistory()
        }
        if let document = prunedDocument {
            syncGeometryEditorLayers(from: document.layers)
            pruneGeometryEditorSelection(in: document)
        } else {
            geometryEditorSelection = .empty
            geometryEditorHistory = EditableGeometryHistory()
        }
        if let cleanSource {
            establishGeometryEditorCleanBaseline(source: cleanSource)
        } else {
            refreshGeometryEditorSaveState()
        }
    }

    private var geometryEditorRequiresLeaveWarning: Bool {
        geometryEditorSaveState == .unsaved
    }

    private var geometryEditorHasUnsavedDraft: Bool {
        !geometryEditorDraftPoints.isEmpty ||
        !geometryEditorFreehandPoints.isEmpty ||
        !geometryEditorPressureTracePoints.isEmpty ||
        geometryEditorMeshExtendDraft != nil ||
        geometryEditorExtrudeDraft != nil
    }

    private func establishGeometryEditorCleanBaseline(source: GeometryEditorCleanSource) {
        let previousKey = geometryEditorCleanKey
        let previousHadSaved = geometryEditorHasSavedCleanState
        geometryEditorCleanFingerprint = geometryEditorFingerprint()
        geometryEditorCleanKey = selectedGeometryKey
        geometryEditorHasSavedCleanState = source == .saved || (previousHadSaved && previousKey == selectedGeometryKey)
        refreshGeometryEditorSaveState()
    }

    private func refreshGeometryEditorSaveState() {
        guard geometryEditorDocument != nil else {
            geometryEditorCleanFingerprint = nil
            geometryEditorCleanKey = nil
            geometryEditorHasSavedCleanState = false
            geometryEditorIsModified = false
            geometryEditorSaveState = .unchanged
            return
        }

        let currentFingerprint = geometryEditorFingerprint()
        let hasUnsavedChanges = geometryEditorHasUnsavedDraft ||
            currentFingerprint != geometryEditorCleanFingerprint ||
            selectedGeometryKey != geometryEditorCleanKey
        geometryEditorIsModified = hasUnsavedChanges
        if hasUnsavedChanges {
            geometryEditorSaveState = .unsaved
        } else {
            geometryEditorSaveState = geometryEditorHasSavedCleanState ? .saved : .unchanged
        }
    }

    private func geometryEditorFingerprint() -> String? {
        guard var document = geometryEditorDocument else { return nil }
        applyLayerPanelState(to: &document)
        document.pruneWeldGroups()
        document.activeLayerID = nil
        guard let data = try? EditableGeometryJSONLoader.encode(document) else { return nil }
        return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    }

    func toggleSelectedGeometryEditorLayerVisibility() {
        toggleGeometryEditorLayerVisibility(id: selectedGeometryEditorLayerID)
    }

    func toggleGeometryEditorLayerVisibility(id: UUID?) {
        guard var document = geometryEditorDocumentForLayerMutation(),
              let id,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers[index].isVisible.toggle()
        if !document.layers[index].isVisible, geometryEditorSelection.layerID == id {
            geometryEditorSelection = .empty
        }
        setGeometryEditorDocument(document)
    }

    func toggleGeometryEditorLayerEditability(id: UUID?) {
        guard var document = geometryEditorDocumentForLayerMutation(),
              let id,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers[index].isEditable.toggle()
        if document.layers[index].isEditable {
            document.layers[index].isVisible = true
        }
        if !document.layers[index].isEditable, geometryEditorSelection.layerID == id {
            geometryEditorSelection = .empty
        }
        setGeometryEditorDocument(document)
    }

    func addGeometryEditorLayer() {
        var document = geometryEditorDocumentForLayerMutation() ?? EditableGeometryDocument(name: "Untitled Polygon")
        document.ensureActiveLayer()
        let layer = EditableGeometryLayer(name: "Layer \(document.layers.count + 1)")
        recordGeometryEditorUndoSnapshot()
        for index in document.layers.indices {
            document.layers[index].isEditable = false
        }
        document.layers.append(layer)
        document.activeLayerID = layer.id
        selectedGeometryEditorLayerID = layer.id
        setGeometryEditorDocument(document)
    }

    func importBakedGeometryAsLayer() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes    = true
        panel.allowedContentTypes     = [.json, .xml]
        panel.title  = "Import Baked Geometry as Layer"
        panel.prompt = "Import"
        if let projURL = projectURL {
            panel.directoryURL = projURL.appendingPathComponent("polygonSets")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let stem = url.deletingPathExtension().lastPathComponent
        do {
            let polygons: [Polygon2D]
            if url.pathExtension.lowercased() == "json" {
                polygons = try EditableGeometryJSONLoader.load(url: url).runtimePolygons(includeHiddenLayers: true)
            } else {
                polygons = try XMLPolygonLoader.load(url: url)
            }
            guard !polygons.isEmpty else { return }

            var document = geometryEditorDocumentForLayerMutation() ?? EditableGeometryDocument(name: stem)
            document.ensureActiveLayer()
            recordGeometryEditorUndoSnapshot()
            for index in document.layers.indices {
                document.layers[index].isEditable = false
            }
            let layerID = try document.appendLayer(from: polygons, named: stem)
            document.activeLayerID       = layerID
            selectedGeometryEditorLayerID = layerID
            setGeometryEditorDocument(document)
        } catch {
            let alert = NSAlert()
            alert.messageText     = "Import Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle      = .warning
            alert.runModal()
        }
    }

    func renameSelectedGeometryEditorLayer(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var document = geometryEditorDocumentForLayerMutation(),
              let id = selectedGeometryEditorLayerID,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers[index].name = trimmed
        setGeometryEditorDocument(document)
    }

    func duplicateSelectedGeometryEditorLayer() {
        guard var document = geometryEditorDocumentForLayerMutation(),
              let id = selectedGeometryEditorLayerID,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        let copy = document.layers[index].duplicated(name: "\(document.layers[index].name) Copy")
        recordGeometryEditorUndoSnapshot()
        document.layers.insert(copy, at: index + 1)
        document.activeLayerID = copy.id
        selectedGeometryEditorLayerID = copy.id
        geometryEditorSelection = .empty
        setGeometryEditorDocument(document)
    }

    func deleteSelectedGeometryEditorLayer() {
        guard var document = geometryEditorDocumentForLayerMutation(),
              document.layers.count > 1,
              let id = selectedGeometryEditorLayerID,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers.remove(at: index)
        let nextLayer = document.layers[min(index, document.layers.count - 1)]
        document.activeLayerID = nextLayer.id
        selectedGeometryEditorLayerID = nextLayer.id
        if geometryEditorSelection.layerID == id {
            geometryEditorSelection = .empty
        }
        setGeometryEditorDocument(document)
    }

    func moveSelectedGeometryEditorLayer(up: Bool) {
        guard var document = geometryEditorDocumentForLayerMutation(),
              let id = selectedGeometryEditorLayerID,
              let index = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        let target = up ? index - 1 : index + 1
        guard document.layers.indices.contains(target) else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers.swapAt(index, target)
        document.activeLayerID = id
        setGeometryEditorDocument(document)
    }

    func reorderGeometryEditorLayer(id: UUID, toBeforeIndex target: Int) {
        guard var document = geometryEditorDocumentForLayerMutation(),
              let fromIndex = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        guard target != fromIndex && target != fromIndex + 1 else { return }
        recordGeometryEditorUndoSnapshot()
        let layer = document.layers.remove(at: fromIndex)
        let insertAt = fromIndex < target ? target - 1 : target
        document.layers.insert(layer, at: max(0, min(insertAt, document.layers.count)))
        document.activeLayerID = id
        setGeometryEditorDocument(document)
    }

    func startPointByPointGeometryCreation() {
        geometryEditorTool = .pointByPoint
        geometryEditorDraftPoints.removeAll()
        if geometryEditorDocument == nil {
            var document = EditableGeometryDocument(name: "Untitled Polygon")
            document.ensureActiveLayer()
            setGeometryEditorDocument(document, cleanSource: .loaded)
        }
    }

    func startGeometryEditMode(_ tool: GeometryEditorTool) {
        if tool == .pointByPoint {
            startPointByPointGeometryCreation()
            return
        }
        if tool == .freehand {
            startFreehandGeometryCreation()
            return
        }
        if tool == .meshExtend {
            startMeshExtendGeometryCreation()
            return
        }
        if tool == .knife {
            startKnifeGeometryCut()
            return
        }
        if tool == .panView {
            geometryEditorTool = .panView
            geometryEditorDraftPoints.removeAll()
            clearGeometryFreehandStroke()
            clearGeometryPressureTraceStroke()
            cancelGeometryMeshExtendDraft()
            cancelGeometryKnifeLine()
            return
        }
        geometryEditorTool = tool
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        clearGeometryPressureTraceStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        geometryEditorSelection = .empty
    }

    func startStandalonePointGeometryCreation() {
        geometryEditorTool = .standalonePoints
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        if geometryEditorDocument == nil {
            var document = EditableGeometryDocument(name: "Untitled Geometry")
            document.ensureActiveLayer()
            setGeometryEditorDocument(document, cleanSource: .loaded)
        }
    }

    func createStandalonePointGeometry(at position: Vector2D) {
        guard geometryEditorTool == .standalonePoints else { return }
        var document = geometryEditorDocument ?? EditableGeometryDocument(name: "Untitled Geometry")
        document.ensureActiveLayer()
        if let selectedGeometryEditorLayerID,
           document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            document.activeLayerID = selectedGeometryEditorLayerID
        }
        guard let layerID = document.activeLayerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }

        let point = EditableStandalonePoint(
            name: "Point \(document.layers[layerIndex].points.count + 1)",
            position: position
        )
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].points.append(point)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            standalonePointIDs: [point.id],
            pointIDs: [point.id]
        )
        selectedGeometryEditorLayerID = layerID
        setGeometryEditorDocument(document)
        postStatus("Created point")
    }

    func appendGeometryDraftPoint(_ point: Vector2D) {
        guard geometryEditorTool == .pointByPoint else { return }
        geometryEditorDraftPoints.append(point)
    }

    func clearGeometryDraft() {
        geometryEditorDraftPoints.removeAll()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
    }

    func createOvalGeometry() {
        let polygon = EditableClosedPolygon(
            name: "Oval",
            ovalCentre: .zero,
            radiusX: 0.28,
            radiusY: 0.2
        )
        createPolygonInNewGeometryLayer(polygon, baseLayerName: "Oval")
        postStatus("Created oval")
    }

    func createRegularPolygonGeometry(sides: Int = 5) {
        do {
            let polygon = try EditableClosedPolygon(
                name: "Regular Polygon",
                regularPolygonSides: sides,
                centre: .zero,
                radius: 0.28
            )
            createPolygonInNewGeometryLayer(polygon, baseLayerName: "Regular Polygon")
            postStatus("Created \(sides)-sided regular polygon")
        } catch {
            postStatus(error.localizedDescription)
        }
    }

    func startMeshExtendGeometryCreation() {
        geometryEditorTool = .meshExtend
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        if geometryEditorDocument == nil {
            var document = EditableGeometryDocument(name: "Untitled Polygon")
            document.ensureActiveLayer()
            setGeometryEditorDocument(document, cleanSource: .loaded)
        }
    }

    func startKnifeGeometryCut() {
        geometryEditorTool = .knife
        geometryEditorKnifeCutsAllVisibleLayers = false
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
    }

    func beginGeometryKnifeLine(at point: Vector2D) {
        guard geometryEditorTool == .knife else { return }
        geometryEditorKnifeLine = GeometryKnifeLine(start: point, end: point)
    }

    func updateGeometryKnifeLine(to point: Vector2D) {
        guard geometryEditorTool == .knife,
              var line = geometryEditorKnifeLine
        else { return }
        line.end = point
        geometryEditorKnifeLine = line
    }

    func finishGeometryKnifeCut() {
        guard geometryEditorTool == .knife,
              let line = geometryEditorKnifeLine
        else { return }
        defer { cancelGeometryKnifeLine() }
        guard line.start.distance(to: line.end) >= 0.005 else { return }
        performGeometryKnifeCut(from: line.start, to: line.end)
    }

    func cancelGeometryKnifeLine() {
        geometryEditorKnifeLine = nil
    }

    // MARK: - Extrude tools

    func startDisplacementExtrude() {
        geometryEditorTool = .displacementExtrude
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        cancelGeometryExtrudeDraft()
    }

    func startScaleExtrude() {
        geometryEditorTool = .scaleExtrude
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
        cancelGeometryExtrudeDraft()
    }

    func beginGeometryExtrudeDrag(at startPoint: Vector2D) {
        guard geometryEditorTool == .displacementExtrude || geometryEditorTool == .scaleExtrude else { return }
        let mode: GeometryExtrudeDraft.Mode = geometryEditorTool == .displacementExtrude ? .displacement : .scale
        geometryEditorExtrudeDraft = GeometryExtrudeDraft(mode: mode, startPoint: startPoint, currentPoint: startPoint)
    }

    func updateGeometryExtrudeDrag(to point: Vector2D) {
        guard geometryEditorExtrudeDraft != nil else { return }
        geometryEditorExtrudeDraft?.currentPoint = point
    }

    func finishGeometryExtrude() {
        guard let draft = geometryEditorExtrudeDraft else { return }
        defer { cancelGeometryExtrudeDraft() }
        switch draft.mode {
        case .displacement:
            guard draft.dragDelta.length > 0.002 else { return }
            performGeometryDisplacementExtrude(delta: draft.dragDelta)
        case .scale:
            let factor = draft.scaleFactor
            guard abs(factor - 1.0) > 0.01 else { return }
            performGeometryScaleExtrude(factor: factor)
        }
    }

    func cancelGeometryExtrudeDraft() {
        geometryEditorExtrudeDraft = nil
    }

    var canExtrudeSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              selectedGeometryEditorLayerCanEditForUI else { return false }
        return !extrudeSourceSegments(in: document).isEmpty
    }

    func extrudePreviewSegments(in document: EditableGeometryDocument) -> [EditableCubicSegment] {
        extrudeSourceSegments(in: document).map(\.segment)
    }

    func beginGeometryMeshExtend(
        layerID: EditableGeometryID,
        polygonID: EditableGeometryID?,
        openCurveID: EditableGeometryID?,
        segmentID: EditableGeometryID,
        apex: Vector2D
    ) {
        guard geometryEditorTool == .meshExtend,
              let document = geometryEditorDocument,
              layerCanEdit(layerID)
        else { return }
        let matching = editableGeometrySegmentReferences(in: document).first { reference in
            reference.layerID == layerID &&
            reference.segment.id == segmentID &&
            ((reference.isPolygon && polygonID == reference.itemID) ||
             (!reference.isPolygon && openCurveID == reference.itemID))
        }
        guard let reference = matching,
              let start = document.point(id: reference.segment.startAnchorID)?.position,
              let controlOut = document.point(id: reference.segment.controlOutID)?.position,
              let controlIn = document.point(id: reference.segment.controlInID)?.position,
              let end = document.point(id: reference.segment.endAnchorID)?.position
        else { return }

        if reference.isPolygon {
            selectGeometrySegment(
                layerID: layerID,
                polygonID: reference.itemID,
                segmentID: segmentID
            )
        } else {
            selectGeometryOpenCurveSegment(
                layerID: layerID,
                openCurveID: reference.itemID,
                segmentID: segmentID
            )
        }
        geometryEditorMeshExtendDraft = GeometryMeshExtendDraft(
            layerID: layerID,
            itemID: reference.itemID,
            segmentID: segmentID,
            isPolygon: reference.isPolygon,
            startAnchorID: reference.segment.startAnchorID,
            controlOutID: reference.segment.controlOutID,
            controlInID: reference.segment.controlInID,
            endAnchorID: reference.segment.endAnchorID,
            start: start,
            controlOut: controlOut,
            controlIn: controlIn,
            end: end,
            apex: midpoint(start, end)
        )
    }

    func updateGeometryMeshExtendDraft(apex: Vector2D) {
        guard geometryEditorTool == .meshExtend,
              geometryEditorMeshExtendDraft != nil
        else { return }
        geometryEditorMeshExtendDraft?.isPreviewActive = true
        geometryEditorMeshExtendDraft?.apex = apex
    }

    func updateGeometryMeshExtendConfirmedAnchor(index: Int, to position: Vector2D) {
        guard geometryEditorTool == .meshExtend,
              var draft = geometryEditorMeshExtendDraft,
              draft.confirmedAnchors.indices.contains(index)
        else { return }
        draft.confirmedAnchors[index] = position
        draft.isPreviewActive = false
        geometryEditorMeshExtendDraft = draft
    }

    func beginGeometryMeshExtendPreviewDrag(from start: Vector2D, to apex: Vector2D) {
        guard geometryEditorTool == .meshExtend,
              var draft = geometryEditorMeshExtendDraft,
              let activeIndex = nearestMeshExtendCandidateEdgeStartIndex(to: start, in: draft)
        else { return }
        draft.activeEdgeStartIndex = activeIndex
        draft.isPreviewActive = true
        draft.apex = apex
        geometryEditorMeshExtendDraft = draft
    }

    var canContinueGeometryMeshExtend: Bool {
        guard geometryEditorTool == .meshExtend,
              let draft = geometryEditorMeshExtendDraft,
              layerCanEdit(draft.layerID),
              draft.isPreviewActive
        else { return false }
        let edge = meshExtendActiveEdge(for: draft)
        return edge.start.distance(to: edge.end) > 0.000_001 &&
            distanceFromPoint(draft.apex, toSegmentFrom: edge.start, to: edge.end) > 0.004
    }

    var isGeometryMeshExtendPreviewActive: Bool {
        guard geometryEditorTool == .meshExtend,
              let draft = geometryEditorMeshExtendDraft
        else { return false }
        return draft.isPreviewActive
    }

    func continueGeometryMeshExtendDraft() {
        guard canContinueGeometryMeshExtend,
              var draft = geometryEditorMeshExtendDraft
        else { return }
        let insertionIndex = max(0, min(draft.confirmedAnchors.count, draft.activeEdgeStartIndex - 1))
        draft.confirmedAnchors.insert(draft.apex, at: insertionIndex)
        let nextEdge = meshExtendActiveEdge(for: draft)
        draft.apex = midpoint(nextEdge.start, nextEdge.end)
        draft.isPreviewActive = false
        geometryEditorMeshExtendDraft = draft
    }

    func cancelGeometryMeshExtendDraft() {
        geometryEditorMeshExtendDraft = nil
    }

    private func createPolygonInNewGeometryLayer(
        _ polygon: EditableClosedPolygon,
        baseLayerName: String
    ) {
        var document = geometryEditorDocument ?? EditableGeometryDocument(name: "Untitled Polygon")
        document.ensureActiveLayer()
        let layerName = uniqueGeometryLayerName(baseLayerName, in: document)
        var layer = EditableGeometryLayer(name: layerName, polygons: [polygon])
        layer.isVisible = true
        layer.isEditable = true

        recordGeometryEditorUndoSnapshot()
        for index in document.layers.indices {
            document.layers[index].isEditable = false
        }
        document.layers.append(layer)
        document.activeLayerID = layer.id
        selectedGeometryEditorLayerID = layer.id
        geometryEditorTool = .polygons
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        cancelGeometryMeshExtendDraft()
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layer.id,
            polygonIDs: [polygon.id]
        )
        setGeometryEditorDocument(document)
    }

    private func uniqueGeometryLayerName(
        _ baseName: String,
        in document: EditableGeometryDocument
    ) -> String {
        let existing = Set(document.layers.map(\.name))
        if !existing.contains(baseName) { return baseName }
        var index = 2
        while existing.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }

    func startFreehandGeometryCreation() {
        geometryEditorTool = .freehand
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        if geometryEditorDocument == nil {
            var document = EditableGeometryDocument(name: "Untitled Polygon")
            document.ensureActiveLayer()
            setGeometryEditorDocument(document)
        }
    }

    func beginGeometryFreehandStroke(at point: Vector2D, pressure: Double = 1.0) {
        guard geometryEditorTool == .freehand, selectedGeometryEditorLayerCanEdit else { return }
        geometryEditorFreehandPoints = [point]
        geometryEditorFreehandPressures = [normalizedPressure(pressure)]
    }

    func appendGeometryFreehandPoint(_ point: Vector2D, pressure: Double = 1.0) {
        guard geometryEditorTool == .freehand, selectedGeometryEditorLayerCanEdit else { return }
        if let last = geometryEditorFreehandPoints.last,
           last.distance(to: point) < 0.003 {
            return
        }
        geometryEditorFreehandPoints.append(point)
        geometryEditorFreehandPressures.append(normalizedPressure(pressure))
    }

    func finaliseGeometryFreehandStroke() {
        guard geometryEditorTool == .freehand,
              selectedGeometryEditorLayerCanEdit,
              geometryEditorFreehandPoints.count >= 2
        else {
            clearGeometryFreehandStroke()
            return
        }

        var rawPoints = geometryEditorFreehandPoints
        let rawPressures = geometryEditorFreehandPressures
        clearGeometryFreehandStroke()

        let shouldClose = rawPoints.count > 5 &&
            rawPoints.last?.distance(to: rawPoints[0]) ?? .greatestFiniteMagnitude < 0.021
        if shouldClose {
            rawPoints.append(rawPoints[0])
        }

        let threshold = 50.0 - min(max(geometryEditorFreehandDetail, 0), 1) * 49.0
        guard let fitted = FreehandCurveFitter.fit(rawPoints, errorThreshold: threshold),
              fitted.count >= 4
        else { return }

        var document = geometryEditorDocument ?? EditableGeometryDocument(name: "Untitled Polygon")
        document.ensureActiveLayer()
        if let selectedGeometryEditorLayerID,
           document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            document.activeLayerID = selectedGeometryEditorLayerID
        }
        guard let activeLayerID = document.activeLayerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == activeLayerID })
        else { return }

        let segmentCount = max(1, fitted.count / 4)
        let pressureCount = shouldClose ? segmentCount : segmentCount + 1
        let pressures = mappedPressures(rawPressures, count: pressureCount)
        recordGeometryEditorUndoSnapshot()
        let fittedSegments = stride(from: 0, to: fitted.count, by: 4).compactMap { index -> [Vector2D]? in
            guard index + 3 < fitted.count else { return nil }
            return Array(fitted[index...(index + 3)])
        }
        if shouldClose {
            let name = "Freehand Polygon \(document.layers[layerIndex].polygons.count + 1)"
            guard let polygon = editableClosedPolygon(
                name: name,
                segments: fittedSegments,
                pressures: pressures,
                isVisible: true
            ) else { return }
            document.layers[layerIndex].polygons.append(polygon)
            geometryEditorSelection = EditableGeometrySelection(layerID: activeLayerID, polygonIDs: [polygon.id])
        } else {
            let name = "Freehand Curve \(document.layers[layerIndex].openCurves.count + 1)"
            guard let curve = editableOpenCurve(
                name: name,
                segments: fittedSegments,
                pressures: pressures,
                isVisible: true
            ) else { return }
            document.layers[layerIndex].openCurves.append(curve)
            geometryEditorSelection = EditableGeometrySelection(layerID: activeLayerID, openCurveIDs: [curve.id])
        }
        selectedGeometryEditorLayerID = activeLayerID
        setGeometryEditorDocument(document)
        postStatus("Created \(shouldClose ? "freehand polygon" : "freehand curve")")
    }

    func clearGeometryFreehandStroke() {
        geometryEditorFreehandPoints.removeAll()
        geometryEditorFreehandPressures.removeAll()
    }

    private func normalizedPressure(_ pressure: Double) -> Double {
        let value = pressure > 0 ? pressure : 1.0
        return min(max(value, 0.05), 1.0)
    }

    private func mappedPressures(_ rawPressures: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !rawPressures.isEmpty else { return Array(repeating: 1.0, count: count) }
        guard count > 1, rawPressures.count > 1 else { return [normalizedPressure(rawPressures[0])] }
        return (0..<count).map { index in
            let rawIndex = Int(round(Double(index) * Double(rawPressures.count - 1) / Double(count - 1)))
            return normalizedPressure(rawPressures[min(max(rawIndex, 0), rawPressures.count - 1)])
        }
    }

    var canPressureTraceSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        if layer.polygons.contains(where: {
            geometryEditorSelection.polygonIDs.contains($0.id) ||
            $0.segments.contains { geometryEditorSelection.segmentIDs.contains($0.id) } ||
            $0.points.contains { point in geometryEditorSelection.pointIDs.contains(point.id) && point.kind == .anchor }
        }) { return true }
        if layer.openCurves.contains(where: {
            geometryEditorSelection.openCurveIDs.contains($0.id) ||
            $0.segments.contains { geometryEditorSelection.segmentIDs.contains($0.id) } ||
            $0.points.contains { point in geometryEditorSelection.pointIDs.contains(point.id) && point.kind == .anchor }
        }) { return true }
        return layer.points.contains {
            geometryEditorSelection.standalonePointIDs.contains($0.id) ||
            geometryEditorSelection.pointIDs.contains($0.id)
        }
    }

    func startPressureTraceGeometryEdit() {
        guard canPressureTraceSelectedGeometry else {
            postStatus("Select geometry before pressure tracing")
            return
        }
        geometryEditorTool = .pressureTrace
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        clearGeometryPressureTraceStroke()
        cancelGeometryMeshExtendDraft()
        cancelGeometryKnifeLine()
    }

    func beginGeometryPressureTrace(at point: Vector2D, pressure: Double = 1.0) {
        guard geometryEditorTool == .pressureTrace, canPressureTraceSelectedGeometry else { return }
        geometryEditorPressureTracePoints = [point]
        geometryEditorPressureTracePressures = [normalizedPressure(pressure)]
    }

    func appendGeometryPressureTracePoint(_ point: Vector2D, pressure: Double = 1.0) {
        guard geometryEditorTool == .pressureTrace, canPressureTraceSelectedGeometry else { return }
        if let last = geometryEditorPressureTracePoints.last,
           last.distance(to: point) < 0.003 {
            return
        }
        geometryEditorPressureTracePoints.append(point)
        geometryEditorPressureTracePressures.append(normalizedPressure(pressure))
    }

    func finaliseGeometryPressureTrace() {
        guard geometryEditorTool == .pressureTrace,
              canPressureTraceSelectedGeometry,
              geometryEditorPressureTracePoints.count >= 2,
              var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else {
            clearGeometryPressureTraceStroke()
            return
        }

        let tracePoints = geometryEditorPressureTracePoints
        let tracePressures = geometryEditorPressureTracePressures
        clearGeometryPressureTraceStroke()
        recordGeometryEditorUndoSnapshot()

        var changed = false
        let selectedPointIDs = geometryEditorSelection.pointIDs
        let selectedSegmentIDs = geometryEditorSelection.segmentIDs
        for polygonIndex in document.layers[layerIndex].polygons.indices {
            var polygon = document.layers[layerIndex].polygons[polygonIndex]
            let objectSelected = geometryEditorSelection.polygonIDs.contains(polygon.id)
            let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
            let anchorIDs = polygon.segments.map(\.startAnchorID)
            let selectedAnchors = Set(anchorIDs).intersection(selectedPointIDs)
            let selectedSegments = polygon.segments.filter { selectedSegmentIDs.contains($0.id) }
            guard objectSelected || !selectedAnchors.isEmpty || !selectedSegments.isEmpty else { continue }
            var pressures = normalizedPressureValues(polygon.pressures, count: polygon.segments.count)
            for (pressureIndex, anchorID) in anchorIDs.enumerated() {
                let segmentSelected = selectedSegments.contains { segment in
                    segment.startAnchorID == anchorID || segment.endAnchorID == anchorID
                }
                let shouldTraceAnchor = !selectedSegmentIDs.isEmpty
                    ? segmentSelected
                    : (objectSelected || selectedAnchors.contains(anchorID))
                guard shouldTraceAnchor,
                      let anchor = polygon.point(id: anchorID)
                else { continue }
                pressures[pressureIndex] = pressureForTracePoint(anchor.position, tracePoints: tracePoints, tracePressures: tracePressures)
                changed = true
            }
            if objectSelected {
                for segment in polygon.segments {
                    if let profile = pressureProfileForSegment(
                        segment,
                        pointMap: pointMap,
                        tracePoints: tracePoints,
                        tracePressures: tracePressures
                    ) {
                        polygon.setPressureProfile(profile, for: segment.id)
                        changed = true
                    }
                }
            }
            if !selectedSegments.isEmpty {
                for segment in selectedSegments {
                    guard let segmentIndex = polygon.segments.firstIndex(where: { $0.id == segment.id }),
                          let endAnchor = polygon.point(id: segment.endAnchorID)
                    else { continue }
                    let endIndex = (segmentIndex + 1) % max(1, polygon.segments.count)
                    pressures[endIndex] = pressureForTracePoint(endAnchor.position, tracePoints: tracePoints, tracePressures: tracePressures)
                    if let profile = pressureProfileForSegment(
                        segment,
                        pointMap: pointMap,
                        tracePoints: tracePoints,
                        tracePressures: tracePressures
                    ) {
                        polygon.setPressureProfile(profile, for: segment.id)
                    }
                    changed = true
                }
            }
            polygon.pressures = pressures
            document.layers[layerIndex].polygons[polygonIndex] = polygon
        }

        for curveIndex in document.layers[layerIndex].openCurves.indices {
            var curve = document.layers[layerIndex].openCurves[curveIndex]
            let objectSelected = geometryEditorSelection.openCurveIDs.contains(curve.id)
            let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
            var anchorIDs: [EditableGeometryID] = []
            if let first = curve.segments.first?.startAnchorID {
                anchorIDs.append(first)
            }
            anchorIDs.append(contentsOf: curve.segments.map(\.endAnchorID))
            let selectedAnchors = Set(anchorIDs).intersection(selectedPointIDs)
            let selectedSegments = curve.segments.filter { selectedSegmentIDs.contains($0.id) }
            guard objectSelected || !selectedAnchors.isEmpty || !selectedSegments.isEmpty else { continue }
            var pressures = normalizedPressureValues(curve.pressures, count: anchorIDs.count)
            for (pressureIndex, anchorID) in anchorIDs.enumerated() {
                let segmentSelected = selectedSegments.contains { segment in
                    segment.startAnchorID == anchorID || segment.endAnchorID == anchorID
                }
                let shouldTraceAnchor = !selectedSegmentIDs.isEmpty
                    ? segmentSelected
                    : (objectSelected || selectedAnchors.contains(anchorID))
                guard shouldTraceAnchor,
                      let anchor = curve.point(id: anchorID)
                else { continue }
                pressures[pressureIndex] = pressureForTracePoint(anchor.position, tracePoints: tracePoints, tracePressures: tracePressures)
                changed = true
            }
            if objectSelected {
                for segment in curve.segments {
                    if let profile = pressureProfileForSegment(
                        segment,
                        pointMap: pointMap,
                        tracePoints: tracePoints,
                        tracePressures: tracePressures
                    ) {
                        curve.setPressureProfile(profile, for: segment.id)
                        changed = true
                    }
                }
            }
            if !selectedSegments.isEmpty {
                for segment in selectedSegments {
                    if let profile = pressureProfileForSegment(
                        segment,
                        pointMap: pointMap,
                        tracePoints: tracePoints,
                        tracePressures: tracePressures
                    ) {
                        curve.setPressureProfile(profile, for: segment.id)
                        changed = true
                    }
                }
            }
            curve.pressures = pressures
            document.layers[layerIndex].openCurves[curveIndex] = curve
        }

        for pointIndex in document.layers[layerIndex].points.indices {
            var point = document.layers[layerIndex].points[pointIndex]
            guard geometryEditorSelection.standalonePointIDs.contains(point.id) ||
                    selectedPointIDs.contains(point.id)
            else { continue }
            point.pressure = pressureForTracePoint(point.position, tracePoints: tracePoints, tracePressures: tracePressures)
            document.layers[layerIndex].points[pointIndex] = point
            changed = true
        }

        if changed {
            setGeometryEditorDocument(document)
            postStatus("Applied pressure trace")
        } else {
            postStatus("Pressure trace: no selected anchors or points")
        }
    }

    var canClearPressureSelectedGeometry: Bool {
        canPressureTraceSelectedGeometry
    }

    func clearPressureForSelectedGeometry() {
        guard canClearPressureSelectedGeometry,
              var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }

        recordGeometryEditorUndoSnapshot()
        var changed = false
        let selectedPointIDs = geometryEditorSelection.pointIDs
        let selectedSegmentIDs = geometryEditorSelection.segmentIDs

        for polygonIndex in document.layers[layerIndex].polygons.indices {
            var polygon = document.layers[layerIndex].polygons[polygonIndex]
            let objectSelected = geometryEditorSelection.polygonIDs.contains(polygon.id)
            let anchorIDs = polygon.segments.map(\.startAnchorID)
            let selectedAnchors = Set(anchorIDs).intersection(selectedPointIDs)
            let selectedSegments = polygon.segments.filter { selectedSegmentIDs.contains($0.id) }
            guard objectSelected || !selectedAnchors.isEmpty || !selectedSegments.isEmpty else { continue }
            var pressures = normalizedPressureValues(polygon.pressures, count: polygon.segments.count)
            for (pressureIndex, anchorID) in anchorIDs.enumerated() {
                let segmentSelected = selectedSegments.contains { segment in
                    segment.startAnchorID == anchorID || segment.endAnchorID == anchorID
                }
                let shouldClearAnchor = !selectedSegmentIDs.isEmpty
                    ? segmentSelected
                    : (objectSelected || selectedAnchors.contains(anchorID))
                guard shouldClearAnchor else { continue }
                pressures[pressureIndex] = 1.0
                changed = true
            }
            if objectSelected {
                for segment in polygon.segments {
                    polygon.setPressureProfile(nil, for: segment.id)
                    changed = true
                }
            }
            if !selectedSegments.isEmpty {
                for segment in selectedSegments {
                    guard let segmentIndex = polygon.segments.firstIndex(where: { $0.id == segment.id }) else { continue }
                    pressures[(segmentIndex + 1) % max(1, polygon.segments.count)] = 1.0
                    polygon.setPressureProfile(nil, for: segment.id)
                    changed = true
                }
            }
            polygon.pressures = pressures
            document.layers[layerIndex].polygons[polygonIndex] = polygon
        }

        for curveIndex in document.layers[layerIndex].openCurves.indices {
            var curve = document.layers[layerIndex].openCurves[curveIndex]
            let objectSelected = geometryEditorSelection.openCurveIDs.contains(curve.id)
            var anchorIDs: [EditableGeometryID] = []
            if let first = curve.segments.first?.startAnchorID {
                anchorIDs.append(first)
            }
            anchorIDs.append(contentsOf: curve.segments.map(\.endAnchorID))
            let selectedAnchors = Set(anchorIDs).intersection(selectedPointIDs)
            let selectedSegments = curve.segments.filter { selectedSegmentIDs.contains($0.id) }
            guard objectSelected || !selectedAnchors.isEmpty || !selectedSegments.isEmpty else { continue }
            var pressures = normalizedPressureValues(curve.pressures, count: anchorIDs.count)
            for (pressureIndex, anchorID) in anchorIDs.enumerated() {
                let segmentSelected = selectedSegments.contains { segment in
                    segment.startAnchorID == anchorID || segment.endAnchorID == anchorID
                }
                let shouldClearAnchor = !selectedSegmentIDs.isEmpty
                    ? segmentSelected
                    : (objectSelected || selectedAnchors.contains(anchorID))
                guard shouldClearAnchor else { continue }
                pressures[pressureIndex] = 1.0
                changed = true
            }
            if objectSelected {
                for segment in curve.segments {
                    curve.setPressureProfile(nil, for: segment.id)
                    changed = true
                }
            }
            if !selectedSegments.isEmpty {
                for segment in selectedSegments {
                    curve.setPressureProfile(nil, for: segment.id)
                    changed = true
                }
            }
            curve.pressures = pressures
            document.layers[layerIndex].openCurves[curveIndex] = curve
        }

        for pointIndex in document.layers[layerIndex].points.indices {
            var point = document.layers[layerIndex].points[pointIndex]
            guard geometryEditorSelection.standalonePointIDs.contains(point.id) ||
                    selectedPointIDs.contains(point.id)
            else { continue }
            point.pressure = 1.0
            document.layers[layerIndex].points[pointIndex] = point
            changed = true
        }

        if changed {
            setGeometryEditorDocument(document)
            postStatus("Cleared pressure")
        } else {
            postStatus("Clear pressure: no selected anchors or points")
        }
    }

    func clearGeometryPressureTraceStroke() {
        geometryEditorPressureTracePoints.removeAll()
        geometryEditorPressureTracePressures.removeAll()
    }

    private func pressureForTracePoint(
        _ point: Vector2D,
        tracePoints: [Vector2D],
        tracePressures: [Double]
    ) -> Double {
        guard !tracePoints.isEmpty else { return 1.0 }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, tracePoint) in tracePoints.enumerated() {
            let distance = point.distance(to: tracePoint)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        let pressure = bestIndex < tracePressures.count ? tracePressures[bestIndex] : tracePressures.last ?? 1.0
        return normalizedPressure(pressure)
    }

    private func pressureProfileForSegment(
        _ segment: EditableCubicSegment,
        pointMap: [EditableGeometryID: Vector2D],
        tracePoints: [Vector2D],
        tracePressures: [Double],
        sampleCount: Int = 16
    ) -> [Double]? {
        guard sampleCount >= 2,
              let a0 = pointMap[segment.startAnchorID],
              let c0 = pointMap[segment.controlOutID],
              let c1 = pointMap[segment.controlInID],
              let a1 = pointMap[segment.endAnchorID]
        else { return nil }
        return (0..<sampleCount).map { index in
            let t = Double(index) / Double(sampleCount - 1)
            let point = cubicPoint(a0, c0, c1, a1, t: t)
            return pressureForTracePoint(point, tracePoints: tracePoints, tracePressures: tracePressures)
        }
    }

    private func cubicPoint(
        _ a0: Vector2D,
        _ c0: Vector2D,
        _ c1: Vector2D,
        _ a1: Vector2D,
        t: Double
    ) -> Vector2D {
        let u = 1.0 - t
        return a0 * (u * u * u)
            + c0 * (3.0 * u * u * t)
            + c1 * (3.0 * u * t * t)
            + a1 * (t * t * t)
    }

    private func normalizedPressureValues(_ values: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !values.isEmpty else { return Array(repeating: 1.0, count: count) }
        if values.count == count { return values.map(normalizedPressure) }
        if values.count > count { return Array(values.prefix(count)).map(normalizedPressure) }
        return values.map(normalizedPressure) + Array(repeating: normalizedPressure(values.last ?? 1.0), count: count - values.count)
    }

    var canFinaliseGeometryDraftPolygon: Bool {
        (geometryEditorDraftPoints.count >= 3 && selectedGeometryEditorLayerCanEdit) ||
        canFinaliseGeometryMeshExtend ||
        canCloseSelectedOpenCurve
    }

    var canFinaliseGeometryDraftOpenCurve: Bool {
        geometryEditorDraftPoints.count >= 2 && selectedGeometryEditorLayerCanEdit
    }

    func finaliseGeometryDraftPolygon() {
        guard canFinaliseGeometryDraftPolygon else { return }
        if canFinaliseGeometryMeshExtend {
            finaliseGeometryMeshExtend()
            return
        }
        if geometryEditorDraftPoints.isEmpty, canCloseSelectedOpenCurve {
            closeSelectedOpenCurve()
            return
        }
        var document = geometryEditorDocument ?? EditableGeometryDocument(name: "Untitled Polygon")
        document.ensureActiveLayer()
        if let selectedGeometryEditorLayerID,
           document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            document.activeLayerID = selectedGeometryEditorLayerID
        }
        guard let activeLayerID = document.activeLayerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == activeLayerID })
        else { return }

        let polygonIndex = document.layers[layerIndex].polygons.count + 1
        do {
            let polygon = try EditableClosedPolygon(name: "Polygon \(polygonIndex)", anchors: geometryEditorDraftPoints)
            recordGeometryEditorUndoSnapshot()
            document.layers[layerIndex].polygons.append(polygon)
            selectedGeometryEditorLayerID = activeLayerID
            setGeometryEditorDocument(document)
            geometryEditorDraftPoints.removeAll()
        } catch {
            geometryEditorLoadError = error.localizedDescription
        }
    }

    var canFinaliseGeometryMeshExtend: Bool {
        guard geometryEditorTool == .meshExtend,
              let draft = geometryEditorMeshExtendDraft,
              layerCanEdit(draft.layerID)
        else { return false }
        return meshExtendVertices(for: draft).count >= 3 &&
            (!draft.confirmedAnchors.isEmpty || canContinueGeometryMeshExtend)
    }

    func finaliseGeometryMeshExtend() {
        guard var document = geometryEditorDocument,
              canFinaliseGeometryMeshExtend,
              let draft = geometryEditorMeshExtendDraft,
              let layerIndex = document.layers.firstIndex(where: { $0.id == draft.layerID })
        else { return }

        let polygonIndex = document.layers[layerIndex].polygons.count + 1
        let polygon = meshExtendPolygon(
            name: "Mesh Polygon \(polygonIndex)",
            draft: draft
        )
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(polygon.polygon)
        document.weldPoints([polygon.startAnchorID, draft.startAnchorID])
        document.weldPoints([polygon.controlOutID, draft.controlOutID])
        document.weldPoints([polygon.controlInID, draft.controlInID])
        document.weldPoints([polygon.endAnchorID, draft.endAnchorID])
        geometryEditorMeshExtendDraft = nil
        geometryEditorSelection = EditableGeometrySelection(
            layerID: draft.layerID,
            polygonIDs: [polygon.polygon.id],
            segmentIDs: Set(polygon.outerSegmentIDs)
        )
        setGeometryEditorDocument(document)
        postStatus("Created \(polygon.polygon.segments.count)-sided mesh polygon")
    }

    var canFillSelectedGeometryTriangle: Bool {
        guard let document = geometryEditorDocument else { return false }
        return selectedMeshCornerFillDefinition(in: document) != nil
    }

    var canFillSelectedGeometryQuad: Bool {
        guard let document = geometryEditorDocument else { return false }
        return selectedMeshCornerFillDefinition(in: document) != nil
    }

    var canFillSelectedGeometryHole: Bool {
        guard let document = geometryEditorDocument else { return false }
        return orderedHoleBoundary(in: document) != nil
    }

    func fillSelectedGeometryTriangle() {
        fillSelectedGeometryCorner(kind: .triangle)
    }

    func fillSelectedGeometryQuad() {
        fillSelectedGeometryCorner(kind: .quad)
    }

    func fillSelectedGeometryHole() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        guard let boundary = orderedHoleBoundary(in: document) else {
            postStatus("Select boundary edges that form a closed loop")
            return
        }
        let polygonIndex = document.layers[layerIndex].polygons.count + 1
        guard let result = polygonFromHoleBoundary(
            boundary,
            name: "Mesh Fill \(polygonIndex)",
            document: document
        ) else { return }

        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(result.polygon)
        for weldPair in result.weldPairs {
            document.weldPoints(weldPair)
        }
        geometryEditorMeshExtendDraft = nil
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: [result.polygon.id]
        )
        setGeometryEditorDocument(document)
        postStatus("Filled mesh hole")
    }

    private enum MeshCornerFillKind {
        case triangle
        case quad
    }

    private struct MeshPolygonBuildResult {
        var polygon: EditableClosedPolygon
        var startAnchorID: EditableGeometryID
        var controlOutID: EditableGeometryID
        var controlInID: EditableGeometryID
        var endAnchorID: EditableGeometryID
        var outerSegmentIDs: [EditableGeometryID]
    }

    private struct HolePolygonBuildResult {
        var polygon: EditableClosedPolygon
        var weldPairs: [Set<EditableGeometryID>]
    }

    private struct MeshSegmentEndpoint {
        var id: EditableGeometryID
        var position: Vector2D
        var isStart: Bool
        var key: String
    }

    private struct MeshCornerFillDefinition {
        var layerID: EditableGeometryID
        var first: (reference: GeometrySegmentReference, forward: Bool)
        var second: (reference: GeometrySegmentReference, forward: Bool)
    }

    private func fillSelectedGeometryCorner(kind: MeshCornerFillKind) {
        guard var document = geometryEditorDocument,
              let definition = selectedMeshCornerFillDefinition(in: document),
              let layerIndex = document.layers.firstIndex(where: { $0.id == definition.layerID }),
              layerCanEdit(definition.layerID)
        else { return }
        let polygonIndex = document.layers[layerIndex].polygons.count + 1
        let kindName = kind == .triangle ? "Triangle" : "Quad"
        guard let result = polygonFromCornerFill(
            definition,
            kind: kind,
            name: "Mesh \(kindName) \(polygonIndex)",
            document: document
        ) else {
            postStatus("Select two connected edges")
            return
        }

        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(result.polygon)
        for weldPair in result.weldPairs {
            document.weldPoints(weldPair)
        }
        geometryEditorMeshExtendDraft = nil
        geometryEditorSelection = EditableGeometrySelection(
            layerID: definition.layerID,
            polygonIDs: [result.polygon.id]
        )
        setGeometryEditorDocument(document)
        postStatus("Filled mesh \(kindName.lowercased())")
    }

    private func meshExtendPolygon(
        name: String,
        draft: GeometryMeshExtendDraft
    ) -> MeshPolygonBuildResult {
        let vertices = meshExtendVertices(for: draft)
        let start = EditableCubicPoint(position: vertices[0], kind: .anchor)
        let controlOut = EditableCubicPoint(position: draft.controlOut, kind: .control)
        let controlIn = EditableCubicPoint(position: draft.controlIn, kind: .control)
        let end = EditableCubicPoint(position: vertices[1], kind: .anchor)

        let baseSegment = EditableCubicSegment(
            startAnchorID: start.id,
            controlOutID: controlOut.id,
            controlInID: controlIn.id,
            endAnchorID: end.id
        )
        var points = [start, controlOut, controlIn, end]
        var segments = [baseSegment]
        var previousAnchor = end
        for vertex in vertices.dropFirst(2) {
            let nextAnchor = EditableCubicPoint(position: vertex, kind: .anchor)
            let controls = linearControlPoints(from: previousAnchor.position, to: vertex)
            let controlOut = EditableCubicPoint(position: controls.0, kind: .control)
            let controlIn = EditableCubicPoint(position: controls.1, kind: .control)
            points.append(contentsOf: [controlOut, controlIn, nextAnchor])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: previousAnchor.id,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: nextAnchor.id
                )
            )
            previousAnchor = nextAnchor
        }
        let closeControls = linearControlPoints(from: previousAnchor.position, to: start.position)
        let closeControlOut = EditableCubicPoint(position: closeControls.0, kind: .control)
        let closeControlIn = EditableCubicPoint(position: closeControls.1, kind: .control)
        points.append(contentsOf: [closeControlOut, closeControlIn])
        segments.append(
            EditableCubicSegment(
                startAnchorID: previousAnchor.id,
                controlOutID: closeControlOut.id,
                controlInID: closeControlIn.id,
                endAnchorID: start.id
            )
        )
        let polygon = EditableClosedPolygon(
            name: name,
            points: points,
            segments: segments,
            pressures: Array(repeating: 1.0, count: segments.count),
            isVisible: true
        )
        return MeshPolygonBuildResult(
            polygon: polygon,
            startAnchorID: start.id,
            controlOutID: controlOut.id,
            controlInID: controlIn.id,
            endAnchorID: end.id,
            outerSegmentIDs: Array(segments.dropFirst().map(\.id))
        )
    }

    private func meshExtendVertices(for draft: GeometryMeshExtendDraft) -> [Vector2D] {
        var vertices = [draft.start, draft.end] + draft.confirmedAnchors
        if draft.isPreviewActive {
            let insertionIndex = max(0, min(draft.confirmedAnchors.count, draft.activeEdgeStartIndex - 1))
            vertices.insert(draft.apex, at: insertionIndex + 2)
        }
        return vertices
    }

    private func meshExtendActiveEdge(for draft: GeometryMeshExtendDraft) -> (start: Vector2D, end: Vector2D) {
        let vertices = [draft.start, draft.end] + draft.confirmedAnchors
        guard vertices.count >= 2 else { return (draft.start, draft.end) }
        let startIndex = max(1, min(draft.activeEdgeStartIndex, vertices.count - 1))
        let endIndex = startIndex == vertices.count - 1 ? 0 : startIndex + 1
        return (vertices[startIndex], vertices[endIndex])
    }

    private func meshExtendCandidateEdgeStartIndices(for draft: GeometryMeshExtendDraft) -> [Int] {
        let vertices = [draft.start, draft.end] + draft.confirmedAnchors
        guard vertices.count >= 2 else { return [] }
        return Array(1..<vertices.count)
    }

    private func nearestMeshExtendCandidateEdgeStartIndex(
        to point: Vector2D,
        in draft: GeometryMeshExtendDraft
    ) -> Int? {
        let vertices = [draft.start, draft.end] + draft.confirmedAnchors
        var bestIndex: Int?
        var bestDistance = 0.018
        for index in meshExtendCandidateEdgeStartIndices(for: draft) {
            let endIndex = index == vertices.count - 1 ? 0 : index + 1
            let centre = midpoint(vertices[index], vertices[endIndex])
            let distance = point.distance(to: centre)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func midpoint(_ first: Vector2D, _ second: Vector2D) -> Vector2D {
        Vector2D(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private func linearControlPoints(from start: Vector2D, to end: Vector2D) -> (Vector2D, Vector2D) {
        let delta = end - start
        return (start + delta * (1.0 / 3.0), start + delta * (2.0 / 3.0))
    }

    private func distanceFromPoint(_ point: Vector2D, toSegmentFrom start: Vector2D, to end: Vector2D) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return point.distance(to: start) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = Vector2D(x: start.x + t * dx, y: start.y + t * dy)
        return point.distance(to: projection)
    }

    private struct HoleBoundaryEdge {
        var reference: GeometrySegmentReference
        var startKey: String
        var endKey: String
    }

    private func orderedHoleBoundary(
        in document: EditableGeometryDocument
    ) -> [(reference: GeometrySegmentReference, forward: Bool)]? {
        let references = selectedGeometrySegmentReferences(in: document)
        guard references.count >= 3 else { return nil }
        var edges: [HoleBoundaryEdge] = []
        for reference in references {
            guard let start = document.point(id: reference.segment.startAnchorID)?.position,
                  let end = document.point(id: reference.segment.endAnchorID)?.position
            else { return nil }
            edges.append(
                HoleBoundaryEdge(
                    reference: reference,
                    startKey: boundaryKey(for: reference.segment.startAnchorID, position: start, in: document),
                    endKey: boundaryKey(for: reference.segment.endAnchorID, position: end, in: document)
                )
            )
        }
        var degrees: [String: Int] = [:]
        for edge in edges {
            degrees[edge.startKey, default: 0] += 1
            degrees[edge.endKey, default: 0] += 1
        }
        guard degrees.count >= 3,
              degrees.values.allSatisfy({ $0 == 2 })
        else { return nil }

        let first = edges[0]
        let startingKey = first.startKey
        var currentKey = first.endKey
        var usedSegmentIDs: Set<EditableGeometryID> = [first.reference.segment.id]
        var ordered: [(reference: GeometrySegmentReference, forward: Bool)] = [(first.reference, true)]

        while usedSegmentIDs.count < edges.count {
            guard let next = edges.first(where: { edge in
                !usedSegmentIDs.contains(edge.reference.segment.id) &&
                (edge.startKey == currentKey || edge.endKey == currentKey)
            }) else { return nil }
            let forward = next.startKey == currentKey
            currentKey = forward ? next.endKey : next.startKey
            usedSegmentIDs.insert(next.reference.segment.id)
            ordered.append((next.reference, forward))
            if currentKey == startingKey && usedSegmentIDs.count < edges.count {
                return nil
            }
        }

        return currentKey == startingKey ? ordered : nil
    }

    private func boundaryKey(
        for pointID: EditableGeometryID,
        position: Vector2D,
        in document: EditableGeometryDocument
    ) -> String {
        let welded = document.weldedPointIDs(containing: pointID)
        if welded.count > 1 {
            return welded.map(\.uuidString).sorted().joined(separator: "|")
        }
        let scale = 100_000.0
        let x = Int((position.x * scale).rounded())
        let y = Int((position.y * scale).rounded())
        return "pos:\(x):\(y)"
    }

    private func selectedMeshCornerFillDefinition(
        in document: EditableGeometryDocument
    ) -> MeshCornerFillDefinition? {
        let references = selectedGeometrySegmentReferences(in: document)
        guard references.count == 2,
              references[0].layerID == references[1].layerID,
              layerCanEdit(references[0].layerID)
        else { return nil }

        let firstEndpoints = meshSegmentEndpoints(for: references[0], in: document)
        let secondEndpoints = meshSegmentEndpoints(for: references[1], in: document)
        guard firstEndpoints.count == 2, secondEndpoints.count == 2 else { return nil }

        let matches = firstEndpoints.flatMap { first in
            secondEndpoints.compactMap { second -> (MeshSegmentEndpoint, MeshSegmentEndpoint)? in
                first.key == second.key ? (first, second) : nil
            }
        }
        guard matches.count == 1,
              let shared = matches.first
        else { return nil }

        return MeshCornerFillDefinition(
            layerID: references[0].layerID,
            first: (
                reference: references[0],
                forward: !shared.0.isStart
            ),
            second: (
                reference: references[1],
                forward: shared.1.isStart
            )
        )
    }

    private func meshSegmentEndpoints(
        for reference: GeometrySegmentReference,
        in document: EditableGeometryDocument
    ) -> [MeshSegmentEndpoint] {
        guard let start = document.point(id: reference.segment.startAnchorID)?.position,
              let end = document.point(id: reference.segment.endAnchorID)?.position
        else { return [] }
        return [
            MeshSegmentEndpoint(
                id: reference.segment.startAnchorID,
                position: start,
                isStart: true,
                key: boundaryKey(for: reference.segment.startAnchorID, position: start, in: document)
            ),
            MeshSegmentEndpoint(
                id: reference.segment.endAnchorID,
                position: end,
                isStart: false,
                key: boundaryKey(for: reference.segment.endAnchorID, position: end, in: document)
            )
        ]
    }

    private func polygonFromCornerFill(
        _ definition: MeshCornerFillDefinition,
        kind: MeshCornerFillKind,
        name: String,
        document: EditableGeometryDocument
    ) -> HolePolygonBuildResult? {
        let firstIDs = orientedSegmentIDs(definition.first.reference.segment, forward: definition.first.forward)
        let secondIDs = orientedSegmentIDs(definition.second.reference.segment, forward: definition.second.forward)
        guard let firstStartID = firstIDs.start,
              let firstControlOutID = firstIDs.controlOut,
              let firstControlInID = firstIDs.controlIn,
              let sharedFromFirstID = firstIDs.end,
              let sharedFromSecondID = secondIDs.start,
              let secondControlOutID = secondIDs.controlOut,
              let secondControlInID = secondIDs.controlIn,
              let secondEndID = secondIDs.end,
              let firstStart = document.point(id: firstStartID)?.position,
              let firstControlOutPosition = document.point(id: firstControlOutID)?.position,
              let firstControlInPosition = document.point(id: firstControlInID)?.position,
              let shared = document.point(id: sharedFromFirstID)?.position,
              let secondControlOutPosition = document.point(id: secondControlOutID)?.position,
              let secondControlInPosition = document.point(id: secondControlInID)?.position,
              let secondEnd = document.point(id: secondEndID)?.position
        else { return nil }

        let firstAnchor = EditableCubicPoint(position: firstStart, kind: .anchor)
        let sharedAnchor = EditableCubicPoint(position: shared, kind: .anchor)
        let secondAnchor = EditableCubicPoint(position: secondEnd, kind: .anchor)
        let firstControlOut = EditableCubicPoint(position: firstControlOutPosition, kind: .control)
        let firstControlIn = EditableCubicPoint(position: firstControlInPosition, kind: .control)
        let secondControlOut = EditableCubicPoint(position: secondControlOutPosition, kind: .control)
        let secondControlIn = EditableCubicPoint(position: secondControlInPosition, kind: .control)

        var points = [
            firstAnchor,
            firstControlOut,
            firstControlIn,
            sharedAnchor,
            secondControlOut,
            secondControlIn,
            secondAnchor
        ]
        var segments = [
            EditableCubicSegment(
                startAnchorID: firstAnchor.id,
                controlOutID: firstControlOut.id,
                controlInID: firstControlIn.id,
                endAnchorID: sharedAnchor.id
            ),
            EditableCubicSegment(
                startAnchorID: sharedAnchor.id,
                controlOutID: secondControlOut.id,
                controlInID: secondControlIn.id,
                endAnchorID: secondAnchor.id
            )
        ]

        if kind == .quad {
            let fourthPosition = firstStart + secondEnd - shared
            let fourthAnchor = EditableCubicPoint(position: fourthPosition, kind: .anchor)
            let toFourthControls = linearControlPoints(from: secondEnd, to: fourthPosition)
            let toFirstControls = linearControlPoints(from: fourthPosition, to: firstStart)
            let toFourthControlOut = EditableCubicPoint(position: toFourthControls.0, kind: .control)
            let toFourthControlIn = EditableCubicPoint(position: toFourthControls.1, kind: .control)
            let toFirstControlOut = EditableCubicPoint(position: toFirstControls.0, kind: .control)
            let toFirstControlIn = EditableCubicPoint(position: toFirstControls.1, kind: .control)
            points.append(contentsOf: [
                toFourthControlOut,
                toFourthControlIn,
                fourthAnchor,
                toFirstControlOut,
                toFirstControlIn
            ])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: secondAnchor.id,
                    controlOutID: toFourthControlOut.id,
                    controlInID: toFourthControlIn.id,
                    endAnchorID: fourthAnchor.id
                )
            )
            segments.append(
                EditableCubicSegment(
                    startAnchorID: fourthAnchor.id,
                    controlOutID: toFirstControlOut.id,
                    controlInID: toFirstControlIn.id,
                    endAnchorID: firstAnchor.id
                )
            )
        } else {
            let closeControls = linearControlPoints(from: secondEnd, to: firstStart)
            let closeControlOut = EditableCubicPoint(position: closeControls.0, kind: .control)
            let closeControlIn = EditableCubicPoint(position: closeControls.1, kind: .control)
            points.append(contentsOf: [closeControlOut, closeControlIn])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: secondAnchor.id,
                    controlOutID: closeControlOut.id,
                    controlInID: closeControlIn.id,
                    endAnchorID: firstAnchor.id
                )
            )
        }

        return HolePolygonBuildResult(
            polygon: EditableClosedPolygon(
                name: name,
                points: points,
                segments: segments,
                pressures: Array(repeating: 1.0, count: segments.count),
                isVisible: true
            ),
            weldPairs: [
                [firstAnchor.id, firstStartID],
                [firstControlOut.id, firstControlOutID],
                [firstControlIn.id, firstControlInID],
                [sharedAnchor.id, sharedFromFirstID, sharedFromSecondID],
                [secondControlOut.id, secondControlOutID],
                [secondControlIn.id, secondControlInID],
                [secondAnchor.id, secondEndID]
            ]
        )
    }

    private func polygonFromHoleBoundary(
        _ boundary: [(reference: GeometrySegmentReference, forward: Bool)],
        name: String,
        document: EditableGeometryDocument
    ) -> HolePolygonBuildResult? {
        guard let first = boundary.first,
              let firstStart = orientedSegmentIDs(first.reference.segment, forward: first.forward).start,
              let firstStartPosition = document.point(id: firstStart)?.position
        else { return nil }

        var points: [EditableCubicPoint] = []
        var segments: [EditableCubicSegment] = []
        var weldPairs: [Set<EditableGeometryID>] = []
        let firstAnchor = EditableCubicPoint(position: firstStartPosition, kind: .anchor)
        points.append(firstAnchor)
        var currentStartID = firstAnchor.id

        for index in boundary.indices {
            let item = boundary[index]
            let ids = orientedSegmentIDs(item.reference.segment, forward: item.forward)
            guard let oldStartID = ids.start,
                  let oldControlOutID = ids.controlOut,
                  let oldControlInID = ids.controlIn,
                  let oldEndID = ids.end,
                  let oldControlOut = document.point(id: oldControlOutID)?.position,
                  let oldControlIn = document.point(id: oldControlInID)?.position,
                  let oldEnd = document.point(id: oldEndID)?.position
            else { return nil }

            let controlOut = EditableCubicPoint(position: oldControlOut, kind: .control)
            let controlIn = EditableCubicPoint(position: oldControlIn, kind: .control)
            let isLast = index == boundary.indices.last
            let endAnchorID: EditableGeometryID
            if isLast {
                endAnchorID = firstAnchor.id
            } else {
                let endAnchor = EditableCubicPoint(position: oldEnd, kind: .anchor)
                points.append(endAnchor)
                endAnchorID = endAnchor.id
            }
            points.append(contentsOf: [controlOut, controlIn])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: currentStartID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchorID
                )
            )
            weldPairs.append([currentStartID, oldStartID])
            weldPairs.append([controlOut.id, oldControlOutID])
            weldPairs.append([controlIn.id, oldControlInID])
            weldPairs.append([endAnchorID, oldEndID])
            currentStartID = endAnchorID
        }

        guard segments.count >= 3 else { return nil }
        return HolePolygonBuildResult(
            polygon: EditableClosedPolygon(
                name: name,
                points: points,
                segments: segments,
                pressures: Array(repeating: 1.0, count: segments.count),
                isVisible: true
            ),
            weldPairs: weldPairs
        )
    }

    private func orientedSegmentIDs(
        _ segment: EditableCubicSegment,
        forward: Bool
    ) -> (start: EditableGeometryID?, controlOut: EditableGeometryID?, controlIn: EditableGeometryID?, end: EditableGeometryID?) {
        if forward {
            return (segment.startAnchorID, segment.controlOutID, segment.controlInID, segment.endAnchorID)
        }
        return (segment.endAnchorID, segment.controlInID, segment.controlOutID, segment.startAnchorID)
    }

    func finaliseGeometryDraftOpenCurve() {
        guard canFinaliseGeometryDraftOpenCurve else { return }
        var document = geometryEditorDocument ?? EditableGeometryDocument(name: "Untitled Polygon")
        document.ensureActiveLayer()
        if let selectedGeometryEditorLayerID,
           document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            document.activeLayerID = selectedGeometryEditorLayerID
        }
        guard let activeLayerID = document.activeLayerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == activeLayerID })
        else { return }

        let curveIndex = document.layers[layerIndex].openCurves.count + 1
        let curve = EditableOpenCurve(name: "Open Curve \(curveIndex)", anchors: geometryEditorDraftPoints)
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].openCurves.append(curve)
        selectedGeometryEditorLayerID = activeLayerID
        geometryEditorSelection = EditableGeometrySelection(layerID: activeLayerID, openCurveIDs: [curve.id])
        setGeometryEditorDocument(document)
        geometryEditorDraftPoints.removeAll()
    }

    var canCloseSelectedOpenCurve: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let curveID = geometryEditorSelection.openCurveIDs.first,
              let layer = document.layers.first(where: { $0.id == layerID }),
              let curve = layer.openCurves.first(where: { $0.id == curveID })
        else { return false }
        return curve.anchorIDs.count >= 3
    }

    func closeSelectedOpenCurve() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let curveID = geometryEditorSelection.openCurveIDs.first,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              let curveIndex = document.layers[layerIndex].openCurves.firstIndex(where: { $0.id == curveID }),
              let polygon = document.layers[layerIndex].openCurves[curveIndex].closingToPolygon()
        else { return }
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].openCurves.remove(at: curveIndex)
        document.layers[layerIndex].polygons.append(polygon)
        geometryEditorSelection = EditableGeometrySelection(layerID: layerID, polygonIDs: [polygon.id])
        setGeometryEditorDocument(document)
    }

    @discardableResult
    func saveGeometryEditorDocument(named requestedName: String) -> Bool {
        guard var document = geometryEditorDocument,
              let projectURL,
              let key = selectedGeometryKey
        else { return false }

        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, String(parts[0]) == "polygonSets" else { return false }
        let oldName = String(parts[1])
        let requested = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = requested.isEmpty ? (fallback.isEmpty ? oldName : fallback) : requested
        let finalName = uniquePolygonSetName(baseName, excluding: oldName)
        let filename = "\(sanitizedGeometryFilename(finalName)).json"
        let directory = projectURL.appendingPathComponent("polygonSets", isDirectory: true)
        let url = directory.appendingPathComponent(filename)

        document.name = finalName
        applyLayerPanelState(to: &document)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try EditableGeometryJSONLoader.save(document, to: url)
            updateProjectConfig { cfg in
                if let index = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == oldName }) {
                    cfg.polygonConfig.library.polygonSets[index].name = finalName
                    cfg.polygonConfig.library.polygonSets[index].folder = "polygonSets"
                    cfg.polygonConfig.library.polygonSets[index].filename = filename
                    cfg.polygonConfig.library.polygonSets[index].polygonType = .splinePolygon
                    cfg.polygonConfig.library.polygonSets[index].regularParams = nil
                }
            }
            selectedGeometryKey = "polygonSets/\(finalName)"
            setGeometryEditorDocument(document, cleanSource: .saved)
            geometryEditorLoadError = nil
            geometryEditorReloadNonce += 1
            return true
        } catch {
            geometryEditorLoadError = error.localizedDescription
            return false
        }
    }

    func saveGeometryLayerAsSVG() {
        guard let document = geometryEditorDocument,
              let projectURL,
              let config = projectConfig,
              let activeLayer = document.activeLayer
        else { return }

        let polys = (try? document.runtimePolygons(targetLayerID: activeLayer.id)) ?? []
        guard !polys.isEmpty else {
            appStatusMessage = "Nothing to export (active layer is empty)"
            return
        }

        let svgsDir = projectURL.appendingPathComponent("svgs")
        let docPart   = LoomSVGWriter.safeStem(
            document.name.isEmpty
                ? (selectedGeometryKey?.components(separatedBy: "/").last ?? "geometry")
                : document.name
        )
        let layerPart = LoomSVGWriter.safeStem(activeLayer.name)
        let stem = "\(docPart)_\(layerPart)"

        do {
            let w = Double(config.globalConfig.width)
            let h = Double(config.globalConfig.height)
            let url = try LoomSVGWriter.writeSVG(polygons: polys, stem: stem, canvasSize: (w, h), to: svgsDir)
            appStatusMessage = "SVG saved: \(url.lastPathComponent)"
            LoomLogger.info("Geometry editor SVG saved: \(url.path)")
        } catch {
            appStatusMessage = "SVG export failed: \(error.localizedDescription)"
            LoomLogger.error("Geometry editor SVG export failed", error: error)
        }
    }

    func reloadGeometryEditorDocumentFromDisk() {
        geometryEditorReloadNonce += 1
    }

    func selectGeometryPoint(
        layerID: EditableGeometryID,
        polygonID: EditableGeometryID,
        pointID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.segmentIDs.removeAll()
            if toggle, selection.pointIDs.contains(pointID) {
                selection.pointIDs.remove(pointID)
            } else {
                selection.polygonIDs.insert(polygonID)
                selection.pointIDs.insert(pointID)
            }
            if selection.pointIDs.isEmpty {
                geometryEditorSelection = .empty
            } else {
                geometryEditorSelection = selection
            }
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: [polygonID],
            pointIDs: [pointID]
        )
    }

    func selectGeometryOpenCurvePoint(
        layerID: EditableGeometryID,
        openCurveID: EditableGeometryID,
        pointID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.segmentIDs.removeAll()
            if toggle, selection.pointIDs.contains(pointID) {
                selection.pointIDs.remove(pointID)
            } else {
                selection.openCurveIDs.insert(openCurveID)
                selection.pointIDs.insert(pointID)
            }
            if selection.pointIDs.isEmpty {
                geometryEditorSelection = .empty
            } else {
                geometryEditorSelection = selection
            }
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            openCurveIDs: [openCurveID],
            pointIDs: [pointID]
        )
    }

    func selectGeometryStandalonePoint(
        layerID: EditableGeometryID,
        pointID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.segmentIDs.removeAll()
            if toggle, selection.pointIDs.contains(pointID) {
                selection.pointIDs.remove(pointID)
                selection.standalonePointIDs.remove(pointID)
            } else {
                selection.pointIDs.insert(pointID)
                selection.standalonePointIDs.insert(pointID)
            }
            geometryEditorSelection = selection.pointIDs.isEmpty ? .empty : selection
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            standalonePointIDs: [pointID],
            pointIDs: [pointID]
        )
    }

    func selectGeometryPoints(
        layerID: EditableGeometryID,
        polygonPoints: [(polygonID: EditableGeometryID, pointID: EditableGeometryID)],
        openCurvePoints: [(openCurveID: EditableGeometryID, pointID: EditableGeometryID)],
        standalonePointIDs: Set<EditableGeometryID>,
        additive: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        let newPointIDs = Set(polygonPoints.map(\.pointID) + openCurvePoints.map(\.pointID)).union(standalonePointIDs)
        guard !newPointIDs.isEmpty else {
            if !additive { clearGeometryEditorSelection() }
            return
        }
        selectGeometryEditorLayer(id: layerID)
        var selection = additive && geometryEditorSelection.layerID == layerID
            ? geometryEditorSelection
            : EditableGeometrySelection(layerID: layerID)
        selection.layerID = layerID
        selection.segmentIDs.removeAll()
        selection.polygonIDs.formUnion(polygonPoints.map(\.polygonID))
        selection.openCurveIDs.formUnion(openCurvePoints.map(\.openCurveID))
        selection.standalonePointIDs.formUnion(standalonePointIDs)
        selection.pointIDs.formUnion(newPointIDs)
        geometryEditorSelection = selection
    }

    func selectGeometryPolygon(
        layerID: EditableGeometryID,
        polygonID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.pointIDs.removeAll()
            selection.segmentIDs.removeAll()
            if toggle, selection.polygonIDs.contains(polygonID) {
                selection.polygonIDs.remove(polygonID)
            } else {
                selection.polygonIDs.insert(polygonID)
            }
            geometryEditorSelection = selection.polygonIDs.isEmpty ? .empty : selection
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: [polygonID]
        )
    }

    func selectGeometryPolygons(layerID: EditableGeometryID, polygonIDs: Set<EditableGeometryID>, additive: Bool = false) {
        guard !polygonIDs.isEmpty else {
            if !additive { clearGeometryEditorSelection() }
            return
        }
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        var selection = additive && geometryEditorSelection.layerID == layerID
            ? geometryEditorSelection
            : EditableGeometrySelection(layerID: layerID)
        selection.layerID = layerID
        selection.pointIDs.removeAll()
        selection.segmentIDs.removeAll()
        selection.polygonIDs.formUnion(polygonIDs)
        geometryEditorSelection = selection
    }

    func selectGeometryOpenCurve(
        layerID: EditableGeometryID,
        openCurveID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.pointIDs.removeAll()
            selection.segmentIDs.removeAll()
            if toggle, selection.openCurveIDs.contains(openCurveID) {
                selection.openCurveIDs.remove(openCurveID)
            } else {
                selection.openCurveIDs.insert(openCurveID)
            }
            geometryEditorSelection = selection.openCurveIDs.isEmpty ? .empty : selection
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            openCurveIDs: [openCurveID]
        )
    }

    func selectGeometryOpenCurves(
        layerID: EditableGeometryID,
        openCurveIDs: Set<EditableGeometryID>,
        additive: Bool = false
    ) {
        guard !openCurveIDs.isEmpty else {
            if !additive { clearGeometryEditorSelection() }
            return
        }
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        var selection = additive && geometryEditorSelection.layerID == layerID
            ? geometryEditorSelection
            : EditableGeometrySelection(layerID: layerID)
        selection.layerID = layerID
        selection.pointIDs.removeAll()
        selection.segmentIDs.removeAll()
        selection.openCurveIDs.formUnion(openCurveIDs)
        geometryEditorSelection = selection
    }

    func selectGeometrySegment(
        layerID: EditableGeometryID,
        polygonID: EditableGeometryID,
        segmentID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.pointIDs.removeAll()
            if toggle, selection.segmentIDs.contains(segmentID) {
                selection.segmentIDs.remove(segmentID)
                if !selection.segmentIDs.contains(where: { _ in true }) {
                    selection.polygonIDs.remove(polygonID)
                }
            } else {
                selection.polygonIDs.insert(polygonID)
                selection.segmentIDs.insert(segmentID)
            }
            if selection.segmentIDs.isEmpty {
                geometryEditorSelection = .empty
            } else {
                geometryEditorSelection = selection
            }
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: [polygonID],
            segmentIDs: [segmentID]
        )
    }

    func selectGeometryOpenCurveSegment(
        layerID: EditableGeometryID,
        openCurveID: EditableGeometryID,
        segmentID: EditableGeometryID,
        additive: Bool = false,
        toggle: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        selectGeometryEditorLayer(id: layerID)
        if (additive || toggle), geometryEditorSelection.layerID == layerID {
            var selection = geometryEditorSelection
            selection.layerID = layerID
            selection.pointIDs.removeAll()
            if toggle, selection.segmentIDs.contains(segmentID) {
                selection.segmentIDs.remove(segmentID)
                if selection.segmentIDs.isEmpty {
                    selection.openCurveIDs.remove(openCurveID)
                }
            } else {
                selection.openCurveIDs.insert(openCurveID)
                selection.segmentIDs.insert(segmentID)
            }
            if selection.segmentIDs.isEmpty {
                geometryEditorSelection = .empty
            } else {
                geometryEditorSelection = selection
            }
            return
        }
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            openCurveIDs: [openCurveID],
            segmentIDs: [segmentID]
        )
    }

    func selectGeometrySegments(
        layerID: EditableGeometryID,
        polygonSegments: [(polygonID: EditableGeometryID, segmentID: EditableGeometryID)],
        openCurveSegments: [(openCurveID: EditableGeometryID, segmentID: EditableGeometryID)],
        additive: Bool = false
    ) {
        guard layerCanEdit(layerID) else { return }
        let newSegmentIDs = Set(polygonSegments.map(\.segmentID) + openCurveSegments.map(\.segmentID))
        guard !newSegmentIDs.isEmpty else {
            if !additive { clearGeometryEditorSelection() }
            return
        }
        selectGeometryEditorLayer(id: layerID)
        var selection = additive && geometryEditorSelection.layerID == layerID
            ? geometryEditorSelection
            : EditableGeometrySelection(layerID: layerID)
        selection.layerID = layerID
        selection.pointIDs.removeAll()
        selection.polygonIDs.formUnion(polygonSegments.map(\.polygonID))
        selection.openCurveIDs.formUnion(openCurveSegments.map(\.openCurveID))
        selection.segmentIDs.formUnion(newSegmentIDs)
        geometryEditorSelection = selection
    }

    func clearGeometryEditorSelection() {
        geometryEditorSelection = .empty
        clearGeometryEditorAutoWeldCandidates()
    }

    func postStatus(_ message: String) {
        appStatusMessage = message
        LoomLogger.info("Status: \(message)")
    }

    var canUndoGeometryEdit: Bool {
        !geometryEditorHistory.undoStack.isEmpty
    }

    var canRedoGeometryEdit: Bool {
        !geometryEditorHistory.redoStack.isEmpty
    }

    func recordGeometryEditorUndoSnapshot() {
        guard let document = geometryEditorDocument else { return }
        geometryEditorHistory.record(
            EditableGeometrySnapshot(document: document, selection: geometryEditorSelection)
        )
    }

    func undoGeometryEdit() {
        guard let document = geometryEditorDocument,
              let snapshot = geometryEditorHistory.undo(
                current: EditableGeometrySnapshot(document: document, selection: geometryEditorSelection)
              )
        else { return }
        geometryEditorDocument = snapshot.document
        geometryEditorSelection = snapshot.selection
        syncGeometryEditorLayers(from: snapshot.document.layers)
        pruneGeometryEditorSelection(in: snapshot.document)
    }

    func redoGeometryEdit() {
        guard let document = geometryEditorDocument,
              let snapshot = geometryEditorHistory.redo(
                current: EditableGeometrySnapshot(document: document, selection: geometryEditorSelection)
              )
        else { return }
        geometryEditorDocument = snapshot.document
        geometryEditorSelection = snapshot.selection
        syncGeometryEditorLayers(from: snapshot.document.layers)
        pruneGeometryEditorSelection(in: snapshot.document)
    }

    var canResetSelectedGeometryControls: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }

        for polygon in layer.polygons where geometryEditorSelection.polygonIDs.contains(polygon.id) {
            if !geometryEditorSelection.segmentIDs.isEmpty { return true }
            if geometryEditorSelection.pointIDs.isEmpty { return true }
            if geometryEditorSelection.pointIDs.contains(where: { polygon.point(id: $0) != nil }) {
                return true
            }
        }
        for curve in layer.openCurves where geometryEditorSelection.openCurveIDs.contains(curve.id) {
            if !geometryEditorSelection.segmentIDs.isEmpty { return true }
            if geometryEditorSelection.pointIDs.contains(where: { curve.point(id: $0) != nil }) {
                return true
            }
        }
        return false
    }

    var canWeldSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        if geometryEditorSelection.pointIDs.count >= 2 {
            return true
        }
        return selectedGeometrySegmentReferences(in: document).count == 2
    }

    var canUnweldSelectedGeometry: Bool {
        selectedWeldPointIDs().contains { pointID in
            guard let document = geometryEditorDocument else { return false }
            return document.weldedPointIDs(containing: pointID).count > 1
        }
    }

    var canWeldAdjacentGeometryEdges: Bool {
        guard let document = geometryEditorDocument else { return false }
        return editableGeometrySegmentReferences(in: document).count >= 2
    }

    var canDeleteSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        if geometryEditorSelection.pointIDs.isEmpty && geometryEditorSelection.segmentIDs.isEmpty {
            return layer.polygons.contains { geometryEditorSelection.polygonIDs.contains($0.id) } ||
                layer.openCurves.contains { geometryEditorSelection.openCurveIDs.contains($0.id) } ||
                layer.points.contains { geometryEditorSelection.standalonePointIDs.contains($0.id) }
        }
        if !geometryEditorSelection.pointIDs.isEmpty,
           geometryEditorSelection.pointIDs.allSatisfy({ pointID in layer.points.contains { $0.id == pointID } }) {
            return true
        }
        if geometryEditorSelection.pointIDs.count == 1,
           let pointID = geometryEditorSelection.pointIDs.first {
            return layer.polygons.contains {
                geometryEditorSelection.polygonIDs.contains($0.id) &&
                $0.point(id: pointID)?.kind == .anchor
            }
        }
        if geometryEditorSelection.segmentIDs.count == 1 {
            return layer.polygons.contains { geometryEditorSelection.polygonIDs.contains($0.id) }
        }
        if geometryEditorSelection.pointIDs.isEmpty,
           geometryEditorSelection.segmentIDs.count == 2 {
            let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
            if let layerIndex, selectedInternalHealPair(in: document, layerIndex: layerIndex) != nil {
                return true
            }
        }
        return false
    }

    var canDeleteAllLayerGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = selectedGeometryEditorLayerID ?? geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible, layer.isEditable
        else { return false }
        return !layer.polygons.isEmpty || !layer.openCurves.isEmpty || !layer.points.isEmpty
    }

    var canTransformSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        return !selectedTransformSeedPointIDs(in: layer, selection: geometryEditorSelection).isEmpty
    }

    var canDuplicateSelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        return layer.polygons.contains { geometryEditorSelection.polygonIDs.contains($0.id) } ||
            layer.openCurves.contains { geometryEditorSelection.openCurveIDs.contains($0.id) } ||
            !geometryEditorSelection.pointIDs.intersection(Set(layer.points.map(\.id))).isEmpty
    }

    var canCutCopySelectedGeometry: Bool {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else { return false }
        return layer.polygons.contains { geometryEditorSelection.polygonIDs.contains($0.id) } ||
            layer.openCurves.contains { geometryEditorSelection.openCurveIDs.contains($0.id) } ||
            layer.points.contains { geometryEditorSelection.standalonePointIDs.contains($0.id) }
    }

    var canPasteGeometry: Bool { geometryEditorClipboard != nil }

    var selectedGeometryAnchorCount: Int {
        if geometryEditorTool == .pointByPoint, !geometryEditorDraftPoints.isEmpty {
            return geometryEditorDraftPoints.count
        }
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID })
        else { return 0 }
        let polygonAnchors = layer.polygons
            .filter { geometryEditorSelection.polygonIDs.contains($0.id) }
            .flatMap(\.anchorIDs)
        let curveAnchors = layer.openCurves
            .filter { geometryEditorSelection.openCurveIDs.contains($0.id) }
            .flatMap(\.anchorIDs)
        let standalonePoints = layer.points
            .filter { geometryEditorSelection.standalonePointIDs.contains($0.id) || geometryEditorSelection.pointIDs.contains($0.id) }
            .map(\.id)
        return Set(polygonAnchors + curveAnchors + standalonePoints).count
    }

    var selectedRegularPolygonParameters: EditableRegularPolygonParameters? {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              geometryEditorSelection.polygonIDs.count == 1,
              geometryEditorSelection.openCurveIDs.isEmpty,
              geometryEditorSelection.pointIDs.isEmpty,
              geometryEditorSelection.segmentIDs.isEmpty,
              let polygonID = geometryEditorSelection.polygonIDs.first,
              let layer = document.layers.first(where: { $0.id == layerID }),
              let polygon = layer.polygons.first(where: { $0.id == polygonID }),
              case .regularPolygon(let parameters) = polygon.parametricSource
        else { return nil }
        return parameters
    }

    func updateSelectedRegularPolygonParameters(
        _ update: (inout EditableRegularPolygonParameters) -> Void
    ) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              geometryEditorSelection.polygonIDs.count == 1,
              let polygonID = geometryEditorSelection.polygonIDs.first,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              let polygonIndex = document.layers[layerIndex].polygons.firstIndex(where: { $0.id == polygonID }),
              case .regularPolygon(var parameters) = document.layers[layerIndex].polygons[polygonIndex].parametricSource
        else { return }

        update(&parameters)
        parameters.sides = max(3, min(64, parameters.sides))
        parameters.radius = max(0.01, min(2.0, parameters.radius))
        parameters.innerRadius = max(0.05, min(1.0, parameters.innerRadius))
        parameters.scaleX = max(0.05, min(4.0, parameters.scaleX))
        parameters.scaleY = max(0.05, min(4.0, parameters.scaleY))

        do {
            let source = EditableParametricSource.regularPolygon(parameters)
            document.layers[layerIndex].polygons[polygonIndex] =
                try document.layers[layerIndex].polygons[polygonIndex].regeneratedFromParametricSource(source)
            setGeometryEditorDocument(document)
        } catch {
            postStatus(error.localizedDescription)
        }
    }

    func duplicateSelectedGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              canDuplicateSelectedGeometry
        else {
            postStatus("Duplicate: no selectable geometry")
            return
        }

        let selectedPolygons = geometryEditorSelection.polygonIDs
        let selectedCurves = geometryEditorSelection.openCurveIDs
        let selectedStandalonePoints = geometryEditorSelection.pointIDs
        var copiedPolygonIDs = Set<EditableGeometryID>()
        var copiedCurveIDs = Set<EditableGeometryID>()
        var copiedStandalonePointIDs = Set<EditableGeometryID>()
        let selectedPoints = selectedGeometryPoints(in: document.layers[layerIndex])
        let offsetDistance = duplicateOffsetDistance(for: selectedPoints)
        let offset = Vector2D(x: offsetDistance, y: -offsetDistance)

        var polygonCopies: [EditableClosedPolygon] = []
        for polygon in document.layers[layerIndex].polygons where selectedPolygons.contains(polygon.id) {
            let copy = polygon.duplicated(name: "\(polygon.name) Copy").translated(by: offset)
            copiedPolygonIDs.insert(copy.id)
            polygonCopies.append(copy)
        }

        var curveCopies: [EditableOpenCurve] = []
        for curve in document.layers[layerIndex].openCurves where selectedCurves.contains(curve.id) {
            let copy = curve.duplicated(name: "\(curve.name) Copy").translated(by: offset)
            copiedCurveIDs.insert(copy.id)
            curveCopies.append(copy)
        }

        var pointCopies: [EditableStandalonePoint] = []
        for point in document.layers[layerIndex].points where selectedStandalonePoints.contains(point.id) {
            let copy = point.duplicated(name: "\(point.name) Copy").translated(by: offset)
            copiedStandalonePointIDs.insert(copy.id)
            pointCopies.append(copy)
        }

        guard !polygonCopies.isEmpty || !curveCopies.isEmpty || !pointCopies.isEmpty else {
            postStatus("Duplicate: selected geometry was not found in layer")
            return
        }
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(contentsOf: polygonCopies)
        document.layers[layerIndex].openCurves.append(contentsOf: curveCopies)
        document.layers[layerIndex].points.append(contentsOf: pointCopies)
        geometryEditorDocument = document
        syncGeometryEditorLayers(from: document.layers)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: copiedPolygonIDs,
            openCurveIDs: copiedCurveIDs,
            standalonePointIDs: copiedStandalonePointIDs,
            pointIDs: copiedStandalonePointIDs
        )
        selectedGeometryEditorLayerID = layerID
        postStatus("Duplicated \(polygonCopies.count + curveCopies.count + pointCopies.count) item(s)")
    }

    func duplicateSelectedGeometryToNewLayer(named proposedName: String) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              canDuplicateSelectedGeometry
        else {
            postStatus("Duplicate to layer: no selectable geometry")
            return
        }

        let selectedPolygons       = geometryEditorSelection.polygonIDs
        let selectedCurves         = geometryEditorSelection.openCurveIDs
        let selectedStandalonePoints = geometryEditorSelection.pointIDs

        let polygonCopies = document.layers[layerIndex].polygons
            .filter { selectedPolygons.contains($0.id) }
            .map { $0.duplicated(name: $0.name) }
        let curveCopies = document.layers[layerIndex].openCurves
            .filter { selectedCurves.contains($0.id) }
            .map { $0.duplicated(name: $0.name) }
        let pointCopies = document.layers[layerIndex].points
            .filter { selectedStandalonePoints.contains($0.id) }
            .map { $0.duplicated(name: $0.name) }

        guard !polygonCopies.isEmpty || !curveCopies.isEmpty || !pointCopies.isEmpty else {
            postStatus("Duplicate to layer: selected geometry not found")
            return
        }

        let layerName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = layerName.isEmpty ? "Layer \(document.layers.count + 1)" : layerName
        let newLayer  = EditableGeometryLayer(name: finalName, polygons: polygonCopies,
                                              openCurves: curveCopies, points: pointCopies)

        recordGeometryEditorUndoSnapshot()
        document.layers.insert(newLayer, at: layerIndex + 1)
        document.activeLayerID = layerID
        geometryEditorDocument = document
        syncGeometryEditorLayers(from: document.layers)
        // Stay on original layer with original selection unchanged
        selectedGeometryEditorLayerID = layerID
        postStatus("Duplicated to new layer \"\(finalName)\"")
    }

    func cutSelectedGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              canCutCopySelectedGeometry
        else {
            postStatus("Cut: no selectable geometry")
            return
        }
        let selectedPolygons = geometryEditorSelection.polygonIDs
        let selectedCurves = geometryEditorSelection.openCurveIDs
        let selectedPoints = geometryEditorSelection.standalonePointIDs
        let polygons = document.layers[layerIndex].polygons.filter { selectedPolygons.contains($0.id) }
        let curves = document.layers[layerIndex].openCurves.filter { selectedCurves.contains($0.id) }
        let points = document.layers[layerIndex].points.filter { selectedPoints.contains($0.id) }
        guard !polygons.isEmpty || !curves.isEmpty || !points.isEmpty else {
            postStatus("Cut: selected geometry was not found in layer")
            return
        }
        let allAnchors: [Vector2D] =
            polygons.flatMap { p in p.anchorIDs.compactMap { p.point(id: $0)?.position } } +
            curves.flatMap { c in c.anchorIDs.compactMap { c.point(id: $0)?.position } } +
            points.map(\.position)
        let centroid = allAnchors.isEmpty ? geometryEditorLastClickPosition :
            Vector2D(x: allAnchors.map(\.x).reduce(0, +) / Double(allAnchors.count),
                     y: allAnchors.map(\.y).reduce(0, +) / Double(allAnchors.count))
        geometryEditorClipboard = GeometryClipboardEntry(polygons: polygons, openCurves: curves, standalonePoints: points, centroid: centroid)
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.removeAll { selectedPolygons.contains($0.id) }
        document.layers[layerIndex].openCurves.removeAll { selectedCurves.contains($0.id) }
        document.layers[layerIndex].points.removeAll { selectedPoints.contains($0.id) }
        geometryEditorSelection = .empty
        setGeometryEditorDocument(document)
        postStatus("Cut \(polygons.count + curves.count + points.count) item(s)")
    }

    func copySelectedGeometry() {
        guard let document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              canCutCopySelectedGeometry
        else {
            postStatus("Copy: no selectable geometry")
            return
        }
        let polygons = layer.polygons.filter { geometryEditorSelection.polygonIDs.contains($0.id) }
        let curves = layer.openCurves.filter { geometryEditorSelection.openCurveIDs.contains($0.id) }
        let points = layer.points.filter { geometryEditorSelection.standalonePointIDs.contains($0.id) }
        guard !polygons.isEmpty || !curves.isEmpty || !points.isEmpty else {
            postStatus("Copy: selected geometry was not found in layer")
            return
        }
        let allAnchors: [Vector2D] =
            polygons.flatMap { p in p.anchorIDs.compactMap { p.point(id: $0)?.position } } +
            curves.flatMap { c in c.anchorIDs.compactMap { c.point(id: $0)?.position } } +
            points.map(\.position)
        let centroid = allAnchors.isEmpty ? geometryEditorLastClickPosition :
            Vector2D(x: allAnchors.map(\.x).reduce(0, +) / Double(allAnchors.count),
                     y: allAnchors.map(\.y).reduce(0, +) / Double(allAnchors.count))
        geometryEditorClipboard = GeometryClipboardEntry(polygons: polygons, openCurves: curves, standalonePoints: points, centroid: centroid)
        postStatus("Copied \(polygons.count + curves.count + points.count) item(s)")
    }

    func pasteGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = selectedGeometryEditorLayerID ?? geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              let clipboard = geometryEditorClipboard
        else {
            postStatus(geometryEditorClipboard == nil ? "Paste: nothing on clipboard" : "Paste: no active editable layer")
            return
        }
        let pasteOffset = geometryEditorLastClickPosition - clipboard.centroid
        var pastedPolygonIDs = Set<EditableGeometryID>()
        var pastedCurveIDs = Set<EditableGeometryID>()
        var pastedPointIDs = Set<EditableGeometryID>()
        var polygonCopies: [EditableClosedPolygon] = []
        for polygon in clipboard.polygons {
            let copy = polygon.duplicated(name: polygon.name).translated(by: pasteOffset)
            pastedPolygonIDs.insert(copy.id)
            polygonCopies.append(copy)
        }
        var curveCopies: [EditableOpenCurve] = []
        for curve in clipboard.openCurves {
            let copy = curve.duplicated(name: curve.name).translated(by: pasteOffset)
            pastedCurveIDs.insert(copy.id)
            curveCopies.append(copy)
        }
        var pointCopies: [EditableStandalonePoint] = []
        for point in clipboard.standalonePoints {
            let copy = point.duplicated(name: point.name).translated(by: pasteOffset)
            pastedPointIDs.insert(copy.id)
            pointCopies.append(copy)
        }
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(contentsOf: polygonCopies)
        document.layers[layerIndex].openCurves.append(contentsOf: curveCopies)
        document.layers[layerIndex].points.append(contentsOf: pointCopies)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: pastedPolygonIDs,
            openCurveIDs: pastedCurveIDs,
            standalonePointIDs: pastedPointIDs,
            pointIDs: pastedPointIDs
        )
        selectedGeometryEditorLayerID = layerID
        setGeometryEditorDocument(document)
        postStatus("Pasted \(polygonCopies.count + curveCopies.count + pointCopies.count) item(s)")
    }

    private func selectedGeometryPoints(in layer: EditableGeometryLayer) -> [Vector2D] {
        let polygonPoints = layer.polygons
            .filter { geometryEditorSelection.polygonIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        let curvePoints = layer.openCurves
            .filter { geometryEditorSelection.openCurveIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        let standalonePoints = layer.points
            .filter { geometryEditorSelection.standalonePointIDs.contains($0.id) || geometryEditorSelection.pointIDs.contains($0.id) }
            .map(\.position)
        return polygonPoints + curvePoints + standalonePoints
    }

    private func selectedGeometryObjectPointIDs(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Set<EditableGeometryID> {
        var ids = Set<EditableGeometryID>()
        for polygon in layer.polygons where selection.polygonIDs.contains(polygon.id) {
            ids.formUnion(polygon.points.map(\.id))
        }
        for curve in layer.openCurves where selection.openCurveIDs.contains(curve.id) {
            ids.formUnion(curve.points.map(\.id))
        }
        ids.formUnion(layer.points.filter { selection.standalonePointIDs.contains($0.id) }.map(\.id))
        return ids
    }

    private func selectedGeometrySegmentPointIDs(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Set<EditableGeometryID> {
        var ids = Set<EditableGeometryID>()
        for polygon in layer.polygons where selection.polygonIDs.contains(polygon.id) {
            for segment in polygon.segments where selection.segmentIDs.contains(segment.id) {
                ids.formUnion(segment.pointIDs)
                ids.formUnion(polygon.attachedControlIDs(forSegment: segment))
            }
        }
        for curve in layer.openCurves where selection.openCurveIDs.contains(curve.id) {
            for segment in curve.segments where selection.segmentIDs.contains(segment.id) {
                ids.formUnion(segment.pointIDs)
                ids.formUnion(curve.attachedControlIDs(forSegment: segment))
            }
        }
        return ids
    }

    private func selectedGeometryDirectPointIDs(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Set<EditableGeometryID> {
        let layerPointIDs = Set(
            layer.polygons.flatMap { $0.points.map(\.id) } +
            layer.openCurves.flatMap { $0.points.map(\.id) } +
            layer.points.map(\.id)
        )
        return selection.pointIDs.intersection(layerPointIDs)
    }

    private func selectedTransformSeedPointIDs(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Set<EditableGeometryID> {
        if !selection.pointIDs.isEmpty {
            return selectedGeometryDirectPointIDs(in: layer, selection: selection)
        }
        if !selection.segmentIDs.isEmpty {
            return selectedGeometrySegmentPointIDs(in: layer, selection: selection)
        }
        return selectedGeometryObjectPointIDs(in: layer, selection: selection)
    }

    private func translateRelationalPointIDs(
        _ seedIDs: Set<EditableGeometryID>,
        by delta: Vector2D,
        in document: inout EditableGeometryDocument
    ) {
        guard !seedIDs.isEmpty else { return }
        for pointID in document.relationalPointIDs(startingWith: seedIDs) {
            guard let position = document.point(id: pointID)?.position else { continue }
            document.setPointPosition(id: pointID, to: position + delta)
        }
    }

    private func translateAnchorPointIDs(
        _ seedIDs: Set<EditableGeometryID>,
        by delta: Vector2D,
        in document: inout EditableGeometryDocument
    ) {
        guard !seedIDs.isEmpty else { return }
        for pointID in document.relationalPointIDs(startingWith: seedIDs) {
            guard let point = document.point(id: pointID), point.kind == .anchor else { continue }
            document.setPointPosition(id: pointID, to: point.position + delta)
        }
    }

    private func duplicateOffsetDistance(for points: [Vector2D]) -> Double {
        guard !points.isEmpty else { return 0.08 }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let span = max(maxX - minX, maxY - minY)
        return min(max(span * 0.20, 0.06), 0.16)
    }

    func zoomGeometryEditorIn() {
        geometryEditorViewZoom = min(geometryEditorViewZoom * 1.25, 8.0)
    }

    func zoomGeometryEditorOut() {
        geometryEditorViewZoom = max(geometryEditorViewZoom / 1.25, 0.25)
    }

    func panGeometryEditorView(screenDelta: CGSize, canvasSize: CGFloat) {
        let scale = (canvasSize / 1040) * CGFloat(geometryEditorViewZoom)
        guard scale > 0 else { return }
        geometryEditorViewCentre = geometryEditorViewCentre - Vector2D(
            x: Double(screenDelta.width / (1000 * scale)),
            y: Double(screenDelta.height / (1000 * scale))
        )
    }

    func loadGeometryEditorReferenceImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Geometry Reference Image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }
        geometryEditorReferenceImage = image
        geometryEditorReferenceImageURL = url
        geometryEditorShowsReferenceImage = true
        postStatus("Loaded reference image")
    }

    func clearGeometryEditorReferenceImage() {
        geometryEditorReferenceImage = nil
        geometryEditorReferenceImageURL = nil
        postStatus("Cleared reference image")
    }

    func centreGeometryEditorViewOnSelectionOrLayer() {
        centreGeometryEditorSelectionOrLayerOnGrid()
    }

    func centreGeometryEditorSelectionOrLayerOnGrid() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID ?? selectedGeometryEditorLayerID ?? document.activeLayerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else {
            postStatus("Centre: no editable layer")
            return
        }

        let layer = document.layers[layerIndex]
        let pointIDs = geometryEditorSelectionHasGeometry
            ? selectedViewPointIDs(in: layer, selection: geometryEditorSelection)
            : allPointIDs(in: layer)
        let points = pointIDs.compactMap { document.point(id: $0)?.position }
        guard !points.isEmpty else {
            postStatus("Centre: no geometry in layer")
            return
        }

        let delta = Vector2D.zero - centre(of: points)
        guard abs(delta.x) > 0.0000001 || abs(delta.y) > 0.0000001 else {
            postStatus("Geometry already centred")
            return
        }

        recordGeometryEditorUndoSnapshot()
        clearParametricSourceForPointIDs(pointIDs, in: &document)
        translateRelationalPointIDs(pointIDs, by: delta, in: &document)
        setGeometryEditorDocument(document)
        postStatus("Centred geometry on grid")
    }

    func snapGeometryEditorSelectionToGrid(anchorOnly: Bool) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID ?? selectedGeometryEditorLayerID ?? document.activeLayerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else {
            postStatus("Snap: no editable layer")
            return
        }

        let layer = document.layers[layerIndex]
        var pointIDs = geometryEditorSelectionHasGeometry
            ? selectedViewPointIDs(in: layer, selection: geometryEditorSelection)
            : allPointIDs(in: layer)
        if anchorOnly {
            pointIDs = pointIDs.filter { document.point(id: $0)?.kind == .anchor }
        }
        guard !pointIDs.isEmpty else {
            postStatus("Snap: no points to snap")
            return
        }

        let spacing = geometryEditorGridSnapSpacing
        recordGeometryEditorUndoSnapshot()
        clearParametricSourceForPointIDs(pointIDs, in: &document)
        for pointID in pointIDs {
            guard let position = document.point(id: pointID)?.position else { continue }
            document.setPointPosition(id: pointID, to: snap(position, spacing: spacing))
        }
        setGeometryEditorDocument(document)
        postStatus(anchorOnly ? "Snapped anchors to grid" : "Snapped points to grid")
    }

    private var geometryEditorSelectionHasGeometry: Bool {
        !geometryEditorSelection.polygonIDs.isEmpty ||
        !geometryEditorSelection.openCurveIDs.isEmpty ||
        !geometryEditorSelection.standalonePointIDs.isEmpty ||
        !geometryEditorSelection.segmentIDs.isEmpty ||
        !geometryEditorSelection.pointIDs.isEmpty
    }

    private var geometryEditorGridSnapSpacing: Double {
        0.026
    }

    private func snap(_ point: Vector2D, spacing: Double) -> Vector2D {
        Vector2D(
            x: (point.x / spacing).rounded() * spacing,
            y: (point.y / spacing).rounded() * spacing
        )
    }

    private func selectedViewPointIDs(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Set<EditableGeometryID> {
        var ids = selectedTransformSeedPointIDs(in: layer, selection: selection)
        ids.formUnion(layer.points.filter { selection.standalonePointIDs.contains($0.id) }.map(\.id))
        return ids
    }

    private func allPointIDs(in layer: EditableGeometryLayer) -> Set<EditableGeometryID> {
        Set(
            layer.polygons.flatMap { $0.points.map(\.id) } +
            layer.openCurves.flatMap { $0.points.map(\.id) } +
            layer.points.map(\.id)
        )
    }

    func flipSelectedGeometryHorizontally() {
        scaleSelectedGeometry(x: -1, y: 1, pivot: .commonCentre)
    }

    func flipSelectedGeometryVertically() {
        scaleSelectedGeometry(x: 1, y: -1, pivot: .commonCentre)
    }

    func scaleSelectedGeometry(x: Double, y: Double, pivot: GeometryTransformPivot) {
        transformSelectedGeometry(pivot: pivot) { point, centre in
            Vector2D(
                x: (point.x - centre.x) * x + centre.x,
                y: (point.y - centre.y) * y + centre.y
            )
        }
    }

    func rotateSelectedGeometry(degrees: Double, pivot: GeometryTransformPivot) {
        let radians = degrees * .pi / 180
        transformSelectedGeometry(pivot: pivot) { point, centre in
            point.rotated(by: radians, around: centre)
        }
    }

    func beginGeometryTransformGesture() {
        guard geometryTransformGestureBase == nil,
              let document = geometryEditorDocument,
              canTransformSelectedGeometry
        else { return }
        let snapshot = EditableGeometrySnapshot(document: document, selection: geometryEditorSelection)
        geometryTransformGestureBase = snapshot
        geometryEditorHistory.record(snapshot)
    }

    func updateScaleTransformGesture(sliderValue: Double, axis: String, pivot: GeometryTransformPivot) {
        updateGeometryTransformGesture { [sliderValue, axis, pivot] document, selection in
            let factor = 1.0 + sliderValue / 100.0
            let x = axis == "Y" ? 1.0 : factor
            let y = axis == "X" ? 1.0 : factor
            applyTransform(
                to: &document,
                selection: selection,
                pivot: pivot
            ) { point, centre in
                Vector2D(
                    x: (point.x - centre.x) * x + centre.x,
                    y: (point.y - centre.y) * y + centre.y
                )
            }
        }
    }

    func updateRotateTransformGesture(sliderValue: Double, pivot: GeometryTransformPivot) {
        updateGeometryTransformGesture { [sliderValue, pivot] document, selection in
            let radians = sliderValue * 1.8 * .pi / 180
            applyTransform(
                to: &document,
                selection: selection,
                pivot: pivot
            ) { point, centre in
                point.rotated(by: radians, around: centre)
            }
        }
    }

    func endGeometryTransformGesture() {
        geometryTransformGestureBase = nil
    }

    var isGeometrySelectionDragGestureActive: Bool {
        geometryTransformGestureBase != nil
    }

    func beginGeometrySelectionDragGesture() {
        guard geometryTransformGestureBase == nil,
              let document = geometryEditorDocument
        else { return }
        let snapshot = EditableGeometrySnapshot(document: document, selection: geometryEditorSelection)
        geometryTransformGestureBase = snapshot
        geometryEditorHistory.record(snapshot)
    }

    func updateGeometrySelectionDragGesture(delta: Vector2D) {
        updateGeometryTransformGesture { [delta] document, selection in
            guard let layerID = selection.layerID,
                  let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
            else { return }
            let layer = document.layers[layerIndex]
            let seedIDs = selectedTransformSeedPointIDs(in: layer, selection: selection)
            guard !seedIDs.isEmpty else { return }
            clearParametricSourceForSelectedPolygons(in: &document, selection: selection)
            if geometryEditorAnchorOnlyEdit {
                translateAnchorPointIDs(seedIDs, by: delta, in: &document)
            } else {
                translateRelationalPointIDs(seedIDs, by: delta, in: &document)
            }
        }
    }

    func endGeometrySelectionDragGesture() {
        geometryTransformGestureBase = nil
    }

    private func updateGeometryTransformGesture(
        transform: (inout EditableGeometryDocument, EditableGeometrySelection) -> Void
    ) {
        guard let base = geometryTransformGestureBase else { return }
        var document = base.document
        transform(&document, base.selection)
        geometryEditorDocument = document
        geometryEditorSelection = base.selection
        syncGeometryEditorLayers(from: document.layers)
        pruneGeometryEditorSelection(in: document)
    }

    private func transformSelectedGeometry(
        pivot: GeometryTransformPivot,
        transform: (Vector2D, Vector2D) -> Vector2D
    ) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              document.layers.contains(where: { $0.id == layerID }),
              canTransformSelectedGeometry
        else { return }

        guard let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              !selectedTransformSeedPointIDs(in: document.layers[layerIndex], selection: geometryEditorSelection).isEmpty
        else { return }
        recordGeometryEditorUndoSnapshot()
        clearParametricSourceForSelectedPolygons(in: &document, selection: geometryEditorSelection)
        applyTransform(to: &document, selection: geometryEditorSelection, pivot: pivot, transform: transform)
        setGeometryEditorDocument(document)
    }

    private func applyTransform(
        to document: inout EditableGeometryDocument,
        selection: EditableGeometrySelection,
        pivot: GeometryTransformPivot,
        transform: (Vector2D, Vector2D) -> Vector2D
    ) {
        guard let layerID = selection.layerID,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }

        let layer = document.layers[layerIndex]
        let seedIDs = selectedTransformSeedPointIDs(in: layer, selection: selection)
        guard !seedIDs.isEmpty else { return }
        clearParametricSourceForSelectedPolygons(in: &document, selection: selection)
        let targetIDs = document.relationalPointIDs(startingWith: seedIDs)
        let selectedPoints = seedIDs.compactMap { document.point(id: $0)?.position }
        let transformCentre: Vector2D
        switch pivot {
        case .localCentre:
            transformCentre = centre(of: selectedPoints)
        case .commonCentre:
            transformCentre = centre(of: selectedPoints)
        case .absoluteCentre:
            transformCentre = .zero
        }

        transformDocumentPointIDs(targetIDs, in: &document, around: transformCentre, transform: transform)
    }

    private func clearParametricSourceForSelectedPolygons(
        in document: inout EditableGeometryDocument,
        selection: EditableGeometrySelection
    ) {
        guard let layerID = selection.layerID,
              !selection.polygonIDs.isEmpty,
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        for polygonIndex in document.layers[layerIndex].polygons.indices
            where selection.polygonIDs.contains(document.layers[layerIndex].polygons[polygonIndex].id) {
            document.layers[layerIndex].polygons[polygonIndex].parametricSource = nil
        }
    }

    private func clearParametricSourceForPointIDs(
        _ pointIDs: Set<EditableGeometryID>,
        in document: inout EditableGeometryDocument
    ) {
        guard !pointIDs.isEmpty else { return }
        for layerIndex in document.layers.indices {
            for polygonIndex in document.layers[layerIndex].polygons.indices {
                let polygonPointIDs = Set(document.layers[layerIndex].polygons[polygonIndex].points.map(\.id))
                if !polygonPointIDs.isDisjoint(with: pointIDs) {
                    document.layers[layerIndex].polygons[polygonIndex].parametricSource = nil
                }
            }
        }
    }

    private func transformDocumentPointIDs(
        _ pointIDs: Set<EditableGeometryID>,
        in document: inout EditableGeometryDocument,
        around centre: Vector2D,
        transform: (Vector2D, Vector2D) -> Vector2D
    ) {
        for pointID in pointIDs {
            guard let position = document.point(id: pointID)?.position else { continue }
            document.setPointPosition(id: pointID, to: transform(position, centre))
        }
    }

    private func selectedGeometryCentre(in layer: EditableGeometryLayer) -> Vector2D {
        selectedGeometryCentre(in: layer, selection: geometryEditorSelection)
    }

    private func selectedGeometryCentre(
        in layer: EditableGeometryLayer,
        selection: EditableGeometrySelection
    ) -> Vector2D {
        let polygonPoints = layer.polygons
            .filter { selection.polygonIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        let curvePoints = layer.openCurves
            .filter { selection.openCurveIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        let standalonePoints = layer.points
            .filter { selection.standalonePointIDs.contains($0.id) || selection.pointIDs.contains($0.id) }
            .map(\.position)
        return centre(of: polygonPoints + curvePoints + standalonePoints)
    }

    private func pivotCentre(
        _ pivot: GeometryTransformPivot,
        itemPoints: [Vector2D],
        commonCentre: Vector2D
    ) -> Vector2D {
        switch pivot {
        case .localCentre:
            return centre(of: itemPoints)
        case .commonCentre:
            return commonCentre
        case .absoluteCentre:
            return .zero
        }
    }

    private func centre(of points: [Vector2D]) -> Vector2D {
        guard !points.isEmpty else { return .zero }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return Vector2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    func moveSelectedGeometryPoint(to position: Vector2D) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let pointID = geometryEditorSelection.pointIDs.first,
              document.layers.firstIndex(where: { $0.id == layerID }) != nil,
              let currentPosition = document.point(id: pointID)?.position
        else { return }

        clearParametricSourceForSelectedPolygons(in: &document, selection: geometryEditorSelection)
        let delta = position - currentPosition
        if geometryEditorAnchorOnlyEdit {
            // Expand through relational links then filter to anchors only — control points stay fixed.
            let expanded = document.relationalPointIDs(startingWith: [pointID])
            for id in expanded {
                guard let pt = document.point(id: id), pt.kind == .anchor else { continue }
                document.setPointPosition(id: id, to: pt.position + delta)
            }
        } else {
            translateRelationalPointIDs([pointID], by: delta, in: &document)
        }
        setGeometryEditorDocument(document)
    }

    func moveSelectedGeometryPoints(by delta: Vector2D) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              !geometryEditorSelection.pointIDs.isEmpty
        else { return }

        let seedIDs = selectedTransformSeedPointIDs(in: document.layers[layerIndex], selection: geometryEditorSelection)
        guard !seedIDs.isEmpty else { return }
        clearParametricSourceForSelectedPolygons(in: &document, selection: geometryEditorSelection)
        if geometryEditorAnchorOnlyEdit {
            translateAnchorPointIDs(seedIDs, by: delta, in: &document)
        } else {
            translateRelationalPointIDs(seedIDs, by: delta, in: &document)
        }
        setGeometryEditorDocument(document)
    }

    func moveSelectedGeometryPolygons(by delta: Vector2D) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              geometryEditorSelection.pointIDs.isEmpty,
              geometryEditorSelection.segmentIDs.isEmpty
        else { return }

        let selectedPolygons = geometryEditorSelection.polygonIDs
        let selectedCurves = geometryEditorSelection.openCurveIDs
        guard !selectedPolygons.isEmpty || !selectedCurves.isEmpty else { return }
        if moveSelectedCleanRegularPolygonParametrically(by: delta, in: &document, layerIndex: layerIndex) {
            setGeometryEditorDocument(document)
            return
        }
        let seedIDs = selectedGeometryObjectPointIDs(in: document.layers[layerIndex], selection: geometryEditorSelection)
        clearParametricSourceForSelectedPolygons(in: &document, selection: geometryEditorSelection)
        translateRelationalPointIDs(seedIDs, by: delta, in: &document)
        setGeometryEditorDocument(document)
    }

    private func moveSelectedCleanRegularPolygonParametrically(
        by delta: Vector2D,
        in document: inout EditableGeometryDocument,
        layerIndex: Int
    ) -> Bool {
        guard geometryEditorSelection.polygonIDs.count == 1,
              geometryEditorSelection.openCurveIDs.isEmpty,
              let polygonID = geometryEditorSelection.polygonIDs.first,
              let polygonIndex = document.layers[layerIndex].polygons.firstIndex(where: { $0.id == polygonID }),
              case .regularPolygon(var parameters) = document.layers[layerIndex].polygons[polygonIndex].parametricSource
        else { return false }
        parameters.centre = parameters.centre + delta
        do {
            document.layers[layerIndex].polygons[polygonIndex] =
                try document.layers[layerIndex].polygons[polygonIndex].regeneratedFromParametricSource(
                    .regularPolygon(parameters)
                )
            return true
        } catch {
            postStatus(error.localizedDescription)
            return false
        }
    }

    func moveSelectedGeometrySegments(by delta: Vector2D) {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              geometryEditorSelection.pointIDs.isEmpty
        else { return }

        let selectedPolygons = geometryEditorSelection.polygonIDs
        let selectedSegments = geometryEditorSelection.segmentIDs
        let selectedCurves = geometryEditorSelection.openCurveIDs
        guard (!selectedPolygons.isEmpty || !selectedCurves.isEmpty), !selectedSegments.isEmpty else { return }

        let seedIDs = selectedGeometrySegmentPointIDs(in: document.layers[layerIndex], selection: geometryEditorSelection)
        clearParametricSourceForSelectedPolygons(in: &document, selection: geometryEditorSelection)
        if geometryEditorAnchorOnlyEdit {
            translateAnchorPointIDs(seedIDs, by: delta, in: &document)
        } else {
            translateRelationalPointIDs(seedIDs, by: delta, in: &document)
        }
        setGeometryEditorDocument(document)
    }

    func resetSelectedGeometryControls() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }

        var didReset = false
        for polygonIndex in document.layers[layerIndex].polygons.indices {
            let polygonID = document.layers[layerIndex].polygons[polygonIndex].id
            guard geometryEditorSelection.polygonIDs.contains(polygonID) else { continue }
            if geometryEditorSelection.pointIDs.isEmpty {
                let selectedSegments = geometryEditorSelection.segmentIDs
                if selectedSegments.isEmpty {
                    document.layers[layerIndex].polygons[polygonIndex].resetControlsToInferredPositions()
                } else {
                    let affectedSegments = document.layers[layerIndex].polygons[polygonIndex]
                        .segmentIDs(touchingSegmentIDs: selectedSegments)
                    document.layers[layerIndex].polygons[polygonIndex].resetControlsToInferredPositions(segmentIDs: affectedSegments)
                }
                didReset = true
            } else {
                var segmentIDs = Set<EditableGeometryID>()
                for pointID in geometryEditorSelection.pointIDs {
                    segmentIDs.formUnion(document.layers[layerIndex].polygons[polygonIndex].segmentIDs(containingPoint: pointID))
                }
                guard !segmentIDs.isEmpty else { continue }
                document.layers[layerIndex].polygons[polygonIndex].resetControlsToInferredPositions(segmentIDs: segmentIDs)
                didReset = true
            }
        }
        for curveIndex in document.layers[layerIndex].openCurves.indices {
            let curveID = document.layers[layerIndex].openCurves[curveIndex].id
            guard geometryEditorSelection.openCurveIDs.contains(curveID) else { continue }
            if geometryEditorSelection.pointIDs.isEmpty {
                let selectedSegments = geometryEditorSelection.segmentIDs
                if selectedSegments.isEmpty {
                    document.layers[layerIndex].openCurves[curveIndex].resetControlsToInferredPositions()
                } else {
                    let affectedSegments = document.layers[layerIndex].openCurves[curveIndex]
                        .segmentIDs(touchingSegmentIDs: selectedSegments)
                    document.layers[layerIndex].openCurves[curveIndex].resetControlsToInferredPositions(segmentIDs: affectedSegments)
                }
                didReset = true
            } else {
                var segmentIDs = Set<EditableGeometryID>()
                for pointID in geometryEditorSelection.pointIDs {
                    segmentIDs.formUnion(document.layers[layerIndex].openCurves[curveIndex].segmentIDs(containingPoint: pointID))
                }
                guard !segmentIDs.isEmpty else { continue }
                document.layers[layerIndex].openCurves[curveIndex].resetControlsToInferredPositions(segmentIDs: segmentIDs)
                didReset = true
            }
        }
        if didReset {
            recordGeometryEditorUndoSnapshot()
            setGeometryEditorDocument(document)
        }
    }

    func weldSelectedGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID)
        else { return }

        let pointIDs = geometryEditorSelection.pointIDs
        if pointIDs.count >= 2 {
            let existing = pointIDs.filter { document.point(id: $0) != nil }
            guard existing.count >= 2 else { return }
            let average = centre(of: existing.compactMap { document.point(id: $0)?.position })
            recordGeometryEditorUndoSnapshot()
            for pointID in existing {
                snapWeldCluster(containing: pointID, to: average, in: &document)
            }
            document.weldPoints(existing)
            setGeometryEditorDocument(document)
            postStatus("Welded \(existing.count) point(s)")
            return
        }

        let selectedEdges = selectedGeometrySegmentReferences(in: document)
        guard selectedEdges.count == 2 else { return }
        guard canWeldEdges(selectedEdges[0], selectedEdges[1], in: document, thresholds: currentWeldThresholds) else {
            postStatus("Selected edges are outside weld tolerance")
            return
        }
        recordGeometryEditorUndoSnapshot()
        weldEdgePair(selectedEdges[0], selectedEdges[1], in: &document)
        setGeometryEditorDocument(document)
        postStatus("Welded selected edges")
    }

    func weldAdjacentGeometryEdges() {
        guard var document = geometryEditorDocument else { return }
        var pairs: [(GeometrySegmentReference, GeometrySegmentReference)] = []
        let references = editableGeometrySegmentReferences(in: document)
        let thresholds = currentWeldThresholds
        for leftIndex in references.indices {
            for rightIndex in references.indices.dropFirst(leftIndex + 1) {
                guard references[leftIndex].itemID != references[rightIndex].itemID,
                      canWeldEdges(references[leftIndex], references[rightIndex], in: document, thresholds: thresholds)
                else { continue }
                pairs.append((references[leftIndex], references[rightIndex]))
            }
        }
        guard !pairs.isEmpty else {
            postStatus("No adjacent edges to weld")
            return
        }

        recordGeometryEditorUndoSnapshot()
        for pair in pairs {
            weldEdgePair(pair.0, pair.1, in: &document)
        }
        setGeometryEditorDocument(document)
        postStatus("Welded \(pairs.count) adjacent edge pair(s)")
    }

    func unweldSelectedGeometry() {
        guard var document = geometryEditorDocument else { return }
        let pointIDs = selectedWeldPointIDs(in: document)
        let weldedIDs = pointIDs.filter { document.weldedPointIDs(containing: $0).count > 1 }
        guard !weldedIDs.isEmpty else {
            postStatus("No selected welds to remove")
            return
        }
        recordGeometryEditorUndoSnapshot()
        document.removePointIDsFromWelds(weldedIDs)
        setGeometryEditorDocument(document)
        postStatus("Unwelded selected geometry")
    }

    func updateGeometryEditorAutoWeldCandidates() {
        guard geometryEditorAutoWeld,
              let document = geometryEditorDocument,
              geometryEditorSelection.pointIDs.isEmpty,
              geometryEditorSelection.segmentIDs.isEmpty,
              !geometryEditorSelection.polygonIDs.isEmpty || !geometryEditorSelection.openCurveIDs.isEmpty
        else {
            clearGeometryEditorAutoWeldCandidates()
            return
        }

        let references = editableGeometrySegmentReferences(in: document)
        let selectedItemIDs = geometryEditorSelection.polygonIDs.union(geometryEditorSelection.openCurveIDs)
        let selectedRefs = references.filter { selectedItemIDs.contains($0.itemID) }
        guard !selectedRefs.isEmpty else {
            clearGeometryEditorAutoWeldCandidates()
            return
        }

        var pairs: [(EditableGeometryID, EditableGeometryID)] = []
        var segmentIDs = Set<EditableGeometryID>()
        let thresholds = currentWeldThresholds
        for selectedRef in selectedRefs {
            for candidateRef in references where !selectedItemIDs.contains(candidateRef.itemID) {
                guard canWeldEdges(selectedRef, candidateRef, in: document, thresholds: thresholds),
                      !areEdgesAlreadyWelded(selectedRef, candidateRef, in: document)
                else { continue }
                pairs.append((selectedRef.segment.id, candidateRef.segment.id))
                segmentIDs.insert(selectedRef.segment.id)
                segmentIDs.insert(candidateRef.segment.id)
            }
        }

        geometryEditorPendingAutoWeldPairs = pairs
        geometryEditorAutoWeldSegmentIDs = segmentIDs
    }

    func executeGeometryEditorPendingAutoWelds() {
        guard geometryEditorAutoWeld,
              !geometryEditorPendingAutoWeldPairs.isEmpty,
              var document = geometryEditorDocument
        else {
            clearGeometryEditorAutoWeldCandidates()
            return
        }

        var weldedCount = 0
        for pair in geometryEditorPendingAutoWeldPairs {
            let references = editableGeometrySegmentReferences(in: document)
            guard let first = references.first(where: { $0.segment.id == pair.0 }),
                  let second = references.first(where: { $0.segment.id == pair.1 }),
                  canWeldEdges(first, second, in: document, thresholds: currentWeldThresholds),
                  !areEdgesAlreadyWelded(first, second, in: document)
            else { continue }
            weldEdgePair(first, second, in: &document)
            weldedCount += 1
        }

        clearGeometryEditorAutoWeldCandidates()
        guard weldedCount > 0 else { return }
        setGeometryEditorDocument(document)
        postStatus("Auto welded \(weldedCount) edge pair(s)")
    }

    func clearGeometryEditorAutoWeldCandidates() {
        geometryEditorPendingAutoWeldPairs.removeAll()
        geometryEditorAutoWeldSegmentIDs.removeAll()
    }

    private func performGeometryKnifeCut(from lineStart: Vector2D, to lineEnd: Vector2D) {
        guard var document = geometryEditorDocument else { return }
        var cutCount = 0
        var selectedPolygonIDs = Set<EditableGeometryID>()
        var selectedCurveIDs = Set<EditableGeometryID>()
        let weldSnapshot = snapshotWeldPoints(in: document)

        let targetLayerID = geometryEditorKnifeCutsAllVisibleLayers ? nil : selectedGeometryEditorLayerID
        guard geometryEditorKnifeCutsAllVisibleLayers || targetLayerID != nil else {
            postStatus("Knife: no selected layer")
            return
        }

        for layerIndex in document.layers.indices {
            guard geometryKnifeCanCutLayer(document.layers[layerIndex], targetLayerID: targetLayerID) else { continue }

            var replacementPolygons: [EditableClosedPolygon] = []
            var polygonIDsToRemove = Set<EditableGeometryID>()
            for polygon in document.layers[layerIndex].polygons {
                guard polygon.isVisible,
                      let pieces = knifePieces(for: polygon, lineStart: lineStart, lineEnd: lineEnd)
                else { continue }
                polygonIDsToRemove.insert(polygon.id)
                replacementPolygons.append(contentsOf: pieces)
                selectedPolygonIDs.formUnion(pieces.map(\.id))
                cutCount += 1
            }
            if !polygonIDsToRemove.isEmpty {
                document.layers[layerIndex].polygons.removeAll { polygonIDsToRemove.contains($0.id) }
                document.layers[layerIndex].polygons.append(contentsOf: replacementPolygons)
            }

            var replacementCurves: [EditableOpenCurve] = []
            var curveIDsToRemove = Set<EditableGeometryID>()
            for curve in document.layers[layerIndex].openCurves {
                guard curve.isVisible,
                      let pieces = knifePieces(for: curve, lineStart: lineStart, lineEnd: lineEnd)
                else { continue }
                curveIDsToRemove.insert(curve.id)
                replacementCurves.append(contentsOf: pieces)
                selectedCurveIDs.formUnion(pieces.map(\.id))
                cutCount += 1
            }
            if !curveIDsToRemove.isEmpty {
                document.layers[layerIndex].openCurves.removeAll { curveIDsToRemove.contains($0.id) }
                document.layers[layerIndex].openCurves.append(contentsOf: replacementCurves)
            }
        }

        guard cutCount > 0 else {
            postStatus("Knife: no geometry crossed")
            return
        }
        recordGeometryEditorUndoSnapshot()
        restoreWelds(from: weldSnapshot, in: &document)
        setGeometryEditorDocument(document)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: selectedGeometryEditorLayerID,
            polygonIDs: selectedPolygonIDs,
            openCurveIDs: selectedCurveIDs
        )
        postStatus("Knife cut \(cutCount) item(s)")
    }

    private func snapshotWeldPoints(in document: EditableGeometryDocument) -> [[GeometryWeldPointSnapshot]] {
        document.weldGroups.compactMap { group in
            let points = group.pointIDs.compactMap { pointID -> GeometryWeldPointSnapshot? in
                guard let position = document.point(id: pointID)?.position else { return nil }
                return GeometryWeldPointSnapshot(id: pointID, position: position)
            }
            return points.count > 1 ? points : nil
        }
    }

    private func restoreWelds(
        from snapshot: [[GeometryWeldPointSnapshot]],
        in document: inout EditableGeometryDocument
    ) {
        guard !snapshot.isEmpty else { return }
        let allPoints = editableGeometryPointReferences(in: document)
        let tolerance = 0.000_08
        for group in snapshot {
            var restoredIDs = Set<EditableGeometryID>()
            for oldPoint in group {
                let matches = allPoints.filter { $0.position.distance(to: oldPoint.position) <= tolerance }
                restoredIDs.formUnion(matches.map(\.id))
            }
            if restoredIDs.count > 1 {
                document.weldPoints(restoredIDs)
            }
        }
        document.pruneWeldGroups()
    }

    private func editableGeometryPointReferences(in document: EditableGeometryDocument) -> [GeometryPointReference] {
        document.layers.flatMap { layer in
            layer.polygons.flatMap { polygon in
                polygon.points.map { GeometryPointReference(id: $0.id, position: $0.position) }
            } +
            layer.openCurves.flatMap { curve in
                curve.points.map { GeometryPointReference(id: $0.id, position: $0.position) }
            } +
            layer.points.map { GeometryPointReference(id: $0.id, position: $0.position) }
        }
    }

    private func geometryKnifeCanCutLayer(
        _ layer: EditableGeometryLayer,
        targetLayerID: EditableGeometryID?
    ) -> Bool {
        let panelLayer = geometryEditorLayers.first { $0.id == layer.id }
        let isVisible = layer.isVisible && (panelLayer?.isVisible ?? true)
        guard isVisible else { return false }

        if geometryEditorKnifeCutsAllVisibleLayers {
            return true
        }

        guard layer.id == targetLayerID else { return false }
        return layer.isEditable && (panelLayer?.isEditable ?? true)
    }

    private func knifePieces(
        for polygon: EditableClosedPolygon,
        lineStart: Vector2D,
        lineEnd: Vector2D
    ) -> [EditableClosedPolygon]? {
        let segments = orderedEditorSegments(for: polygon)
        let intersections = knifeIntersections(
            segments: segments,
            lineStart: lineStart,
            lineEnd: lineEnd
        )
        guard intersections.count >= 2, intersections.count.isMultiple(of: 2) else { return nil }

        var pieces: [EditableClosedPolygon] = []
        for index in intersections.indices {
            let next = intersections.index(after: index) == intersections.endIndex
                ? intersections.startIndex
                : intersections.index(after: index)
            let pieceSegments = buildClosedKnifePiece(
                segments: segments,
                from: intersections[index],
                to: intersections[next]
            )
            guard pieceSegments.count >= 2,
                  let piece = editableClosedPolygon(
                    name: "\(polygon.name) Cut \(pieces.count + 1)",
                    segments: pieceSegments,
                    isVisible: polygon.isVisible
                  )
            else { continue }
            pieces.append(piece)
        }
        return pieces.count >= 2 ? pieces : nil
    }

    private func knifePieces(
        for curve: EditableOpenCurve,
        lineStart: Vector2D,
        lineEnd: Vector2D
    ) -> [EditableOpenCurve]? {
        let segments = orderedEditorSegments(for: curve)
        let intersections = knifeIntersections(
            segments: segments,
            lineStart: lineStart,
            lineEnd: lineEnd
        )
        guard !intersections.isEmpty else { return nil }

        var boundaries: [GeometryKnifeIntersection] = [
            GeometryKnifeIntersection(segmentIndex: 0, t: 0, point: segments[0][0])
        ]
        boundaries.append(contentsOf: intersections)
        boundaries.append(
            GeometryKnifeIntersection(
                segmentIndex: segments.count - 1,
                t: 1,
                point: segments[segments.count - 1][3]
            )
        )

        var pieces: [EditableOpenCurve] = []
        for index in 0..<(boundaries.count - 1) {
            let pieceSegments = buildOpenKnifePiece(
                segments: segments,
                from: boundaries[index],
                to: boundaries[index + 1]
            )
            guard !pieceSegments.isEmpty,
                  let piece = editableOpenCurve(
                    name: "\(curve.name) Cut \(pieces.count + 1)",
                    segments: pieceSegments,
                    isVisible: curve.isVisible
                  )
            else { continue }
            pieces.append(piece)
        }
        return pieces.count >= 2 ? pieces : nil
    }

    private func orderedEditorSegments(for polygon: EditableClosedPolygon) -> [[Vector2D]] {
        let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
        return polygon.segments.compactMap { segment in
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { return nil }
            return [a0, c0, c1, a1]
        }
    }

    private func orderedEditorSegments(for curve: EditableOpenCurve) -> [[Vector2D]] {
        let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
        return curve.segments.compactMap { segment in
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { return nil }
            return [a0, c0, c1, a1]
        }
    }

    private func knifeIntersections(
        segments: [[Vector2D]],
        lineStart: Vector2D,
        lineEnd: Vector2D
    ) -> [GeometryKnifeIntersection] {
        guard segments.count > 0 else { return [] }
        let a = -(lineEnd.y - lineStart.y)
        let b = lineEnd.x - lineStart.x
        let c = -(a * lineStart.x + b * lineStart.y)
        let lineDelta = lineEnd - lineStart
        let lineLengthSquared = lineDelta.x * lineDelta.x + lineDelta.y * lineDelta.y
        guard lineLengthSquared > 1e-12 else { return [] }

        var raw: [GeometryKnifeIntersection] = []
        for (index, segment) in segments.enumerated() {
            let distances = segment.map { a * $0.x + b * $0.y + c }
            findKnifeRoots(
                distances,
                tMin: 0,
                tMax: 1,
                segmentIndex: index,
                segment: segment,
                output: &raw
            )
        }

        let filtered = raw
            .sorted { $0.globalT < $1.globalT }
            .filter { intersection in
                let s = ((intersection.point.x - lineStart.x) * lineDelta.x +
                         (intersection.point.y - lineStart.y) * lineDelta.y) / lineLengthSquared
                return s >= -0.02 && s <= 1.02
            }

        var deduped: [GeometryKnifeIntersection] = []
        for intersection in filtered {
            guard !deduped.contains(where: { abs($0.globalT - intersection.globalT) < 0.015 }) else { continue }
            deduped.append(intersection)
        }
        return deduped
    }

    private func findKnifeRoots(
        _ distances: [Double],
        tMin: Double,
        tMax: Double,
        segmentIndex: Int,
        segment: [Vector2D],
        output: inout [GeometryKnifeIntersection]
    ) {
        let allPositive = distances.allSatisfy { $0 >= 0 }
        let allNegative = distances.allSatisfy { $0 <= 0 }
        if allPositive || allNegative { return }
        if tMax - tMin < 1e-6 {
            let t = (tMin + tMax) / 2
            output.append(
                GeometryKnifeIntersection(
                    segmentIndex: segmentIndex,
                    t: t,
                    point: BezierMath.point(seg: segment, t: t)
                )
            )
            return
        }

        let tMid = (tMin + tMax) / 2
        let d01 = (distances[0] + distances[1]) / 2
        let d12 = (distances[1] + distances[2]) / 2
        let d23 = (distances[2] + distances[3]) / 2
        let d012 = (d01 + d12) / 2
        let d123 = (d12 + d23) / 2
        let d0123 = (d012 + d123) / 2

        findKnifeRoots(
            [distances[0], d01, d012, d0123],
            tMin: tMin,
            tMax: tMid,
            segmentIndex: segmentIndex,
            segment: segment,
            output: &output
        )
        findKnifeRoots(
            [d0123, d123, d23, distances[3]],
            tMin: tMid,
            tMax: tMax,
            segmentIndex: segmentIndex,
            segment: segment,
            output: &output
        )
    }

    private func buildClosedKnifePiece(
        segments: [[Vector2D]],
        from start: GeometryKnifeIntersection,
        to end: GeometryKnifeIntersection
    ) -> [[Vector2D]] {
        var piece = pathSegmentsBetween(segments: segments, from: start, to: end, wraps: true)
        piece.append(BezierMath.connector(from: end.point, to: start.point, cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0)))
        return piece
    }

    private func buildOpenKnifePiece(
        segments: [[Vector2D]],
        from start: GeometryKnifeIntersection,
        to end: GeometryKnifeIntersection
    ) -> [[Vector2D]] {
        pathSegmentsBetween(segments: segments, from: start, to: end, wraps: false)
    }

    private func pathSegmentsBetween(
        segments: [[Vector2D]],
        from start: GeometryKnifeIntersection,
        to end: GeometryKnifeIntersection,
        wraps: Bool
    ) -> [[Vector2D]] {
        guard !segments.isEmpty else { return [] }
        let startIndex = start.segmentIndex
        let endIndex = end.segmentIndex
        var result: [[Vector2D]] = []

        if startIndex == endIndex && start.t < end.t {
            result.append(extractSubCurve(segments[startIndex], from: start.t, to: end.t))
            return result
        }

        result.append(BezierMath.split(seg: segments[startIndex], t: start.t).right)
        var index = startIndex + 1
        while index != endIndex {
            if index >= segments.count {
                guard wraps else { return result }
                index = 0
                if index == endIndex { break }
            }
            result.append(segments[index])
            index += 1
        }
        if segments.indices.contains(endIndex) {
            result.append(BezierMath.split(seg: segments[endIndex], t: end.t).left)
        }
        return result.filter { $0[0].distance(to: $0[3]) > 1e-8 }
    }

    private func extractSubCurve(_ segment: [Vector2D], from t0: Double, to t1: Double) -> [Vector2D] {
        let right = BezierMath.split(seg: segment, t: t0).right
        guard t1 < 1.0 - 1e-9 else { return right }
        let adjusted = (t1 - t0) / (1.0 - t0)
        return BezierMath.split(seg: right, t: adjusted).left
    }

    private func editableClosedPolygon(
        name: String,
        segments: [[Vector2D]],
        pressures: [Double]? = nil,
        isVisible: Bool
    ) -> EditableClosedPolygon? {
        guard segments.count >= 2 else { return nil }
        let firstAnchor = EditableCubicPoint(position: segments[0][0], kind: .anchor)
        var points = [firstAnchor]
        var editableSegments: [EditableCubicSegment] = []
        var previousAnchorID = firstAnchor.id

        for (index, segment) in segments.enumerated() {
            let controlOut = EditableCubicPoint(position: segment[1], kind: .control)
            let controlIn = EditableCubicPoint(position: segment[2], kind: .control)
            let endAnchorID: EditableGeometryID
            if index == segments.count - 1 && segment[3].distance(to: segments[0][0]) < 1e-7 {
                endAnchorID = firstAnchor.id
                points.append(contentsOf: [controlOut, controlIn])
            } else {
                let endAnchor = EditableCubicPoint(position: segment[3], kind: .anchor)
                endAnchorID = endAnchor.id
                points.append(contentsOf: [controlOut, controlIn, endAnchor])
            }
            editableSegments.append(
                EditableCubicSegment(
                    startAnchorID: previousAnchorID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchorID
                )
            )
            previousAnchorID = endAnchorID
        }

        return EditableClosedPolygon(
            name: name,
            points: points,
            segments: editableSegments,
            pressures: pressures ?? Array(repeating: 1.0, count: editableSegments.count),
            isVisible: isVisible
        )
    }

    private func editableOpenCurve(
        name: String,
        segments: [[Vector2D]],
        pressures: [Double]? = nil,
        isVisible: Bool
    ) -> EditableOpenCurve? {
        guard !segments.isEmpty else { return nil }
        let firstAnchor = EditableCubicPoint(position: segments[0][0], kind: .anchor)
        var points = [firstAnchor]
        var editableSegments: [EditableCubicSegment] = []
        var previousAnchorID = firstAnchor.id

        for segment in segments {
            let controlOut = EditableCubicPoint(position: segment[1], kind: .control)
            let controlIn = EditableCubicPoint(position: segment[2], kind: .control)
            let endAnchor = EditableCubicPoint(position: segment[3], kind: .anchor)
            points.append(contentsOf: [controlOut, controlIn, endAnchor])
            editableSegments.append(
                EditableCubicSegment(
                    startAnchorID: previousAnchorID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchor.id
                )
            )
            previousAnchorID = endAnchor.id
        }

        return EditableOpenCurve(
            name: name,
            points: points,
            segments: editableSegments,
            pressures: pressures ?? Array(repeating: 1.0, count: editableSegments.count),
            isVisible: isVisible
        )
    }

    private func selectedWeldPointIDs(in document: EditableGeometryDocument? = nil) -> Set<EditableGeometryID> {
        guard let document = document ?? geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID })
        else { return [] }
        if !geometryEditorSelection.pointIDs.isEmpty {
            return geometryEditorSelection.pointIDs
        }
        if !geometryEditorSelection.segmentIDs.isEmpty {
            return selectedGeometrySegmentPointIDs(in: layer, selection: geometryEditorSelection)
        }
        return selectedGeometryObjectPointIDs(in: layer, selection: geometryEditorSelection)
    }

    private var currentWeldThresholds: GeometryWeldThresholds {
        let value = min(max(geometryEditorWeldTolerance, 0), 1)
        let eased = value * value
        return GeometryWeldThresholds(
            midpointDistance: 0.004 + eased * 0.116,
            endpointPairDistance: 0.006 + eased * 0.194,
            minimumDirectionDot: 0.98 - value * 0.43
        )
    }

    private func canWeldEdges(
        _ first: GeometrySegmentReference,
        _ second: GeometrySegmentReference,
        in document: EditableGeometryDocument,
        thresholds: GeometryWeldThresholds
    ) -> Bool {
        guard let a0 = document.point(id: first.segment.startAnchorID)?.position,
              let a1 = document.point(id: first.segment.endAnchorID)?.position,
              let b0 = document.point(id: second.segment.startAnchorID)?.position,
              let b1 = document.point(id: second.segment.endAnchorID)?.position
        else { return false }
        let midpointA = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)
        let midpointB = Vector2D(x: (b0.x + b1.x) / 2, y: (b0.y + b1.y) / 2)
        guard midpointA.distance(to: midpointB) <= thresholds.midpointDistance else { return false }
        let directionA = a1 - a0
        let directionB = b1 - b0
        let lengthA = directionA.length
        let lengthB = directionB.length
        guard lengthA > 0.0001, lengthB > 0.0001 else { return false }
        let directionDot = abs((directionA.x * directionB.x + directionA.y * directionB.y) / (lengthA * lengthB))
        guard directionDot >= thresholds.minimumDirectionDot else { return false }
        let same = a0.distance(to: b0) + a1.distance(to: b1)
        let reversed = a0.distance(to: b1) + a1.distance(to: b0)
        return min(same, reversed) <= thresholds.endpointPairDistance
    }

    private func areEdgesAlreadyWelded(
        _ first: GeometrySegmentReference,
        _ second: GeometrySegmentReference,
        in document: EditableGeometryDocument
    ) -> Bool {
        let sameStart = document.weldedPointIDs(containing: first.segment.startAnchorID).contains(second.segment.startAnchorID)
        let sameEnd = document.weldedPointIDs(containing: first.segment.endAnchorID).contains(second.segment.endAnchorID)
        let reversedStart = document.weldedPointIDs(containing: first.segment.startAnchorID).contains(second.segment.endAnchorID)
        let reversedEnd = document.weldedPointIDs(containing: first.segment.endAnchorID).contains(second.segment.startAnchorID)
        return (sameStart && sameEnd) || (reversedStart && reversedEnd)
    }

    private func weldEdgePair(
        _ first: GeometrySegmentReference,
        _ second: GeometrySegmentReference,
        in document: inout EditableGeometryDocument
    ) {
        guard let firstStart = document.point(id: first.segment.startAnchorID)?.position,
              let firstEnd = document.point(id: first.segment.endAnchorID)?.position,
              let firstControlOut = document.point(id: first.segment.controlOutID)?.position,
              let firstControlIn = document.point(id: first.segment.controlInID)?.position,
              let secondStart = document.point(id: second.segment.startAnchorID)?.position,
              let secondEnd = document.point(id: second.segment.endAnchorID)?.position,
              let secondControlOut = document.point(id: second.segment.controlOutID)?.position,
              let secondControlIn = document.point(id: second.segment.controlInID)?.position
        else { return }

        let same = firstStart.distance(to: secondStart) + firstEnd.distance(to: secondEnd)
        let reversed = firstStart.distance(to: secondEnd) + firstEnd.distance(to: secondStart)
        let secondMatchesForward = same <= reversed

        let startPartner = secondMatchesForward ? second.segment.startAnchorID : second.segment.endAnchorID
        let endPartner = secondMatchesForward ? second.segment.endAnchorID : second.segment.startAnchorID
        let controlOutPartner = secondMatchesForward ? second.segment.controlOutID : second.segment.controlInID
        let controlInPartner = secondMatchesForward ? second.segment.controlInID : second.segment.controlOutID

        let startPartnerPosition = secondMatchesForward ? secondStart : secondEnd
        let endPartnerPosition = secondMatchesForward ? secondEnd : secondStart
        let controlOutPartnerPosition = secondMatchesForward ? secondControlOut : secondControlIn
        let controlInPartnerPosition = secondMatchesForward ? secondControlIn : secondControlOut

        snapWeldCluster(
            containing: first.segment.startAnchorID,
            to: centre(of: [firstStart, startPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: startPartner,
            to: centre(of: [firstStart, startPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: first.segment.endAnchorID,
            to: centre(of: [firstEnd, endPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: endPartner,
            to: centre(of: [firstEnd, endPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: first.segment.controlOutID,
            to: centre(of: [firstControlOut, controlOutPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: controlOutPartner,
            to: centre(of: [firstControlOut, controlOutPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: first.segment.controlInID,
            to: centre(of: [firstControlIn, controlInPartnerPosition]),
            in: &document
        )
        snapWeldCluster(
            containing: controlInPartner,
            to: centre(of: [firstControlIn, controlInPartnerPosition]),
            in: &document
        )

        document.weldPoints([first.segment.startAnchorID, startPartner])
        document.weldPoints([first.segment.endAnchorID, endPartner])
        document.weldPoints([first.segment.controlOutID, controlOutPartner])
        document.weldPoints([first.segment.controlInID, controlInPartner])
    }

    private func snapWeldCluster(
        containing pointID: EditableGeometryID,
        to position: Vector2D,
        in document: inout EditableGeometryDocument
    ) {
        for weldedID in document.weldedPointIDs(containing: pointID) {
            document.setPointPosition(id: weldedID, to: position)
        }
    }

    func deleteSelectedGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID })
        else { return }

        if geometryEditorSelection.pointIDs.isEmpty && geometryEditorSelection.segmentIDs.isEmpty {
            let selectedPolygons = geometryEditorSelection.polygonIDs
            let selectedCurves = geometryEditorSelection.openCurveIDs
            let selectedStandalonePoints = geometryEditorSelection.standalonePointIDs
            guard !selectedPolygons.isEmpty || !selectedCurves.isEmpty || !selectedStandalonePoints.isEmpty else { return }
            recordGeometryEditorUndoSnapshot()
            document.layers[layerIndex].polygons.removeAll { selectedPolygons.contains($0.id) }
            document.layers[layerIndex].openCurves.removeAll { selectedCurves.contains($0.id) }
            document.layers[layerIndex].points.removeAll { selectedStandalonePoints.contains($0.id) }
            geometryEditorSelection = .empty
            setGeometryEditorDocument(document)
            return
        }

        let selectedStandalonePoints = geometryEditorSelection.pointIDs
        if !selectedStandalonePoints.isEmpty,
           selectedStandalonePoints.allSatisfy({ pointID in document.layers[layerIndex].points.contains { $0.id == pointID } }) {
            recordGeometryEditorUndoSnapshot()
            document.layers[layerIndex].points.removeAll { selectedStandalonePoints.contains($0.id) }
            geometryEditorSelection = .empty
            setGeometryEditorDocument(document)
            return
        }

        if geometryEditorSelection.pointIDs.isEmpty,
           geometryEditorSelection.segmentIDs.count == 2,
           healSelectedInternalPolygonEdges(in: &document, layerIndex: layerIndex) {
            return
        }

        if geometryEditorSelection.pointIDs.count == 1 {
            deleteSelectedGeometryAnchor(in: &document, layerIndex: layerIndex)
            return
        }

        if geometryEditorSelection.segmentIDs.count == 1 {
            deleteSelectedGeometrySegment(in: &document, layerIndex: layerIndex)
        }
    }

    private func healSelectedInternalPolygonEdges(
        in document: inout EditableGeometryDocument,
        layerIndex: Int
    ) -> Bool {
        guard let pair = selectedInternalHealPair(in: document, layerIndex: layerIndex),
              document.layers[layerIndex].polygons.indices.contains(pair.first.itemIndex),
              document.layers[layerIndex].polygons.indices.contains(pair.second.itemIndex)
        else { return false }

        let firstPolygon = document.layers[layerIndex].polygons[pair.first.itemIndex]
        let secondPolygon = document.layers[layerIndex].polygons[pair.second.itemIndex]
        guard let firstBoundary = firstPolygon.deletingSegment(id: pair.first.segment.id),
              let secondBoundary = secondPolygon.deletingSegment(id: pair.second.segment.id),
              let mergedSegments = mergedBoundarySegments(
                first: orderedEditorSegments(for: firstBoundary),
                second: orderedEditorSegments(for: secondBoundary)
              ),
              let mergedPolygon = editableClosedPolygon(
                name: healedPolygonName(firstPolygon.name, secondPolygon.name),
                segments: mergedSegments,
                isVisible: firstPolygon.isVisible || secondPolygon.isVisible
              )
        else { return false }

        let weldSnapshot = snapshotWeldPoints(in: document)
        let selectedLayerID = document.layers[layerIndex].id
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.removeAll { polygon in
            polygon.id == firstPolygon.id || polygon.id == secondPolygon.id
        }
        document.layers[layerIndex].polygons.append(mergedPolygon)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: selectedLayerID,
            polygonIDs: [mergedPolygon.id]
        )
        restoreWelds(from: weldSnapshot, in: &document)
        setGeometryEditorDocument(document)
        postStatus("Healed selected internal edge")
        return true
    }

    private func selectedInternalHealPair(
        in document: EditableGeometryDocument,
        layerIndex: Int
    ) -> (first: GeometrySegmentReference, second: GeometrySegmentReference)? {
        guard document.layers.indices.contains(layerIndex),
              geometryEditorSelection.pointIDs.isEmpty,
              geometryEditorSelection.segmentIDs.count == 2
        else { return nil }

        let selectedSegmentIDs = geometryEditorSelection.segmentIDs
        let references = editableGeometrySegmentReferences(in: document).filter { reference in
            reference.layerIndex == layerIndex &&
            reference.isPolygon &&
            selectedSegmentIDs.contains(reference.segment.id) &&
            geometryEditorSelection.polygonIDs.contains(reference.itemID)
        }
        guard references.count == 2,
              references[0].itemID != references[1].itemID,
              internalHealEdgesMatch(references[0], references[1], in: document.layers[layerIndex])
        else { return nil }
        return (references[0], references[1])
    }

    private func internalHealEdgesMatch(
        _ first: GeometrySegmentReference,
        _ second: GeometrySegmentReference,
        in layer: EditableGeometryLayer
    ) -> Bool {
        guard let firstEndpoints = segmentEndpoints(first, in: layer),
              let secondEndpoints = segmentEndpoints(second, in: layer)
        else { return false }

        let tolerance = max(0.001, currentWeldThresholds.endpointPairDistance * 0.2)
        let same = firstEndpoints.start.distance(to: secondEndpoints.start) +
            firstEndpoints.end.distance(to: secondEndpoints.end)
        let reversed = firstEndpoints.start.distance(to: secondEndpoints.end) +
            firstEndpoints.end.distance(to: secondEndpoints.start)
        return min(same, reversed) <= tolerance
    }

    private func segmentEndpoints(
        _ reference: GeometrySegmentReference,
        in layer: EditableGeometryLayer
    ) -> GeometrySegmentEndpoints? {
        guard reference.isPolygon,
              layer.polygons.indices.contains(reference.itemIndex)
        else { return nil }
        let polygon = layer.polygons[reference.itemIndex]
        guard let start = polygon.point(id: reference.segment.startAnchorID)?.position,
              let end = polygon.point(id: reference.segment.endAnchorID)?.position
        else { return nil }
        return GeometrySegmentEndpoints(start: start, end: end)
    }

    private func mergedBoundarySegments(
        first: [[Vector2D]],
        second: [[Vector2D]]
    ) -> [[Vector2D]]? {
        let candidates = [
            (first, second),
            (first, reversedPathSegments(second)),
            (reversedPathSegments(first), second),
            (reversedPathSegments(first), reversedPathSegments(second))
        ]
        let tolerance = 0.002
        for (firstPath, secondPath) in candidates {
            guard let firstStart = firstPath.first?.first,
                  let firstEnd = firstPath.last?.last,
                  let secondStart = secondPath.first?.first,
                  let secondEnd = secondPath.last?.last
            else { continue }
            if firstEnd.distance(to: secondStart) <= tolerance &&
                secondEnd.distance(to: firstStart) <= tolerance {
                return firstPath + secondPath
            }
        }
        return nil
    }

    private func reversedPathSegments(_ segments: [[Vector2D]]) -> [[Vector2D]] {
        segments.reversed().map { segment in
            guard segment.count == 4 else { return segment }
            return [segment[3], segment[2], segment[1], segment[0]]
        }
    }

    private func healedPolygonName(_ first: String, _ second: String) -> String {
        guard first != second else { return "\(first) Healed" }
        return "\(first) + \(second)"
    }

    private func deleteSelectedGeometryAnchor(in document: inout EditableGeometryDocument, layerIndex: Int) {
        guard let pointID = geometryEditorSelection.pointIDs.first,
              let polygonID = geometryEditorSelection.polygonIDs.first,
              let polygonIndex = document.layers[layerIndex].polygons.firstIndex(where: { $0.id == polygonID }),
              let result = document.layers[layerIndex].polygons[polygonIndex].deletingAnchor(id: pointID)
        else { return }

        recordGeometryEditorUndoSnapshot()
        switch result {
        case .closedPolygon(let polygon):
            document.layers[layerIndex].polygons[polygonIndex] = polygon
        case .openCurve(let curve):
            document.layers[layerIndex].polygons.remove(at: polygonIndex)
            document.layers[layerIndex].openCurves.append(curve)
        }
        geometryEditorSelection = .empty
        setGeometryEditorDocument(document)
    }

    private func deleteSelectedGeometrySegment(in document: inout EditableGeometryDocument, layerIndex: Int) {
        guard let segmentID = geometryEditorSelection.segmentIDs.first,
              let polygonID = geometryEditorSelection.polygonIDs.first,
              let polygonIndex = document.layers[layerIndex].polygons.firstIndex(where: { $0.id == polygonID }),
              let curve = document.layers[layerIndex].polygons[polygonIndex].deletingSegment(id: segmentID)
        else { return }

        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.remove(at: polygonIndex)
        document.layers[layerIndex].openCurves.append(curve)
        geometryEditorSelection = .empty
        setGeometryEditorDocument(document)
    }

    func deleteAllLayerGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = selectedGeometryEditorLayerID ?? geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              canDeleteAllLayerGeometry
        else { postStatus("Delete All: no active editable layer with geometry"); return }
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.removeAll()
        document.layers[layerIndex].openCurves.removeAll()
        document.layers[layerIndex].points.removeAll()
        geometryEditorSelection = .empty
        setGeometryEditorDocument(document)
        postStatus("Deleted all geometry in layer")
    }

    private func pruneGeometryEditorSelection(in document: EditableGeometryDocument) {
        guard let layerID = geometryEditorSelection.layerID,
              let layer = document.layers.first(where: { $0.id == layerID }),
              layer.isVisible,
              layer.isEditable
        else {
            geometryEditorSelection = .empty
            return
        }
        let polygonIDs = Set(layer.polygons.map(\.id))
        let openCurveIDs = Set(layer.openCurves.map(\.id))
        let standalonePointIDs = Set(layer.points.map(\.id))
        var pointIDs = Set<EditableGeometryID>()
        var segmentIDs = Set<EditableGeometryID>()
        for polygon in layer.polygons where geometryEditorSelection.polygonIDs.contains(polygon.id) {
            pointIDs.formUnion(polygon.points.map(\.id))
            segmentIDs.formUnion(polygon.segments.map(\.id))
        }
        for curve in layer.openCurves where geometryEditorSelection.openCurveIDs.contains(curve.id) {
            pointIDs.formUnion(curve.points.map(\.id))
            segmentIDs.formUnion(curve.segments.map(\.id))
        }
        pointIDs.formUnion(standalonePointIDs)
        geometryEditorSelection.polygonIDs.formIntersection(polygonIDs)
        geometryEditorSelection.openCurveIDs.formIntersection(openCurveIDs)
        geometryEditorSelection.standalonePointIDs.formIntersection(standalonePointIDs)
        geometryEditorSelection.pointIDs.formIntersection(pointIDs)
        geometryEditorSelection.segmentIDs.formIntersection(segmentIDs)
        if geometryEditorSelection.polygonIDs.isEmpty &&
            geometryEditorSelection.openCurveIDs.isEmpty &&
            geometryEditorSelection.standalonePointIDs.isEmpty &&
            geometryEditorSelection.pointIDs.isEmpty {
            geometryEditorSelection = .empty
        }
    }

    // MARK: - Extrude implementation

    // Collects segments to extrude from the current selection using two distinct modes:
    //
    // • Segment-priority (segmentIDs non-empty): uses only the explicitly listed segment IDs,
    //   searching all editable polygons and open curves regardless of whether their parent
    //   object is in polygonIDs/openCurveIDs. This makes chained extrusion work correctly —
    //   after an extrude the auto-selected top edges are in segmentIDs, so the next extrude
    //   only extends those edges rather than all four sides of the newly created quads.
    //
    // • Whole-object (segmentIDs empty): expands to every edge of every polygon in
    //   polygonIDs and every open curve in openCurveIDs. This is the "3D" path — the user
    //   switches to Polygons mode, selects the quads (no explicit edge selection), and
    //   extruding all four sides produces a volumetric shape.
    private func extrudeSourceSegments(
        in document: EditableGeometryDocument
    ) -> [GeometrySegmentReference] {
        guard let layerID = geometryEditorSelection.layerID else { return [] }
        let sel = geometryEditorSelection
        var refs: [GeometrySegmentReference] = []
        var seen = Set<EditableGeometryID>()

        for layerIndex in document.layers.indices {
            let layer = document.layers[layerIndex]
            guard layer.id == layerID, layer.isVisible, layer.isEditable else { continue }

            if sel.segmentIDs.isEmpty {
                // Whole-object expansion: all edges of selected polygons
                for polygonIndex in layer.polygons.indices {
                    let polygon = layer.polygons[polygonIndex]
                    guard sel.polygonIDs.contains(polygon.id) else { continue }
                    for segIdx in polygon.segments.indices {
                        let seg = polygon.segments[segIdx]
                        if seen.insert(seg.id).inserted {
                            refs.append(GeometrySegmentReference(
                                layerIndex: layerIndex, isPolygon: true,
                                itemIndex: polygonIndex, segmentIndex: segIdx,
                                layerID: layer.id, itemID: polygon.id, segment: seg
                            ))
                        }
                    }
                }
                // Whole-object expansion: all edges of selected open curves
                for curveIndex in layer.openCurves.indices {
                    let curve = layer.openCurves[curveIndex]
                    guard sel.openCurveIDs.contains(curve.id) else { continue }
                    for segIdx in curve.segments.indices {
                        let seg = curve.segments[segIdx]
                        if seen.insert(seg.id).inserted {
                            refs.append(GeometrySegmentReference(
                                layerIndex: layerIndex, isPolygon: false,
                                itemIndex: curveIndex, segmentIndex: segIdx,
                                layerID: layer.id, itemID: curve.id, segment: seg
                            ))
                        }
                    }
                }
            } else {
                // Segment-priority: search every editable polygon and open curve for
                // segment IDs that appear in the explicit selection, regardless of whether
                // the parent object is also in polygonIDs/openCurveIDs.
                for polygonIndex in layer.polygons.indices {
                    let polygon = layer.polygons[polygonIndex]
                    for segIdx in polygon.segments.indices {
                        let seg = polygon.segments[segIdx]
                        guard sel.segmentIDs.contains(seg.id),
                              seen.insert(seg.id).inserted else { continue }
                        refs.append(GeometrySegmentReference(
                            layerIndex: layerIndex, isPolygon: true,
                            itemIndex: polygonIndex, segmentIndex: segIdx,
                            layerID: layer.id, itemID: polygon.id, segment: seg
                        ))
                    }
                }
                for curveIndex in layer.openCurves.indices {
                    let curve = layer.openCurves[curveIndex]
                    for segIdx in curve.segments.indices {
                        let seg = curve.segments[segIdx]
                        guard sel.segmentIDs.contains(seg.id),
                              seen.insert(seg.id).inserted else { continue }
                        refs.append(GeometrySegmentReference(
                            layerIndex: layerIndex, isPolygon: false,
                            itemIndex: curveIndex, segmentIndex: segIdx,
                            layerID: layer.id, itemID: curve.id, segment: seg
                        ))
                    }
                }
            }
        }
        return refs
    }

    private func makeExtrudeQuad(
        oA0: Vector2D, oC1: Vector2D, oC2: Vector2D, oA3: Vector2D,
        lA0: Vector2D, lC1: Vector2D, lC2: Vector2D, lA3: Vector2D,
        name: String
    ) -> EditableClosedPolygon {
        func lerp(_ a: Vector2D, _ b: Vector2D, _ t: Double) -> Vector2D { a + (b - a) * t }

        // Anchors
        let pOA0 = EditableCubicPoint(position: oA0, kind: .anchor)
        let pOA3 = EditableCubicPoint(position: oA3, kind: .anchor)
        let pLA3 = EditableCubicPoint(position: lA3, kind: .anchor)
        let pLA0 = EditableCubicPoint(position: lA0, kind: .anchor)

        // Segment 0: bottom — original edge forward
        let pBC1 = EditableCubicPoint(position: oC1, kind: .control)
        let pBC2 = EditableCubicPoint(position: oC2, kind: .control)

        // Segment 1: right connector — straight oA3 → lA3
        let pRC1 = EditableCubicPoint(position: lerp(oA3, lA3, 1.0 / 3.0), kind: .control)
        let pRC2 = EditableCubicPoint(position: lerp(oA3, lA3, 2.0 / 3.0), kind: .control)

        // Segment 2: top — displaced edge reversed (lA3 → lA0 using lC2, lC1)
        let pTC1 = EditableCubicPoint(position: lC2, kind: .control)
        let pTC2 = EditableCubicPoint(position: lC1, kind: .control)

        // Segment 3: left connector — straight lA0 → oA0
        let pLC1 = EditableCubicPoint(position: lerp(lA0, oA0, 1.0 / 3.0), kind: .control)
        let pLC2 = EditableCubicPoint(position: lerp(lA0, oA0, 2.0 / 3.0), kind: .control)

        let seg0 = EditableCubicSegment(startAnchorID: pOA0.id, controlOutID: pBC1.id, controlInID: pBC2.id, endAnchorID: pOA3.id)
        let seg1 = EditableCubicSegment(startAnchorID: pOA3.id, controlOutID: pRC1.id, controlInID: pRC2.id, endAnchorID: pLA3.id)
        let seg2 = EditableCubicSegment(startAnchorID: pLA3.id, controlOutID: pTC1.id, controlInID: pTC2.id, endAnchorID: pLA0.id)
        let seg3 = EditableCubicSegment(startAnchorID: pLA0.id, controlOutID: pLC1.id, controlInID: pLC2.id, endAnchorID: pOA0.id)

        return EditableClosedPolygon(
            name: name,
            points: [pOA0, pBC1, pBC2, pOA3, pRC1, pRC2, pLA3, pTC1, pTC2, pLA0, pLC1, pLC2],
            segments: [seg0, seg1, seg2, seg3]
        )
    }

    private func performGeometryDisplacementExtrude(delta: Vector2D) {
        guard var document = geometryEditorDocument else { return }
        let sources = extrudeSourceSegments(in: document)
        guard !sources.isEmpty else { return }

        var pairs: [(source: GeometrySegmentReference, quad: EditableClosedPolygon)] = []
        for source in sources {
            guard let oA0 = document.point(id: source.segment.startAnchorID)?.position,
                  let oC1 = document.point(id: source.segment.controlOutID)?.position,
                  let oC2 = document.point(id: source.segment.controlInID)?.position,
                  let oA3 = document.point(id: source.segment.endAnchorID)?.position
            else { continue }
            pairs.append((source, makeExtrudeQuad(
                oA0: oA0, oC1: oC1, oC2: oC2, oA3: oA3,
                lA0: oA0 + delta, lC1: oC1 + delta, lC2: oC2 + delta, lA3: oA3 + delta,
                name: "Extrude Quad"
            )))
        }
        commitExtrudeQuads(pairs: pairs, into: &document, statusPrefix: "Displacement extrude")
    }

    private func performGeometryScaleExtrude(factor: Double) {
        guard var document = geometryEditorDocument else { return }
        let sources = extrudeSourceSegments(in: document)
        guard !sources.isEmpty else { return }

        var anchorPositions: [Vector2D] = []
        for source in sources {
            if let p = document.point(id: source.segment.startAnchorID)?.position { anchorPositions.append(p) }
            if let p = document.point(id: source.segment.endAnchorID)?.position   { anchorPositions.append(p) }
        }
        guard !anchorPositions.isEmpty else { return }
        let centroid = anchorPositions.reduce(.zero, +) * (1.0 / Double(anchorPositions.count))

        var pairs: [(source: GeometrySegmentReference, quad: EditableClosedPolygon)] = []
        for source in sources {
            guard let oA0 = document.point(id: source.segment.startAnchorID)?.position,
                  let oC1 = document.point(id: source.segment.controlOutID)?.position,
                  let oC2 = document.point(id: source.segment.controlInID)?.position,
                  let oA3 = document.point(id: source.segment.endAnchorID)?.position
            else { continue }
            func sc(_ p: Vector2D) -> Vector2D { centroid + (p - centroid) * factor }
            pairs.append((source, makeExtrudeQuad(
                oA0: oA0, oC1: oC1, oC2: oC2, oA3: oA3,
                lA0: sc(oA0), lC1: sc(oC1), lC2: sc(oC2), lA3: sc(oA3),
                name: "Scale Extrude Quad"
            )))
        }
        commitExtrudeQuads(pairs: pairs, into: &document,
                           statusPrefix: String(format: "Scale extrude ×%.2f", factor))
    }

    // Shared commit for both extrude modes:
    // • welds each quad's bottom anchors to its source polygon anchors
    // • welds adjacent quads' top-edge corner anchors wherever two source edges shared an original anchor
    // • records one undo snapshot (pre-mutation), then publishes the new document
    private func commitExtrudeQuads(
        pairs: [(source: GeometrySegmentReference, quad: EditableClosedPolygon)],
        into document: inout EditableGeometryDocument,
        statusPrefix: String
    ) {
        guard !pairs.isEmpty else { return }

        // Bottom-to-source welds and layer insertion
        for (source, quad) in pairs {
            if source.isPolygon {
                document.weldPoints([source.segment.startAnchorID, quad.segments[0].startAnchorID])
                document.weldPoints([source.segment.endAnchorID,   quad.segments[0].endAnchorID])
            }
            document.layers[source.layerIndex].polygons.append(quad)
        }

        // Adjacent top-corner welds:
        // seg[2] of the quad is the top edge, running from pLA3 (= oA3 displaced) to pLA0 (= oA0 displaced).
        // Two quads from neighbouring edges share the same original anchor at their junction.
        // Collect all top-corner anchor IDs keyed by the original anchor they were derived from,
        // then weld any bucket that received more than one entry.
        var originToTopIDs: [EditableGeometryID: [EditableGeometryID]] = [:]
        for (source, quad) in pairs {
            // seg[2].startAnchorID = pLA3, derived from source.segment.endAnchorID (oA3)
            originToTopIDs[source.segment.endAnchorID, default: []].append(quad.segments[2].startAnchorID)
            // seg[2].endAnchorID = pLA0, derived from source.segment.startAnchorID (oA0)
            originToTopIDs[source.segment.startAnchorID, default: []].append(quad.segments[2].endAnchorID)
        }
        for topIDs in originToTopIDs.values where topIDs.count > 1 {
            document.weldPoints(Set(topIDs))
        }

        let newPolygonIDs = Set(pairs.map(\.quad.id))
        let newSegmentIDs = Set(pairs.map { $0.quad.segments[2].id })

        recordGeometryEditorUndoSnapshot()
        setGeometryEditorDocument(document)
        geometryEditorTool = .edges
        geometryEditorSelection = EditableGeometrySelection(
            layerID: selectedGeometryEditorLayerID,
            polygonIDs: newPolygonIDs,
            segmentIDs: newSegmentIDs
        )
        postStatus("\(statusPrefix): \(pairs.count) edge(s)")
    }

    private func selectedGeometrySegmentReferences(
        in document: EditableGeometryDocument
    ) -> [GeometrySegmentReference] {
        guard let layerID = geometryEditorSelection.layerID,
              !geometryEditorSelection.segmentIDs.isEmpty
        else { return [] }
        return editableGeometrySegmentReferences(in: document).filter { reference in
            reference.layerID == layerID &&
            geometryEditorSelection.segmentIDs.contains(reference.segment.id) &&
            (
                geometryEditorSelection.polygonIDs.contains(reference.itemID) ||
                geometryEditorSelection.openCurveIDs.contains(reference.itemID)
            )
        }
    }

    private func editableGeometrySegmentReferences(
        in document: EditableGeometryDocument
    ) -> [GeometrySegmentReference] {
        var references: [GeometrySegmentReference] = []
        for layerIndex in document.layers.indices {
            let layer = document.layers[layerIndex]
            guard layer.isVisible, layer.isEditable else { continue }
            for polygonIndex in layer.polygons.indices {
                let polygon = layer.polygons[polygonIndex]
                for segmentIndex in polygon.segments.indices {
                    references.append(
                        GeometrySegmentReference(
                            layerIndex: layerIndex,
                            isPolygon: true,
                            itemIndex: polygonIndex,
                            segmentIndex: segmentIndex,
                            layerID: layer.id,
                            itemID: polygon.id,
                            segment: polygon.segments[segmentIndex]
                        )
                    )
                }
            }
            for curveIndex in layer.openCurves.indices {
                let curve = layer.openCurves[curveIndex]
                for segmentIndex in curve.segments.indices {
                    references.append(
                        GeometrySegmentReference(
                            layerIndex: layerIndex,
                            isPolygon: false,
                            itemIndex: curveIndex,
                            segmentIndex: segmentIndex,
                            layerID: layer.id,
                            itemID: curve.id,
                            segment: curve.segments[segmentIndex]
                        )
                    )
                }
            }
        }
        return references
    }

    private func applyLayerPanelState(to document: inout EditableGeometryDocument) {
        let panelState = Dictionary(uniqueKeysWithValues: geometryEditorLayers.map { ($0.id, $0) })
        var updatedLayers = document.layers.map { layer in
            guard let state = panelState[layer.id] else { return layer }
            var updated = layer
            updated.name = state.name
            updated.isVisible = state.isVisible
            updated.isEditable = state.isEditable
            return updated
        }
        let panelOrder = Dictionary(uniqueKeysWithValues: geometryEditorLayers.enumerated().map { ($0.element.id, $0.offset) })
        updatedLayers.sort {
            (panelOrder[$0.id] ?? Int.max) < (panelOrder[$1.id] ?? Int.max)
        }
        document.layers = updatedLayers
    }

    private func geometryEditorDocumentForLayerMutation() -> EditableGeometryDocument? {
        guard var document = geometryEditorDocument else { return nil }
        document.ensureActiveLayer()
        if let selectedGeometryEditorLayerID,
           document.layers.contains(where: { $0.id == selectedGeometryEditorLayerID }) {
            document.activeLayerID = selectedGeometryEditorLayerID
        }
        return document
    }

    private var selectedGeometryEditorLayerCanEdit: Bool {
        guard let id = selectedGeometryEditorLayerID else { return false }
        return layerCanEdit(id)
    }

    var selectedGeometryEditorLayerCanEditForUI: Bool {
        selectedGeometryEditorLayerCanEdit
    }

    private func layerCanEdit(_ id: EditableGeometryID) -> Bool {
        guard let layer = geometryEditorDocument?.layers.first(where: { $0.id == id }) else { return false }
        return layer.isVisible && layer.isEditable
    }

    private func uniquePolygonSetName(_ name: String, excluding oldName: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "New_Polygon_Set" : trimmed
        let existing = Set(projectConfig?.polygonConfig.library.polygonSets
            .map(\.name)
            .filter { $0 != oldName } ?? [])
        guard existing.contains(base) else { return base }
        var suffix = 2
        var candidate = "\(base)_\(suffix)"
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(base)_\(suffix)"
        }
        return candidate
    }

    private func sanitizedGeometryFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "geometry" : sanitized
    }

    /// Reload the engine from disk (for callers that already have the config persisted).
    private func scheduleEngineReload() {
        configCommitItem?.cancel()
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

    func createProject(named rawName: String) {
        let name = sanitizedProjectName(rawName)
        guard !name.isEmpty else {
            loadError = "Enter a project name."
            return
        }
        let url = Self.defaultProjectsDirectory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            loadError = "A project named \(name) already exists."
            return
        }
        createProject(at: url, name: name)
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

    private func createProject(at url: URL, name: String? = nil) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let topLevel = [
                "polygonSets", "curveSets", "pointSets", "ovalSets", "regularPolygons",
                "background_image", "brushes", "configuration", "morphTargets",
                "palettes", "stamps", "svgs"
            ]
            for folder in topLevel {
                try FileManager.default.createDirectory(
                    at: url.appendingPathComponent(folder),
                    withIntermediateDirectories: true
                )
            }
            // SVG sprite sprites live inside the svgs/ hub alongside geometry exports.
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("svgs/sprites"),
                withIntermediateDirectories: true
            )
            let renders = url.appendingPathComponent("renders")
            for sub in ["stills", "animations"] {
                try FileManager.default.createDirectory(
                    at: renders.appendingPathComponent(sub),
                    withIntermediateDirectories: true
                )
            }
            DefaultBrushes.write(to: url.appendingPathComponent("brushes"))
            var config = ProjectConfig()
            if let name {
                config.globalConfig.name = name
            }
            try ProjectLoader.save(config, to: url)
            open(projectDirectory: url)
        } catch {
            loadError = "Could not create project: \(error.localizedDescription)"
            LoomLogger.error("Could not create project at \(url.path)", error: error)
        }
    }

    private func sanitizedProjectName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars).replacingOccurrences(of: " ", with: "_")
    }

    /// Rename the current project directory on disk.
    /// Returns nil on success or a user-facing error string on failure.
    /// All internal asset references use relative paths and are unaffected.
    /// backgroundImagePath is rewritten if the image lives inside the project.
    @discardableResult
    func renameProject(to newName: String) -> String? {
        guard let oldURL = projectURL else { return "No project is open." }
        let sanitized = sanitizedProjectName(newName)
        guard !sanitized.isEmpty else { return "Name cannot be empty." }
        guard sanitized != oldURL.lastPathComponent else { return nil }
        let newURL = oldURL.deletingLastPathComponent()
                          .appendingPathComponent(sanitized, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            return "A project named \"\(sanitized)\" already exists in this folder."
        }
        // Flush any pending debounced save before moving the directory.
        saveNow()
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            return "Could not rename: \(error.localizedDescription)"
        }
        projectURL = newURL
        // Fix backgroundImagePath if the image was inside the old project directory.
        let oldPrefix = oldURL.path + "/"
        let newPrefix = newURL.path + "/"
        updateProjectConfig { cfg in
            cfg.globalConfig.name = sanitized
            if cfg.globalConfig.backgroundImagePath.hasPrefix(oldPrefix) {
                cfg.globalConfig.backgroundImagePath =
                    newPrefix + cfg.globalConfig.backgroundImagePath.dropFirst(oldPrefix.count)
            }
        }
        // Update the recents list to point at the new path.
        recentProjects.removeAll { $0 == oldURL }
        addToRecent(newURL)
        LoomLogger.info("Renamed project \"\(oldURL.lastPathComponent)\" -> \"\(sanitized)\"")
        return nil
    }

    func open(projectDirectory: URL) {
        LoomLogger.info("Opening project: \(projectDirectory.path)")
        projectURL         = projectDirectory
        loadError          = nil
        animationCompleted = false
        loadEngine(from: projectDirectory)
        tryAutoRelinkAllMissing()
        playbackState = .stopped
        addToRecent(projectDirectory)
        startSentinelTimer()
        clearSelections()
    }

    func reload() {
        guard let url = projectURL else { return }
        LoomLogger.info("Reloading project: \(url.path)")
        loadError          = nil
        animationCompleted = false
        loadEngine(from: url)
        tryAutoRelinkAllMissing()
        playbackState = .stopped
    }

    // MARK: - Scrub

    /// Upper bound for the scrub slider.
    /// Falls back to 300 (10 s at 30 fps) when the project has no fixed end frame.
    var maxScrubFrames: Int {
        max(engine?.maxAnimationFrames ?? 0, 300)
    }

    var canPlay: Bool {
        engine?.globalConfig.animating == true
    }

    // MARK: - Playback

    func play() {
        guard engine != nil else { return }
        guard canPlay else {
            playbackState = .stopped
            return
        }
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
        if loopPlayback {
            play()
        } else {
            // Use .paused so the timer stops but the canvas is preserved for the user to see.
            playbackState = .paused
        }
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
        if let error {
            LoomLogger.error("Export ended with error", error: error)
        } else {
            LoomLogger.info("Export ended successfully")
        }
        isExporting = false
    }

    // MARK: - Still export (toolbar button)

    func saveSVG() {
        guard let engine = engine else { return }
        let name = engine.globalConfig.name.isEmpty
            ? (projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType(filenameExtension: "svg") ?? .data]
        panel.nameFieldStringValue = "\(name)_\(f.string(from: Date())).svg"
        if let base = projectURL {
            panel.directoryURL = base.appendingPathComponent("svgs")
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SVGExporter.exportSVG(engine: engine, to: url)
                LoomLogger.info("Saved SVG: \(url.path)")
            } catch {
                LoomLogger.error("SVG export failed", error: error)
            }
            self?.lastRenderOutputType = .still
        }
    }

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
            do {
                try StillExporter.exportPNG(engine: engine, to: url)
                LoomLogger.info("Saved still: \(url.path)")
            } catch {
                LoomLogger.error("Still export failed", error: error)
            }
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

    // MARK: - Render collector

    var allRendersDirectory: URL {
        Self.defaultProjectsDirectory.appendingPathComponent("All")
    }

    var allRendersDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: allRendersDirectory.path)
    }

    func collectRenders() {
        guard !isCollectingRenders else { return }
        isCollectingRenders = true
        appStatusMessage = "Scanning projects…"

        let projectsDir = Self.defaultProjectsDirectory
        let allStills   = allRendersDirectory.appendingPathComponent("stills")
        let allAnims    = allRendersDirectory.appendingPathComponent("animations")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let fm = FileManager.default

            do {
                try fm.createDirectory(at: allStills, withIntermediateDirectories: true)
                try fm.createDirectory(at: allAnims,  withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    self.appStatusMessage    = "Error creating All: \(error.localizedDescription)"
                    self.isCollectingRenders = false
                }
                return
            }

            guard let entries = try? fm.contentsOfDirectory(
                at: projectsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    self.appStatusMessage    = "Could not read \(projectsDir.lastPathComponent)"
                    self.isCollectingRenders = false
                }
                return
            }

            let projectDirs = entries
                .filter {
                    $0.lastPathComponent != "All" &&
                    ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
                }
                .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

            let stillExts: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "heic"]
            let animExts:  Set<String> = ["mp4", "mov", "gif"]

            var movedStills: Int   = 0
            var movedAnims:  Int   = 0
            var stillBytes:  Int64 = 0
            var animBytes:   Int64 = 0
            var skipped:     Int   = 0

            func filesIn(_ dir: URL, exts: Set<String>) -> [(url: URL, date: Date, size: Int64)] {
                guard let items = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { return [] }
                return items.compactMap { u in
                    guard exts.contains(u.pathExtension.lowercased()) else { return nil }
                    let rv   = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let date = rv?.contentModificationDate ?? Date.distantPast
                    let size = Int64(rv?.fileSize ?? 0)
                    return (u, date, size)
                }.sorted { $0.date < $1.date }
            }

            func nextIndex(prefix: String, in destDir: URL) -> Int {
                guard let existing = try? fm.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
                else { return 1 }
                let needle = prefix + "_"
                let maxIdx = existing.compactMap { f -> Int? in
                    let stem = f.deletingPathExtension().lastPathComponent
                    guard stem.hasPrefix(needle) else { return nil }
                    return Int(stem.dropFirst(needle.count))
                }.max() ?? 0
                return maxIdx + 1
            }

            for projDir in projectDirs {
                let projName = projDir.lastPathComponent
                let renders  = projDir.appendingPathComponent("renders")

                // Stills
                var si = nextIndex(prefix: projName, in: allStills)
                for sub in ["stills", "still"] {
                    let dir = renders.appendingPathComponent(sub)
                    guard fm.fileExists(atPath: dir.path) else { continue }
                    for f in filesIn(dir, exts: stillExts) {
                        let dest = allStills.appendingPathComponent(
                            String(format: "%@_%04d.%@", projName, si, f.url.pathExtension.lowercased()))
                        if (try? fm.moveItem(at: f.url, to: dest)) != nil {
                            movedStills += 1; stillBytes += f.size; si += 1
                        } else { skipped += 1 }
                    }
                    break
                }

                // Animations
                var ai = nextIndex(prefix: projName, in: allAnims)
                for sub in ["animations", "animation"] {
                    let dir = renders.appendingPathComponent(sub)
                    guard fm.fileExists(atPath: dir.path) else { continue }
                    for f in filesIn(dir, exts: animExts) {
                        let dest = allAnims.appendingPathComponent(
                            String(format: "%@_%04d.%@", projName, ai, f.url.pathExtension.lowercased()))
                        if (try? fm.moveItem(at: f.url, to: dest)) != nil {
                            movedAnims += 1; animBytes += f.size; ai += 1
                        } else { skipped += 1 }
                    }
                    break
                }
            }

            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useKB, .useMB, .useGB]
            fmt.countStyle   = .file
            var msg: String
            if movedStills == 0 && movedAnims == 0 {
                msg = "Nothing to collect — no renders found, or all are already in All."
            } else {
                msg = "Collected: \(movedStills) still\(movedStills == 1 ? "" : "s") (\(fmt.string(fromByteCount: stillBytes))), "
                    + "\(movedAnims) animation\(movedAnims == 1 ? "" : "s") (\(fmt.string(fromByteCount: animBytes)))"
                if skipped > 0 {
                    msg += "\n\(skipped) file\(skipped == 1 ? "" : "s") could not be moved"
                }
            }

            await MainActor.run {
                self.appStatusMessage    = msg
                self.isCollectingRenders = false
            }
        }
    }

    // MARK: - Recent projects

    func removeFromRecent(_ url: URL) {
        recentProjects.removeAll { $0 == url }
        persistRecentProjects()
    }

    // MARK: - Geometry CRUD

    func createGeometry(folder: String) {
        switch folder {
        case "polygonSets":
            createPolygonSetGeometry()
        default:
            break
        }
    }

    private func createPolygonSetGeometry() {
        guard projectURL != nil else { return }
        var createdName: String?
        updateProjectConfig { cfg in
            let existing = Set(cfg.polygonConfig.library.polygonSets.map(\.name))
            let base = "New_Polygon_Set"
            var candidate = base
            var suffix = 1
            while existing.contains(candidate) {
                suffix += 1
                candidate = "\(base)_\(suffix)"
            }
            cfg.polygonConfig.library.polygonSets.append(
                PolygonSetDef(
                    name: candidate,
                    folder: "polygonSets",
                    filename: "",
                    polygonType: .splinePolygon
                )
            )
            createdName = candidate
        }
        if let createdName {
            selectedTab = .geometry
            selectedGeometryKey = "polygonSets/\(createdName)"
            enterGeometryEditor()
            var document = EditableGeometryDocument(name: createdName)
            document.ensureActiveLayer()
            setGeometryEditorDocument(document, resetHistory: true, cleanSource: .loaded)
        }
    }

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
                    let ext = URL(fileURLWithPath: def.filename).pathExtension
                    let newFilename = "\(def.name).\(ext.isEmpty ? "xml" : ext)"
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

    /// Import an SVG file and convert its path geometry into a new polygon set.
    /// All styling is stripped; only Bézier curves and straight segments are kept.
    /// Each SVG subpath becomes a `<polygon>` in the polygon set.
    func importSVGGeometry(from sourceURL: URL) {
        guard let projectURL = projectURL else { return }
        let stem      = sourceURL.deletingPathExtension().lastPathComponent
        let baseName  = stem.isEmpty ? "imported_svg" : stem
        let finalName = uniquePolygonSetName(baseName, excluding: "")
        let filename  = "\(sanitizedGeometryFilename(finalName)).xml"
        let directory = projectURL.appendingPathComponent("polygonSets", isDirectory: true)
        let destURL   = directory.appendingPathComponent(filename)
        do {
            let xml = try LoomSVGImporter.importPolygonSetXML(from: sourceURL)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try xml.write(to: destURL, atomically: true, encoding: .utf8)
            updateProjectConfig { cfg in
                let def = PolygonSetDef(
                    name: finalName,
                    folder: "polygonSets",
                    filename: filename,
                    polygonType: .splinePolygon
                )
                cfg.polygonConfig.library.polygonSets.append(def)
            }
            selectedGeometryKey = "polygonSets/\(finalName)"
            appStatusMessage = "SVG imported: \(finalName)"
        } catch {
            appStatusMessage = "SVG import failed: \(error.localizedDescription)"
            LoomLogger.error("Failed to import SVG geometry from \(sourceURL.lastPathComponent)", error: error)
        }
    }

    func importGeometry(from sourceURL: URL) {
        guard let projectURL = projectURL else { return }
        let stem     = sourceURL.deletingPathExtension().lastPathComponent
        let ext      = sourceURL.pathExtension
        let baseName = stem.isEmpty ? "imported_geometry" : stem
        let finalName    = uniquePolygonSetName(baseName, excluding: "")
        let destFilename = "\(sanitizedGeometryFilename(finalName)).\(ext.isEmpty ? "json" : ext)"
        let directory    = projectURL.appendingPathComponent("polygonSets", isDirectory: true)
        let destURL      = directory.appendingPathComponent(destFilename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            updateProjectConfig { cfg in
                let def = PolygonSetDef(
                    name: finalName,
                    folder: "polygonSets",
                    filename: destFilename,
                    polygonType: .splinePolygon
                )
                cfg.polygonConfig.library.polygonSets.append(def)
            }
            selectedGeometryKey = "polygonSets/\(finalName)"
        } catch {
            LoomLogger.error("Failed to import geometry from \(sourceURL.lastPathComponent)", error: error)
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
                    let ext = URL(fileURLWithPath: def.filename).pathExtension
                    let newFilename = "\(newName).\(ext.isEmpty ? "xml" : ext)"
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
            DefaultBrushes.write(to: url.appendingPathComponent("brushes"))
            // Ensure svgs/sprites exists for projects created before this feature.
            try? FileManager.default.createDirectory(
                at: url.appendingPathComponent("svgs/sprites"),
                withIntermediateDirectories: true
            )
            let loadedEngine = try Engine(projectDirectory: url)
            engineCanvasSize = loadedEngine.canvasSize
            engine        = loadedEngine
            projectConfig = try? ProjectLoader.load(projectDirectory: url)
            loadError     = nil
            LoomLogger.info("Loaded engine: \(url.path)")
        } catch {
            engine        = nil
            engineCanvasSize = CGSize(width: 1, height: 1)
            // Still load the config so missing-file recovery is accessible in the UI.
            projectConfig = try? ProjectLoader.load(projectDirectory: url)
            loadError     = error.localizedDescription
            LoomLogger.error("Could not load engine from \(url.path)", error: error)
        }
    }

    func reloadEngine() {
        guard let url = projectURL else { return }
        loadEngine(from: url)
    }

    // Returns the on-disk URL for a geometry file, or nil if there is no project or the filename is empty.
    func geometryFileURL(folder: String, filename: String) -> URL? {
        guard let base = projectURL, !filename.isEmpty else { return nil }
        let dir = (folder == "polygonSet" || folder.isEmpty) ? "polygonSets" : folder
        return base.appendingPathComponent(dir).appendingPathComponent(filename)
    }

    // MARK: - Geometry auto-relink

    /// True if any registered geometry file is missing on disk.
    func hasMissingGeometryFiles() -> Bool {
        guard let cfg = projectConfig, let base = projectURL else { return false }
        func gone(_ folder: String, _ filename: String) -> Bool {
            guard !filename.isEmpty else { return false }
            let dir = (folder == "polygonSet" || folder.isEmpty) ? "polygonSets" : folder
            return !FileManager.default.fileExists(atPath: base.appendingPathComponent(dir).appendingPathComponent(filename).path)
        }
        return cfg.polygonConfig.library.polygonSets.contains { $0.regularParams == nil && gone($0.folder, $0.filename) }
            || cfg.curveConfig.library.curveSets.contains  { gone($0.folder, $0.filename) }
            || cfg.pointConfig.library.pointSets.contains  { gone($0.folder, $0.filename) }
    }

    /// Returns unregistered XML/JSON files in the same directory as the missing file,
    /// ranked by name similarity to the missing filename.
    func candidateRelinkFiles(for name: String, folder: String) -> [URL] {
        guard let base = projectURL, let cfg = projectConfig else { return [] }
        let resolvedFolder = (folder == "polygonSet" || folder.isEmpty) ? "polygonSets" : folder

        let missingFilename: String
        switch resolvedFolder {
        case "polygonSets":
            missingFilename = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name })?.filename ?? ""
        case "curveSets":
            missingFilename = cfg.curveConfig.library.curveSets.first(where: { $0.name == name })?.filename ?? ""
        case "pointSets":
            missingFilename = cfg.pointConfig.library.pointSets.first(where: { $0.name == name })?.filename ?? ""
        default:
            missingFilename = ""
        }
        guard !missingFilename.isEmpty else { return [] }

        var registered = Set<String>()
        registered.formUnion(cfg.polygonConfig.library.polygonSets.map { $0.filename })
        registered.formUnion(cfg.curveConfig.library.curveSets.map { $0.filename })
        registered.formUnion(cfg.pointConfig.library.pointSets.map { $0.filename })
        registered.remove(missingFilename)

        let dirURL    = base.appendingPathComponent(resolvedFolder)
        let allFiles  = (try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)) ?? []
        let candidates = allFiles.filter {
            let ext = $0.pathExtension.lowercased()
            return (ext == "xml" || ext == "json") && !registered.contains($0.lastPathComponent)
        }

        let missingStem = URL(fileURLWithPath: missingFilename).deletingPathExtension().lastPathComponent.lowercased()
        return candidates.sorted { a, b in
            relinkSimilarity(missingStem, a.deletingPathExtension().lastPathComponent.lowercased()) >
            relinkSimilarity(missingStem, b.deletingPathExtension().lastPathComponent.lowercased())
        }
    }

    private func relinkSimilarity(_ a: String, _ b: String) -> Int {
        if a == b                          { return 1000 }
        if a.contains(b) || b.contains(a) { return  500 }
        let sep   = CharacterSet(charactersIn: " _-")
        let aWords = Set(a.components(separatedBy: sep).filter { !$0.isEmpty })
        let bWords = Set(b.components(separatedBy: sep).filter { !$0.isEmpty })
        let shared = aWords.intersection(bWords).count
        if shared > 0                      { return  100 + shared * 10 }
        return Set(a).intersection(Set(b)).count
    }

    /// For each missing geometry file with exactly one candidate in its directory,
    /// relinks it automatically and triggers one engine reload.
    /// Safe to call repeatedly — exits immediately when nothing is missing.
    func tryAutoRelinkAllMissing() {
        guard !isAutoRelinking, hasMissingGeometryFiles() else { return }
        guard let cfg = projectConfig, let base = projectURL else { return }
        isAutoRelinking = true
        defer { isAutoRelinking = false }

        var count = 0

        func attempt(name: String, folder: String, filename: String) {
            let resolvedFolder = (folder == "polygonSet" || folder.isEmpty) ? "polygonSets" : folder
            let url = base.appendingPathComponent(resolvedFolder).appendingPathComponent(filename)
            guard !filename.isEmpty, !FileManager.default.fileExists(atPath: url.path) else { return }
            let candidates = candidateRelinkFiles(for: name, folder: resolvedFolder)
            guard candidates.count == 1 else { return }
            relinkGeometryFile(name: name, folder: resolvedFolder, toURL: candidates[0], reload: false)
            count += 1
        }

        for def in cfg.polygonConfig.library.polygonSets where def.regularParams == nil {
            attempt(name: def.name, folder: def.folder, filename: def.filename)
        }
        for def in cfg.curveConfig.library.curveSets {
            attempt(name: def.name, folder: def.folder, filename: def.filename)
        }
        for def in cfg.pointConfig.library.pointSets {
            attempt(name: def.name, folder: def.folder, filename: def.filename)
        }

        if count > 0 {
            appStatusMessage = "Auto-relinked \(count) missing geometry file\(count == 1 ? "" : "s")"
            reloadEngine()
        }
    }

    func relinkGeometryFile(name: String, folder: String, toURL chosenURL: URL, reload: Bool = true) {
        guard let base = projectURL else { return }
        let dir = (folder == "polygonSet" || folder.isEmpty) ? "polygonSets" : folder
        let targetDir   = base.appendingPathComponent(dir, isDirectory: true)
        let newFilename = chosenURL.lastPathComponent
        let destURL     = targetDir.appendingPathComponent(newFilename)
        if destURL.standardizedFileURL != chosenURL.standardizedFileURL {
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: chosenURL, to: destURL)
        }
        updateProjectConfig { cfg in
            switch folder {
            case "polygonSets", "regularPolygons", "polygonSet", "":
                if let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == name }) {
                    cfg.polygonConfig.library.polygonSets[idx].filename = newFilename
                }
            case "curveSets":
                if let idx = cfg.curveConfig.library.curveSets.firstIndex(where: { $0.name == name }) {
                    cfg.curveConfig.library.curveSets[idx].filename = newFilename
                }
            case "pointSets":
                if let idx = cfg.pointConfig.library.pointSets.firstIndex(where: { $0.name == name }) {
                    cfg.pointConfig.library.pointSets[idx].filename = newFilename
                }
            default: break
            }
        }
        if reload { reloadEngine() }
    }

    private func clearSelections() {
        selectedGeometryKey           = nil
        selectedSubdivisionIndex      = nil
        selectedSubdivisionParamIndex = nil
        selectedSpriteID              = nil
        subdivSelectedSpriteID        = nil
        subdivPreviewSetName          = nil
        renderingSelectedSpriteID     = nil
        renderingPreviewSetName       = nil
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

        // Check for newly broken geometry references every ~3 s (e.g. file renamed in Finder).
        if Date().timeIntervalSince(lastAutoRelinkCheck) > 3.0 {
            lastAutoRelinkCheck = Date()
            tryAutoRelinkAllMissing()
        }

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
