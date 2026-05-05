import AppKit
import Foundation
import LoomEngine
import UniformTypeIdentifiers

// MARK: - RenderOutputType

enum RenderOutputType { case still, animation }

enum GeometryEditorTool: String {
    case points = "Points"
    case edges = "Edges"
    case openCurves = "Open Curves"
    case polygons = "Polygons"
    case pointByPoint = "Point By Point"
    case freehand = "Freehand"
}

enum GeometryTransformPivot: String {
    case localCentre = "Local centre"
    case commonCentre = "Common centre"
    case absoluteCentre = "Absolute centre"
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
    @Published var appStatusMessage:              String  = "Ready"
    @Published var isGeometryEditorActive:        Bool    = false
    @Published var geometryEditorTool:            GeometryEditorTool = .points
    @Published var geometryEditorDocument:        EditableGeometryDocument? = nil
    @Published var geometryEditorLoadError:       String? = nil
    @Published var geometryEditorReloadNonce:     Int     = 0
    @Published var geometryEditorSelection:       EditableGeometrySelection = .empty
    @Published var geometryEditorHistory:         EditableGeometryHistory = EditableGeometryHistory()
    @Published var geometryEditorDraftPoints:     [Vector2D] = []
    @Published var geometryEditorFreehandPoints:  [Vector2D] = []
    @Published var geometryEditorFreehandPressures: [Double] = []
    @Published var geometryEditorFreehandDetail:  Double = 0.2
    @Published var geometryEditorLayers:          [GeometryEditorLayer] = [GeometryEditorLayer(name: "Layer 1")]
    @Published var geometryEditorAutoWeld:        Bool = true
    @Published var geometryEditorWeldTolerance:   Double = 0.5
    @Published var geometryEditorAutoWeldSegmentIDs: Set<EditableGeometryID> = []
    @Published var selectedGeometryEditorLayerID: UUID?   = nil
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
    private var geometryTransformGestureBase: EditableGeometrySnapshot?
    private var geometryEditorPendingAutoWeldPairs: [(EditableGeometryID, EditableGeometryID)] = []

    private struct GeometrySegmentReference {
        var layerIndex: Int
        var isPolygon: Bool
        var itemIndex: Int
        var segmentIndex: Int
        var layerID: EditableGeometryID
        var itemID: EditableGeometryID
        var segment: EditableCubicSegment
    }

    private struct GeometryWeldThresholds {
        var midpointDistance: Double
        var endpointPairDistance: Double
        var minimumDirectionDot: Double
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
        projectConfig = config
        if let url = projectURL {
            try? ProjectLoader.save(config, to: url)
        }
        scheduleEngineReload()
    }

    // MARK: - Geometry editor shell

    func enterGeometryEditor() {
        ensureGeometryEditorLayerSelection()
        isGeometryEditorActive = true
    }

    func exitGeometryEditor() {
        isGeometryEditorActive = false
        geometryEditorTool = .points
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
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
        resetHistory: Bool = false
    ) {
        var prunedDocument = document
        prunedDocument?.pruneWeldGroups()
        geometryEditorDocument = prunedDocument
        geometryEditorLoadError = loadError
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

    func startPointByPointGeometryCreation() {
        geometryEditorTool = .pointByPoint
        geometryEditorDraftPoints.removeAll()
        if geometryEditorDocument == nil {
            var document = EditableGeometryDocument(name: "Untitled Polygon")
            document.ensureActiveLayer()
            setGeometryEditorDocument(document)
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
        geometryEditorTool = tool
        geometryEditorDraftPoints.removeAll()
        clearGeometryFreehandStroke()
        geometryEditorSelection = .empty
    }

    func appendGeometryDraftPoint(_ point: Vector2D) {
        guard geometryEditorTool == .pointByPoint else { return }
        geometryEditorDraftPoints.append(point)
    }

    func clearGeometryDraft() {
        geometryEditorDraftPoints.removeAll()
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
        do {
            recordGeometryEditorUndoSnapshot()
            if shouldClose {
                let name = "Freehand Polygon \(document.layers[layerIndex].polygons.count + 1)"
                let polygon = try EditableClosedPolygon(
                    name: name,
                    polygon: Polygon2D(points: fitted, type: .spline, pressures: pressures, visible: true)
                )
                document.layers[layerIndex].polygons.append(polygon)
                geometryEditorSelection = EditableGeometrySelection(layerID: activeLayerID, polygonIDs: [polygon.id])
                geometryEditorTool = .polygons
            } else {
                let name = "Freehand Curve \(document.layers[layerIndex].openCurves.count + 1)"
                let curve = try EditableOpenCurve(
                    name: name,
                    polygon: Polygon2D(points: fitted, type: .openSpline, pressures: pressures, visible: true)
                )
                document.layers[layerIndex].openCurves.append(curve)
                geometryEditorSelection = EditableGeometrySelection(layerID: activeLayerID, openCurveIDs: [curve.id])
                geometryEditorTool = .openCurves
            }
            selectedGeometryEditorLayerID = activeLayerID
            setGeometryEditorDocument(document)
            postStatus("Created \(shouldClose ? "freehand polygon" : "freehand curve")")
        } catch {
            geometryEditorLoadError = error.localizedDescription
            postStatus("Freehand fit failed: \(error.localizedDescription)")
        }
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

    var canFinaliseGeometryDraftPolygon: Bool {
        (geometryEditorDraftPoints.count >= 3 && selectedGeometryEditorLayerCanEdit) || canCloseSelectedOpenCurve
    }

    var canFinaliseGeometryDraftOpenCurve: Bool {
        geometryEditorDraftPoints.count >= 2 && selectedGeometryEditorLayerCanEdit
    }

    func finaliseGeometryDraftPolygon() {
        guard canFinaliseGeometryDraftPolygon else { return }
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

    func saveGeometryEditorDocument(named requestedName: String) {
        guard var document = geometryEditorDocument,
              let projectURL,
              let key = selectedGeometryKey
        else { return }

        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, String(parts[0]) == "polygonSets" else { return }
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
            setGeometryEditorDocument(document)
            selectedGeometryKey = "polygonSets/\(finalName)"
            geometryEditorLoadError = nil
            geometryEditorReloadNonce += 1
        } catch {
            geometryEditorLoadError = error.localizedDescription
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
                layer.openCurves.contains { geometryEditorSelection.openCurveIDs.contains($0.id) }
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
        return false
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
            layer.openCurves.contains { geometryEditorSelection.openCurveIDs.contains($0.id) }
    }

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
        return Set(polygonAnchors + curveAnchors).count
    }

    func duplicateSelectedGeometry() {
        guard var document = geometryEditorDocument,
              let layerID = geometryEditorSelection.layerID,
              layerCanEdit(layerID),
              let layerIndex = document.layers.firstIndex(where: { $0.id == layerID }),
              canDuplicateSelectedGeometry
        else {
            postStatus("Duplicate: no selectable polygon or open curve")
            return
        }

        let selectedPolygons = geometryEditorSelection.polygonIDs
        let selectedCurves = geometryEditorSelection.openCurveIDs
        var copiedPolygonIDs = Set<EditableGeometryID>()
        var copiedCurveIDs = Set<EditableGeometryID>()
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

        guard !polygonCopies.isEmpty || !curveCopies.isEmpty else {
            postStatus("Duplicate: selected geometry was not found in layer")
            return
        }
        recordGeometryEditorUndoSnapshot()
        document.layers[layerIndex].polygons.append(contentsOf: polygonCopies)
        document.layers[layerIndex].openCurves.append(contentsOf: curveCopies)
        geometryEditorDocument = document
        syncGeometryEditorLayers(from: document.layers)
        geometryEditorSelection = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: copiedPolygonIDs,
            openCurveIDs: copiedCurveIDs
        )
        selectedGeometryEditorLayerID = layerID
        postStatus("Duplicated \(polygonCopies.count + curveCopies.count) item(s)")
    }

    private func selectedGeometryPoints(in layer: EditableGeometryLayer) -> [Vector2D] {
        let polygonPoints = layer.polygons
            .filter { geometryEditorSelection.polygonIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        let curvePoints = layer.openCurves
            .filter { geometryEditorSelection.openCurveIDs.contains($0.id) }
            .flatMap { $0.points.map(\.position) }
        return polygonPoints + curvePoints
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
            layer.openCurves.flatMap { $0.points.map(\.id) }
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

    private func duplicateOffsetDistance(for points: [Vector2D]) -> Double {
        guard !points.isEmpty else { return 0.08 }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let span = max(maxX - minX, maxY - minY)
        return min(max(span * 0.20, 0.06), 0.16)
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
        return centre(of: polygonPoints + curvePoints)
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

        translateRelationalPointIDs([pointID], by: position - currentPosition, in: &document)
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
        let seedIDs = selectedGeometryObjectPointIDs(in: document.layers[layerIndex], selection: geometryEditorSelection)
        translateRelationalPointIDs(seedIDs, by: delta, in: &document)
        setGeometryEditorDocument(document)
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
        translateRelationalPointIDs(seedIDs, by: delta, in: &document)
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
        return GeometryWeldThresholds(
            midpointDistance: 0.03 + value * 0.09,
            endpointPairDistance: 0.06 + value * 0.14,
            minimumDirectionDot: 0.92 - value * 0.37
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
            guard !selectedPolygons.isEmpty || !selectedCurves.isEmpty else { return }
            recordGeometryEditorUndoSnapshot()
            document.layers[layerIndex].polygons.removeAll { selectedPolygons.contains($0.id) }
            document.layers[layerIndex].openCurves.removeAll { selectedCurves.contains($0.id) }
            geometryEditorSelection = .empty
            setGeometryEditorDocument(document)
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
        geometryEditorSelection.polygonIDs.formIntersection(polygonIDs)
        geometryEditorSelection.openCurveIDs.formIntersection(openCurveIDs)
        geometryEditorSelection.pointIDs.formIntersection(pointIDs)
        geometryEditorSelection.segmentIDs.formIntersection(segmentIDs)
        if geometryEditorSelection.polygonIDs.isEmpty && geometryEditorSelection.openCurveIDs.isEmpty {
            geometryEditorSelection = .empty
        }
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
            for folder in ["polygonSets", "curveSets", "pointSets", "ovalSets", "regularPolygons"] {
                try FileManager.default.createDirectory(
                    at: url.appendingPathComponent(folder),
                    withIntermediateDirectories: true
                )
            }
            var config = ProjectConfig()
            if let name {
                config.globalConfig.name = name
            }
            try ProjectLoader.save(config, to: url)
            open(projectDirectory: url)
        } catch {
            loadError = "Could not create project: \(error.localizedDescription)"
        }
    }

    private func sanitizedProjectName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars).replacingOccurrences(of: " ", with: "_")
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
            setGeometryEditorDocument(document, resetHistory: true)
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
