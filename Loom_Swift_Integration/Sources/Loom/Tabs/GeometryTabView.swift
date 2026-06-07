import AppKit
import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

private struct GeometrySource: Identifiable, Hashable {
    let key: String
    let name: String
    let folder: String
    let icon: String
    let hasPolygons: Bool
    let hasCurves: Bool
    let hasPoints: Bool
    let spriteCount: Int
    var isMissingFile: Bool = false

    var id: String { key }
}

private enum GeometryKind {
    case polygons
    case curves
    case points
}

private struct GeometryKindIcon: Shape {
    let kind: GeometryKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .polygons:
            var path = Path()
            let size = min(rect.width, rect.height) * 0.62
            let origin = CGPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
            path.addRect(CGRect(origin: origin, size: CGSize(width: size, height: size)))
            return path

        case .curves:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.28))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.22),
                control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08)
            )
            return path

        case .points:
            var path = Path()
            let outer = min(rect.width, rect.height) * 0.68
            let outerRect = CGRect(
                x: rect.midX - outer / 2,
                y: rect.midY - outer / 2,
                width: outer,
                height: outer
            )
            path.addEllipse(in: outerRect)
            let inner = outer * 0.24
            path.addEllipse(
                in: CGRect(
                    x: rect.midX - inner / 2,
                    y: rect.midY - inner / 2,
                    width: inner,
                    height: inner
                )
            )
            return path
        }
    }
}

// Left-panel list view for the Geometry tab.
// Shows geometry sources once, with passive indicators for the geometry types they contain.
struct GeometryTabView: View {

    @EnvironmentObject private var controller: AppController
    @State private var showingRenameAlert = false
    @State private var renameText         = ""

    var body: some View {
        Group {
            if controller.isGeometryEditorActive {
                GeometryLayerPanel()
                    .environmentObject(controller)
            } else {
                geometryList
            }
        }
        .alert("Rename Geometry", isPresented: $showingRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                guard let key = controller.selectedGeometryKey, !renameText.isEmpty else { return }
                controller.renameGeometry(key: key, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var geometryList: some View {
        VStack(spacing: 0) {
            List(selection: $controller.selectedGeometryKey) {
                Section {
                    if geometrySources.isEmpty {
                        Text("None")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    } else {
                        ForEach(geometrySources) { source in
                            geometrySourceRow(source)
                                .tag(source.key)
                                .contextMenu {
                                    Button("Rename…") {
                                        renameText = source.name
                                        controller.selectedGeometryKey = source.key
                                        showingRenameAlert = true
                                    }
                                    Button("Duplicate") { controller.duplicateGeometry(key: source.key) }
                                    Divider()
                                    Button("Delete", role: .destructive) { controller.deleteGeometry(key: source.key) }
                                }
                        }
                    }
                } header: {
                    geometrySourcesHeader
                }
            }
            .listStyle(.sidebar)

            Divider()
            actionBar
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .padding(.bottom, 2)
            Button("Duplicate") {
                if let key = controller.selectedGeometryKey {
                    controller.duplicateGeometry(key: key)
                }
            }
            .disabled(controller.selectedGeometryKey == nil)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Rename") {
                    if let key = controller.selectedGeometryKey {
                        renameText = String(key.split(separator: "/", maxSplits: 1).last ?? "")
                        showingRenameAlert = true
                    }
                }
                .disabled(controller.selectedGeometryKey == nil)

                Spacer()

                Button("Import") {
                    let panel = NSOpenPanel()
                    panel.title = "Import Geometry"
                    panel.message = "Select a geometry file to import into this project"
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.directoryURL = AppController.defaultProjectsDirectory
                    panel.allowedContentTypes = [.json]
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        controller.importGeometry(from: url)
                    }
                }

                Spacer()

                Button("Delete") {
                    if let key = controller.selectedGeometryKey {
                        controller.deleteGeometry(key: key)
                    }
                }
                .disabled(controller.selectedGeometryKey == nil)
                .foregroundStyle(controller.selectedGeometryKey != nil ? Color.red : Color.secondary)
            }

            HStack {
                Spacer()
                Button("Import SVG…") {
                    let panel = NSOpenPanel()
                    panel.title = "Import SVG Geometry"
                    panel.message = "Select an SVG file to import. Text should be converted to paths in Inkscape first (Object › Object to Path)."
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        controller.importSVGGeometry(from: url)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Source list

    @ViewBuilder
    private var geometrySourcesHeader: some View {
        HStack(spacing: 6) {
            Text("Geometry Sources")
            Spacer()
            Button {
                controller.createGeometry(folder: "polygonSets")
            } label: {
                Label("New", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("New Geometry Source")
        }
    }

    @ViewBuilder
    private func geometrySourceRow(_ source: GeometrySource) -> some View {
        HStack(spacing: 6) {
            Label(source.name, systemImage: source.icon)
                .font(.system(size: 12))
                .lineLimit(1)
            if source.isMissingFile {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("Geometry file not found — select this item and use the inspector to re-link it")
            }
            Spacer()
            geometryKindIcon(.polygons, isPresent: source.hasPolygons)
                .frame(width: 18, height: 16)
                .help(source.hasPolygons ? "Contains polygons" : "No polygons")
            geometryKindIcon(.curves, isPresent: source.hasCurves)
                .frame(width: 18, height: 16)
                .help(source.hasCurves ? "Contains curves" : "No curves")
            geometryKindIcon(.points, isPresent: source.hasPoints)
                .frame(width: 22, height: 16)
                .help(source.hasPoints ? "Contains points" : "No points")
            Text("\(source.spriteCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(source.spriteCount > 0 ? Color.secondary : Color.clear)
                .frame(minWidth: 16, alignment: .trailing)
        }
    }

    private func geometryKindIcon(_ kind: GeometryKind, isPresent: Bool) -> some View {
        GeometryKindIcon(kind: kind)
            .stroke(
                isPresent ? Color.secondary : Color.secondary.opacity(0.22),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
    }

    // MARK: - Helpers

    private var geometrySources: [GeometrySource] {
        if let cfg = controller.projectConfig {
            return configuredGeometrySources(cfg)
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        }

        return filesystemGeometrySources()
    }

    private func configuredGeometrySources(_ cfg: ProjectConfig) -> [GeometrySource] {
        var sources: [GeometrySource] = []

        for def in cfg.polygonConfig.library.polygonSets where def.regularParams != nil {
            sources.append(
                GeometrySource(
                    key: "regularPolygons/\(def.name)",
                    name: def.name,
                    folder: "regularPolygons",
                    icon: "hexagon",
                    hasPolygons: true,
                    hasCurves: false,
                    hasPoints: false,
                    spriteCount: spriteCount(folder: "regularPolygons", name: def.name)
                )
            )
        }

        for def in cfg.polygonConfig.library.polygonSets where def.regularParams == nil && !isLayerTargetedPolygonSet(def) {
            let contents = editableGeometryContents(for: def)
            let missing  = controller.geometryFileURL(folder: "polygonSets", filename: def.filename)
                .map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
            sources.append(
                GeometrySource(
                    key: "polygonSets/\(def.name)",
                    name: def.name,
                    folder: "polygonSets",
                    icon: "square.stack.3d.up",
                    hasPolygons: contents?.hasPolygons ?? true,
                    hasCurves: contents?.hasCurves ?? false,
                    hasPoints: contents?.hasPoints ?? false,
                    spriteCount: spriteCount(folder: "polygonSets", name: def.name),
                    isMissingFile: missing
                )
            )
        }

        for def in cfg.curveConfig.library.curveSets {
            let missing = controller.geometryFileURL(folder: def.folder, filename: def.filename)
                .map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
            sources.append(
                GeometrySource(
                    key: "curveSets/\(def.name)",
                    name: def.name,
                    folder: "curveSets",
                    icon: "scribble",
                    hasPolygons: false,
                    hasCurves: true,
                    hasPoints: false,
                    spriteCount: spriteCount(folder: "curveSets", name: def.name),
                    isMissingFile: missing
                )
            )
        }

        for def in cfg.pointConfig.library.pointSets {
            let missing = controller.geometryFileURL(folder: def.folder, filename: def.filename)
                .map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
            sources.append(
                GeometrySource(
                    key: "pointSets/\(def.name)",
                    name: def.name,
                    folder: "pointSets",
                    icon: "circle.grid.3x3.fill",
                    hasPolygons: false,
                    hasCurves: false,
                    hasPoints: true,
                    spriteCount: spriteCount(folder: "pointSets", name: def.name),
                    isMissingFile: missing
                )
            )
        }

        return sources
    }

    private func filesystemGeometrySources() -> [GeometrySource] {
        guard let base = controller.projectURL else { return [] }
        let folders: [(folder: String, icon: String, hasPolygons: Bool, hasCurves: Bool, hasPoints: Bool)] = [
            ("polygonSets", "square.stack.3d.up", true, false, false),
            ("curveSets", "scribble", false, true, false),
            ("pointSets", "circle.grid.3x3.fill", false, false, true)
        ]
        var sources: [GeometrySource] = []
        for folder in folders {
            let dir = base.appendingPathComponent(folder.folder)
            guard let contents = try? FileManager.default
                .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter({ !$0.lastPathComponent.hasPrefix(".") })
            else { continue }
            for url in contents {
                let name = url.deletingPathExtension().lastPathComponent
                sources.append(
                    GeometrySource(
                        key: "\(folder.folder)/\(name)",
                        name: name,
                        folder: folder.folder,
                        icon: folder.icon,
                        hasPolygons: folder.hasPolygons,
                        hasCurves: folder.hasCurves,
                        hasPoints: folder.hasPoints,
                        spriteCount: spriteCount(folder: folder.folder, name: name)
                    )
                )
            }
        }
        return sources.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func editableGeometryContents(for def: PolygonSetDef) -> (hasPolygons: Bool, hasCurves: Bool, hasPoints: Bool)? {
        guard let projectURL = controller.projectURL,
              !def.filename.isEmpty,
              def.filename.lowercased().hasSuffix(".json")
        else { return nil }
        let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
        guard let document = try? EditableGeometryJSONLoader.load(
            url: projectURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
        ) else { return nil }
        return (
            hasPolygons: document.layers.contains { !$0.polygons.isEmpty },
            hasCurves: document.layers.contains { !$0.openCurves.isEmpty },
            hasPoints: document.layers.contains { !$0.points.isEmpty }
        )
    }

    private func spriteCount(folder: String, name: String) -> Int {
        guard let cfg = controller.projectConfig else { return 0 }
        let shapeSetNames: Set<String> = Set(cfg.shapeConfig.library.shapeSets.compactMap { ss in
            let matches = ss.shapes.contains { shape in
            switch folder {
                case "polygonSets", "regularPolygons": return polygonSetName(shape.polygonSetName, matchesVisibleName: name)
                case "curveSets":   return shape.openCurveSetName == name
                case "pointSets":   return shape.pointSetName == name
                default:            return false
                }
            }
            return matches ? ss.name : nil
        })
        return cfg.spriteConfig.library.allSprites.filter { shapeSetNames.contains($0.shapeSetName) }.count
    }

    private func isLayerTargetedPolygonSet(_ def: PolygonSetDef) -> Bool {
        def.editableLayerID != nil ||
        !(def.editableLayerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func polygonSetName(_ candidate: String, matchesVisibleName visibleName: String) -> Bool {
        guard let cfg = controller.projectConfig else { return candidate == visibleName }
        guard candidate != visibleName,
              let visibleDef = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == visibleName }),
              let candidateDef = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == candidate }),
              isLayerTargetedPolygonSet(candidateDef)
        else {
            return candidate == visibleName
        }
        return visibleDef.filename == candidateDef.filename &&
            visibleDef.folder == candidateDef.folder &&
            visibleDef.regularParams == nil &&
            candidateDef.regularParams == nil
    }
}

// Reusable drop delegate for layer reordering.
private struct LayerDropDelegate: DropDelegate {
    var validate: () -> Bool
    var entered:  () -> Void
    var exited:   () -> Void
    var perform:  () -> Bool

    func validateDrop(info: DropInfo) -> Bool { validate() }
    func dropEntered(info: DropInfo)           { entered() }
    func dropExited(info: DropInfo)            { exited() }
    func performDrop(info: DropInfo) -> Bool   { perform() }
}

private struct GeometryLayerPanel: View {
    @EnvironmentObject private var controller: AppController
    @State private var showingRenameAlert        = false
    @State private var renameText                = ""
    @State private var showingDeleteConfirmation = false
    @State private var dragLayerID:   UUID?      = nil
    @State private var dropBeforeIdx: Int?       = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            let layers = controller.geometryEditorLayers
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                        layerRow(layer: layer, index: index)
                    }
                    // After-all drop zone
                    Color.clear
                        .frame(height: 10)
                        .contentShape(Rectangle())
                        .onDrop(of: [UTType.utf8PlainText], delegate: afterAllDelegate(total: layers.count))
                        .overlay(alignment: .bottom) {
                            if dropBeforeIdx == layers.count { insertionLine }
                        }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                controller.ensureGeometryEditorLayerSelection()
                if let id = controller.selectedGeometryEditorLayerID {
                    controller.focusGeometryEditorLayer(id: id)
                }
            }

            Divider()

            if morphLayerVertexMismatch {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("Layers have different vertex counts — morph targets may not work.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }

            VStack(spacing: 6) {
                let morphLocked = controller.isCurrentGeometryMorphTargetLocked
                HStack {
                    Button("New")     { controller.addGeometryEditorLayer() }
                        .disabled(morphLocked)
                    Spacer()
                    Button("Rename") {
                        renameText = selectedLayerName
                        showingRenameAlert = true
                    }
                    .disabled(controller.selectedGeometryEditorLayerID == nil)
                }
                HStack {
                    Button("Duplicate") { controller.duplicateSelectedGeometryEditorLayer() }
                        .disabled(controller.selectedGeometryEditorLayerID == nil || morphLocked)
                    Spacer()
                    Button("Delete") {
                        if selectedLayerHasGeometry {
                            showingDeleteConfirmation = true
                        } else {
                            controller.deleteSelectedGeometryEditorLayer()
                        }
                    }
                    .disabled(controller.geometryEditorLayers.count <= 1 || morphLocked)
                    .foregroundStyle(controller.geometryEditorLayers.count > 1 && !morphLocked ? Color.red : Color.secondary)
                }
                HStack {
                    Button("Import layer…") { controller.importBakedGeometryAsLayer() }
                        .disabled(morphLocked)
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .alert("Rename Layer", isPresented: $showingRenameAlert) {
            TextField("Layer name", text: $renameText)
            Button("Rename") { controller.renameSelectedGeometryEditorLayer(to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \"\(selectedLayerName)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Layer", role: .destructive) {
                controller.deleteSelectedGeometryEditorLayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This layer contains geometry. Deleting it cannot be undone except via Undo.")
        }
    }

    // MARK: - Layer row

    private func layerRow(layer: GeometryEditorLayer, index: Int) -> some View {
        let isSelected   = layer.id == controller.selectedGeometryEditorLayerID
        let isDropTarget = dropBeforeIdx == index

        return HStack(spacing: 6) {
            Text(layer.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            Spacer()
            Button {
                controller.toggleGeometryEditorLayerEditability(id: layer.id)
            } label: {
                Image(systemName: layer.isEditable ? "hand.draw.fill" : "hand.draw")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(layer.isEditable ? Color.accentColor : Color.secondary)
            .help(layer.isEditable ? "Editable" : "Not editable")

            Button {
                controller.toggleGeometryEditorLayerVisibility(id: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(layer.isVisible ? Color.accentColor : Color.secondary)
            .help(layer.isVisible ? "Visible" : "Hidden")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.focusGeometryEditorLayer(id: layer.id) }
        .onDrag {
            self.dragLayerID = layer.id
            return NSItemProvider(object: layer.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: rowDelegate(index: index))
        .overlay(alignment: .top) {
            if isDropTarget { insertionLine }
        }
    }

    private var insertionLine: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 4)
    }

    // MARK: - Drop delegates

    private func rowDelegate(index: Int) -> LayerDropDelegate {
        LayerDropDelegate(
            validate: { self.dragLayerID != nil },
            entered:  { self.dropBeforeIdx = index },
            exited:   { if self.dropBeforeIdx == index { self.dropBeforeIdx = nil } },
            perform: {
                defer { self.dragLayerID = nil; self.dropBeforeIdx = nil }
                guard let id = self.dragLayerID else { return false }
                self.controller.reorderGeometryEditorLayer(id: id, toBeforeIndex: index)
                return true
            }
        )
    }

    private func afterAllDelegate(total: Int) -> LayerDropDelegate {
        LayerDropDelegate(
            validate: { self.dragLayerID != nil },
            entered:  { self.dropBeforeIdx = total },
            exited:   { if self.dropBeforeIdx == total { self.dropBeforeIdx = nil } },
            perform: {
                defer { self.dragLayerID = nil; self.dropBeforeIdx = nil }
                guard let id = self.dragLayerID else { return false }
                self.controller.reorderGeometryEditorLayer(id: id, toBeforeIndex: total)
                return true
            }
        )
    }

    // MARK: - Helpers

    private var selectedLayerName: String {
        guard let id = controller.selectedGeometryEditorLayerID,
              let layer = controller.geometryEditorLayers.first(where: { $0.id == id })
        else { return "" }
        return layer.name
    }

    private var selectedLayerHasGeometry: Bool {
        guard let id = controller.selectedGeometryEditorLayerID,
              let document = controller.geometryEditorDocument,
              let layer = document.layers.first(where: { $0.id == id })
        else { return false }
        return !layer.polygons.isEmpty || !layer.openCurves.isEmpty || !layer.points.isEmpty
    }

    // True when the document has 2+ layers and any layer's polygon vertex-count
    // profile differs from the first layer — warns the user that morph targets
    // may be broken.
    private var morphLayerVertexMismatch: Bool {
        guard let layers = controller.geometryEditorDocument?.layers, layers.count > 1 else { return false }
        let baseline = layers[0].polygons.map { $0.points.count }
        return layers.dropFirst().contains { $0.polygons.map { $0.points.count } != baseline }
    }
}

// MARK: - Center panel

// Center-panel main view for the Geometry tab.
// Shows wireframe of selected geometry set; falls back to live canvas when nothing is selected.
struct GeometryMainView: View {

    @EnvironmentObject private var controller: AppController
    @State private var loadedPolygons: [Polygon2D] = []
    @State private var loadError:      String?

    var body: some View {
        Group {
            if controller.isGeometryEditorActive {
                GeometryEditorMainShell(
                    document: controller.geometryEditorDocument,
                    loadError: controller.geometryEditorLoadError
                )
                    .environmentObject(controller)
            } else {
                previewBody
            }
        }
        .onAppear        { loadGeometry() }
        .onChange(of: controller.selectedGeometryKey) { _, _ in loadGeometry() }
        .onChange(of: controller.projectURL)          { _, _ in loadGeometry() }
        .onChange(of: controller.isGeometryEditorActive) { _, _ in loadGeometry() }
        .onChange(of: controller.geometryEditorReloadNonce) { _, _ in loadGeometry() }
    }

    private var previewBody: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)

            if controller.selectedGeometryKey != nil {
                if !loadedPolygons.isEmpty {
                    WireframeCanvas(polygons: loadedPolygons)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Text("No geometry data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ZStack {
                    Color.black
                    if let engine = controller.engine {
                        let size   = controller.engineCanvasSize
                        let aspect = size.width / max(size.height, 1)
                        RenderSurfaceView(
                            engine:        engine,
                            playbackState: controller.playbackState,
                            onFrameTick:   { _ in }
                        )
                        .aspectRatio(aspect, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func loadGeometry() {
        guard let key = controller.selectedGeometryKey else {
            loadedPolygons = []
            loadError = nil
            controller.setGeometryEditorDocument(nil, resetHistory: true)
            return
        }
        do {
            if let editableDocument = try resolveEditableDocument(key: key) {
                let layerTarget = resolveEditableLayerTarget(key: key)
                loadedPolygons = try editableDocument.runtimePolygons(
                    targetLayerID: layerTarget?.id,
                    targetLayerName: layerTarget?.name
                )
                controller.setGeometryEditorDocument(editableDocument, resetHistory: true, cleanSource: .loaded)
            } else {
                loadedPolygons = try resolvePolygons(key: key)
                let editableDocument = try makeEditableDocument(key: key, polygons: loadedPolygons)
                controller.setGeometryEditorDocument(editableDocument, resetHistory: true, cleanSource: .loaded)
            }
            loadError = nil
        } catch {
            loadedPolygons = []
            controller.setGeometryEditorDocument(nil, loadError: error.localizedDescription, resetHistory: true)
            loadError = error.localizedDescription
        }
    }

    private func makeEditableDocument(key: String, polygons: [Polygon2D]) throws -> EditableGeometryDocument {
        let name = String(key.split(separator: "/", maxSplits: 1).last ?? "Editable Geometry")

        let closedPolygons = polygons.filter { $0.type == .spline }
        let openPolygons   = polygons.filter { $0.type == .openSpline }

        // Empty source — start blank.
        if closedPolygons.isEmpty && openPolygons.isEmpty {
            if key.hasPrefix("polygonSets/") {
                var document = EditableGeometryDocument(name: name)
                document.ensureActiveLayer()
                return document
            }
            throw EditableGeometryError.unsupportedPolygonType(polygons.first?.type ?? .line)
        }

        var layers: [EditableGeometryLayer] = []

        if !closedPolygons.isEmpty {
            let editablePolygons = try closedPolygons.enumerated().map { index, polygon in
                try EditableClosedPolygon(name: "Polygon \(index + 1)", polygon: polygon)
            }
            layers.append(EditableGeometryLayer(name: "Closed Paths", polygons: editablePolygons))
        }

        if !openPolygons.isEmpty {
            let editableCurves = try openPolygons.enumerated().map { index, polygon in
                try EditableOpenCurve(name: "Curve \(index + 1)", polygon: polygon)
            }
            layers.append(EditableGeometryLayer(name: "Open Curves", openCurves: editableCurves))
        }

        return EditableGeometryDocument(name: name, layers: layers, activeLayerID: layers[0].id)
    }

    private func resolvePolygons(key: String) throws -> [Polygon2D] {
        guard let projURL = controller.projectURL,
              let cfg     = controller.projectConfig
        else { return [] }

        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return [] }
        let folder = String(parts[0])
        let name   = String(parts[1])

        switch folder {
        case "polygonSets":
            guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name })
            else { return [] }
            if let rp = def.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }
            guard !def.filename.isEmpty else { return [] }
            let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
            let url = projURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
            if def.filename.lowercased().hasSuffix(".json") {
                return try EditableGeometryJSONLoader.load(url: url).runtimePolygons(
                    targetLayerID: def.editableLayerID,
                    targetLayerName: def.editableLayerName
                )
            }
            return try XMLPolygonLoader.load(url: url)

        case "regularPolygons":
            guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name }),
                  let rp  = def.regularParams
            else { return [] }
            return [RegularPolygonGenerator.generate(params: rp)]

        case "curveSets":
            guard let def = cfg.curveConfig.library.curveSets.first(where: { $0.name == name })
            else { return [] }
            let url = projURL.appendingPathComponent(def.folder).appendingPathComponent(def.filename)
            return try XMLPolygonLoader.loadOpenCurveSet(url: url)

        case "pointSets":
            guard let def = cfg.pointConfig.library.pointSets.first(where: { $0.name == name })
            else { return [] }
            let url = projURL.appendingPathComponent(def.folder).appendingPathComponent(def.filename)
            return try XMLPolygonLoader.loadPointSet(url: url)

        default:
            return []
        }
    }

    private func resolveEditableDocument(key: String) throws -> EditableGeometryDocument? {
        guard let projURL = controller.projectURL,
              let cfg     = controller.projectConfig
        else { return nil }

        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              String(parts[0]) == "polygonSets"
        else { return nil }

        let name = String(parts[1])
        guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name }),
              !def.filename.isEmpty,
              def.filename.lowercased().hasSuffix(".json")
        else { return nil }

        let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
        return try EditableGeometryJSONLoader.load(
            url: projURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
        )
    }

    private func resolveEditableLayerTarget(key: String) -> (id: EditableGeometryID?, name: String?)? {
        guard let cfg = controller.projectConfig else { return nil }
        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              String(parts[0]) == "polygonSets"
        else { return nil }
        let name = String(parts[1])
        guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name }),
              def.editableLayerID != nil || def.editableLayerName != nil
        else { return nil }
        return (def.editableLayerID, def.editableLayerName)
    }
}

private struct GeometryEditorMainShell: View {
    @EnvironmentObject private var controller: AppController
    let document: EditableGeometryDocument?
    let loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Title + geometry info
                Text("Geometry Editor")
                    .font(.system(size: 13, weight: .semibold))
                Text(currentGeometryName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(controller.geometryEditorTool.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                let morphLocked = controller.isCurrentGeometryMorphTargetLocked

                // Gap ≈ "Polygons"
                Color.clear.frame(width: 52)

                // Edit label
                Text("Edit:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                // 5 edit-mode icons
                toolbarIconButton(help: "Edit points", selected: controller.geometryEditorTool == .points) {
                    EditPointsIcon()
                } action: { controller.startGeometryEditMode(.points) }
                toolbarIconButton(
                    help: "Anchor-only edit: drag anchors without moving their control points",
                    selected: controller.geometryEditorAnchorOnlyEdit
                ) {
                    CrosshairAnchorIcon()
                } action: { controller.geometryEditorAnchorOnlyEdit.toggle() }
                toolbarIconButton(help: "Edit edges", selected: controller.geometryEditorTool == .edges) {
                    EdgeGeometryIcon()
                } action: { controller.startGeometryEditMode(.edges) }
                toolbarIconButton(help: "Edit open curves", selected: controller.geometryEditorTool == .openCurves) {
                    OpenCurveGeometryIcon()
                } action: { controller.startGeometryEditMode(.openCurves) }
                toolbarIconButton(help: "Edit polygons", selected: controller.geometryEditorTool == .polygons) {
                    PolygonGeometryIcon()
                } action: { controller.startGeometryEditMode(.polygons) }

                // Gap
                Color.clear.frame(width: 52)

                // Cut / copy / paste
                toolbarIconButton(help: "Cut selected objects", disabled: !controller.canCutCopySelectedGeometry || morphLocked) {
                    Image(systemName: "scissors").font(.system(size: 14))
                } action: { controller.cutSelectedGeometry() }
                toolbarIconButton(help: "Copy selected objects", disabled: !controller.canCutCopySelectedGeometry) {
                    CopyGeometryIcon()
                } action: { controller.copySelectedGeometry() }
                toolbarIconButton(help: "Paste at last click position", disabled: !controller.canPasteGeometry || morphLocked) {
                    PasteGeometryIcon()
                } action: { controller.pasteGeometry() }

                // Gap
                Color.clear.frame(width: 52)

                // Centre
                toolbarIconButton(help: "Centre selected geometry, or the active layer if nothing is selected") {
                    Image(systemName: "scope").font(.system(size: 14))
                } action: { controller.centreGeometryEditorViewOnSelectionOrLayer() }

                // Gap
                Color.clear.frame(width: 52)

                // Snap icons
                toolbarIconButton(help: "Snap selected anchors to grid, leaving control points unchanged") {
                    AnchorSnapIcon()
                } action: { controller.snapGeometryEditorSelectionToGrid(anchorOnly: true) }
                toolbarIconButton(help: "Snap selected points to grid, or all active layer points if nothing is selected") {
                    SnapAllPointsIcon()
                } action: { controller.snapGeometryEditorSelectionToGrid(anchorOnly: false) }
                toolbarIconButton(help: "Reset control points", disabled: !controller.canResetSelectedGeometryControls) {
                    SteeringWheelIcon()
                } action: { controller.resetSelectedGeometryControls() }

                Spacer(minLength: 0)

                // Delete icons (towards right)
                toolbarIconButton(help: "Delete selected geometry", disabled: !controller.canDeleteSelectedGeometry || morphLocked) {
                    DeleteSelectedGeometryIcon()
                } action: { controller.deleteSelectedGeometry() }
                toolbarIconButton(help: "Delete all geometry in active layer", disabled: !controller.canDeleteAllLayerGeometry || morphLocked) {
                    DeleteAllLayerGeometryIcon()
                } action: { controller.deleteAllLayerGeometry() }

                Divider().frame(height: 16)

                // Morph target lock
                Button {
                    controller.toggleCurrentGeometryMorphTargetLock()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: morphLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 12))
                        Text("Morph Target")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(morphLocked ? Color.orange : Color.secondary)
                }
                .help(morphLocked ? "Morph target locked: only vertex positions can be edited. Click to unlock." : "Click to designate as morph target (locks topology)")
                .buttonStyle(.plain)

                Button("Default Geometry View") {
                    controller.requestExitGeometryEditor()
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ZStack {
                Color(red: 0.07, green: 0.075, blue: 0.09)
                if let document {
                    EditableGeometryCanvas(document: document)
                        .environmentObject(controller)
                        .padding(24)
                } else {
                    Text(loadError ?? "Select a closed polygon set to inspect.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private var currentGeometryName: String {
        guard let key = controller.selectedGeometryKey else { return "New closed polygon shell" }
        return String(key.split(separator: "/", maxSplits: 1).last ?? "")
    }

    @ViewBuilder
    private func toolbarIconButton<Content: View>(
        help: String = "",
        disabled: Bool = false,
        selected: Bool = false,
        @ViewBuilder label: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    selected  ? Color.accentColor :
                    disabled  ? Color.secondary.opacity(0.35) :
                                Color.primary
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .modifier(LoomHoverHelp(help))
    }
}

private struct EditableGeometryCanvas: View {
    @EnvironmentObject private var controller: AppController
    let document: EditableGeometryDocument
    @State private var activeDragTarget: GeometryPointHit?
    @State private var activePolygonDragTarget: GeometryPolygonHit?
    @State private var activeOpenCurveDragTarget: GeometryOpenCurveHit?
    @State private var activeSegmentDragTarget: GeometrySegmentHit?
    @State private var activeMeshAnchorIndex: Int?
    @State private var activeMeshPreviewDrag = false
    @State private var lastDragWorldPoint: Vector2D?
    @State private var rubberBandStart: CGPoint?
    @State private var rubberBandEnd: CGPoint?
    @State private var rubberBandAddsToSelection = false
    @State private var dragUndoRecorded = false
    @State private var lastPanScreenPoint: CGPoint?
    @State private var activeSelectionCanvasDrag = false
    @State private var activeClickOnlySelection = false
    private let weldedEdgeColor = Color(red: 0.72, green: 0.22, blue: 1.0)
    private let weldedAnchorColor = Color(red: 0.95, green: 0.58, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let canvasSize = max(220, side)
            Canvas { ctx, size in
                draw(ctx: ctx, size: size)
            }
            .frame(width: canvasSize, height: canvasSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        controller.geometryEditorLastClickPosition = unproject(value.startLocation, canvasSize: canvasSize)
                        switch controller.geometryEditorTool {
                        case .panView:
                            if let previous = lastPanScreenPoint {
                                controller.panGeometryEditorView(
                                    screenDelta: CGSize(
                                        width: value.location.x - previous.x,
                                        height: value.location.y - previous.y
                                    ),
                                    canvasSize: canvasSize
                                )
                            }
                            lastPanScreenPoint = value.location

                        case .standalonePoints:
                            return

                        case .points:
                            let current = unproject(value.location, canvasSize: canvasSize)
                            if activeDragTarget == nil && rubberBandStart == nil {
                                if controller.isGeometrySelectionDragGestureActive ||
                                    canBeginSelectedPointGroupDrag(at: value.startLocation, canvasSize: canvasSize) {
                                    activeSelectionCanvasDrag = true
                                    controller.beginGeometrySelectionDragGesture()
                                    let start = unproject(value.startLocation, canvasSize: canvasSize)
                                    controller.updateGeometrySelectionDragGesture(delta: current - start)
                                    controller.updateGeometryEditorAutoWeldCandidates()
                                    lastDragWorldPoint = start
                                } else if hasPointGroupSelection &&
                                            !additiveSelectionModifierActive &&
                                            !toggleSelectionModifierActive {
                                    rubberBandStart = value.startLocation
                                    rubberBandAddsToSelection = false
                                } else {
                                    activeDragTarget = hitTestPoint(at: value.location, canvasSize: canvasSize)
                                    if let target = activeDragTarget {
                                        selectPointStack(target, additive: additiveSelectionModifierActive, toggle: toggleSelectionModifierActive)
                                        activeClickOnlySelection = additiveSelectionModifierActive || toggleSelectionModifierActive
                                        lastDragWorldPoint = current
                                    } else {
                                        rubberBandStart = value.startLocation
                                        rubberBandAddsToSelection = additiveSelectionModifierActive || toggleSelectionModifierActive
                                    }
                                }
                            }
                            if activeSelectionCanvasDrag {
                                let start = unproject(value.startLocation, canvasSize: canvasSize)
                                controller.updateGeometrySelectionDragGesture(delta: current - start)
                                controller.updateGeometryEditorAutoWeldCandidates()
                                return
                            }
                            if activeDragTarget == nil {
                                rubberBandEnd = value.location
                                return
                            }
                            guard activeDragTarget != nil,
                                  !activeClickOnlySelection,
                                  let previous = lastDragWorldPoint
                            else { return }
                            let start = unproject(value.startLocation, canvasSize: canvasSize)
                            let totalDelta = current - start
                            guard dragUndoRecorded || totalDelta.length > 0.002 else { return }
                            let delta = current - previous
                            guard delta.length > 0.0000001 else { return }
                            if !dragUndoRecorded {
                                controller.recordGeometryEditorUndoSnapshot()
                                dragUndoRecorded = true
                            }
                            controller.moveSelectedGeometryPoints(by: delta)
                            controller.updateGeometryEditorAutoWeldCandidates()
                            lastDragWorldPoint = current

                        case .polygons:
                            let current = unproject(value.location, canvasSize: canvasSize)
                            if activePolygonDragTarget == nil && rubberBandStart == nil {
                                activePolygonDragTarget = hitTestPolygon(at: value.startLocation, canvasSize: canvasSize)
                                if let target = activePolygonDragTarget {
                                    if !controller.geometryEditorSelection.polygonIDs.contains(target.polygonID) ||
                                        controller.geometryEditorSelection.layerID != target.layerID ||
                                        !controller.geometryEditorSelection.pointIDs.isEmpty ||
                                        !controller.geometryEditorSelection.segmentIDs.isEmpty {
                                        controller.selectGeometryPolygon(
                                            layerID: target.layerID,
                                            polygonID: target.polygonID,
                                            additive: additiveSelectionModifierActive,
                                            toggle: toggleSelectionModifierActive
                                        )
                                    }
                                    lastDragWorldPoint = current
                                } else {
                                    rubberBandStart = value.startLocation
                                    rubberBandAddsToSelection = additiveSelectionModifierActive || toggleSelectionModifierActive
                                }
                            }
                            if activePolygonDragTarget == nil {
                                rubberBandEnd = value.location
                                return
                            }
                            guard activePolygonDragTarget != nil,
                                  let previous = lastDragWorldPoint
                            else { return }
                            if !dragUndoRecorded {
                                controller.recordGeometryEditorUndoSnapshot()
                                dragUndoRecorded = true
                            }
                            controller.moveSelectedGeometryPolygons(by: current - previous)
                            controller.updateGeometryEditorAutoWeldCandidates()
                            lastDragWorldPoint = current

                        case .openCurves:
                            let current = unproject(value.location, canvasSize: canvasSize)
                            if activeOpenCurveDragTarget == nil && rubberBandStart == nil {
                                activeOpenCurveDragTarget = hitTestOpenCurve(at: value.startLocation, canvasSize: canvasSize)
                                if let target = activeOpenCurveDragTarget {
                                    if !controller.geometryEditorSelection.openCurveIDs.contains(target.openCurveID) ||
                                        controller.geometryEditorSelection.layerID != target.layerID ||
                                        !controller.geometryEditorSelection.pointIDs.isEmpty ||
                                        !controller.geometryEditorSelection.segmentIDs.isEmpty {
                                        controller.selectGeometryOpenCurve(
                                            layerID: target.layerID,
                                            openCurveID: target.openCurveID,
                                            additive: additiveSelectionModifierActive,
                                            toggle: toggleSelectionModifierActive
                                        )
                                    }
                                    lastDragWorldPoint = current
                                } else {
                                    rubberBandStart = value.startLocation
                                    rubberBandAddsToSelection = additiveSelectionModifierActive || toggleSelectionModifierActive
                                }
                            }
                            if activeOpenCurveDragTarget == nil {
                                rubberBandEnd = value.location
                                return
                            }
                            guard activeOpenCurveDragTarget != nil,
                                  let previous = lastDragWorldPoint
                            else { return }
                            if !dragUndoRecorded {
                                controller.recordGeometryEditorUndoSnapshot()
                                dragUndoRecorded = true
                            }
                            controller.moveSelectedGeometryPolygons(by: current - previous)
                            controller.updateGeometryEditorAutoWeldCandidates()
                            lastDragWorldPoint = current

                        case .edges:
                            let current = unproject(value.location, canvasSize: canvasSize)
                            if activeSegmentDragTarget == nil && rubberBandStart == nil {
                                if controller.isGeometrySelectionDragGestureActive ||
                                    canBeginSelectedSegmentGroupDrag(at: value.startLocation, canvasSize: canvasSize) {
                                    activeSelectionCanvasDrag = true
                                    controller.beginGeometrySelectionDragGesture()
                                    let start = unproject(value.startLocation, canvasSize: canvasSize)
                                    controller.updateGeometrySelectionDragGesture(delta: current - start)
                                    controller.updateGeometryEditorAutoWeldCandidates()
                                    lastDragWorldPoint = start
                                } else if hasSegmentGroupSelection &&
                                            !additiveSelectionModifierActive &&
                                            !toggleSelectionModifierActive {
                                    rubberBandStart = value.startLocation
                                    rubberBandAddsToSelection = false
                                } else {
                                    activeSegmentDragTarget = hitTestSegment(at: value.startLocation, canvasSize: canvasSize)
                                    if let target = activeSegmentDragTarget {
                                        selectSegment(target, additive: additiveSelectionModifierActive, toggle: toggleSelectionModifierActive)
                                        lastDragWorldPoint = current
                                    } else {
                                        rubberBandStart = value.startLocation
                                        rubberBandAddsToSelection = additiveSelectionModifierActive || toggleSelectionModifierActive
                                    }
                                }
                            }
                            if activeSelectionCanvasDrag {
                                let start = unproject(value.startLocation, canvasSize: canvasSize)
                                controller.updateGeometrySelectionDragGesture(delta: current - start)
                                controller.updateGeometryEditorAutoWeldCandidates()
                                return
                            }
                            if activeSegmentDragTarget == nil {
                                rubberBandEnd = value.location
                                return
                            }
                            guard activeSegmentDragTarget != nil,
                                  let previous = lastDragWorldPoint
                            else { return }
                            if !dragUndoRecorded {
                                controller.recordGeometryEditorUndoSnapshot()
                                dragUndoRecorded = true
                            }
                            controller.moveSelectedGeometrySegments(by: current - previous)
                            lastDragWorldPoint = current

                        case .freehand:
                            let point = unproject(value.location, canvasSize: canvasSize)
                            let pressure = currentPressure()
                            if controller.geometryEditorFreehandPoints.isEmpty {
                                controller.beginGeometryFreehandStroke(at: point, pressure: pressure)
                            } else {
                                controller.appendGeometryFreehandPoint(point, pressure: pressure)
                            }

                        case .pressureTrace:
                            let point = unproject(value.location, canvasSize: canvasSize)
                            let pressure = currentPressure()
                            if controller.geometryEditorPressureTracePoints.isEmpty {
                                controller.beginGeometryPressureTrace(at: point, pressure: pressure)
                            } else {
                                controller.appendGeometryPressureTracePoint(point, pressure: pressure)
                            }

                        case .meshExtend:
                            let point = unproject(value.location, canvasSize: canvasSize)
                            if controller.geometryEditorMeshExtendDraft == nil {
                                if let target = hitTestSegment(at: value.startLocation, canvasSize: canvasSize) {
                                    controller.beginGeometryMeshExtend(
                                        layerID: target.layerID,
                                        polygonID: target.polygonID,
                                        openCurveID: target.openCurveID,
                                        segmentID: target.segmentID,
                                        apex: point
                                    )
                                }
                            } else if controller.geometryEditorMeshExtendDraft?.isPreviewActive == false {
                                if activeMeshAnchorIndex == nil && !activeMeshPreviewDrag {
                                    activeMeshAnchorIndex = hitTestMeshConfirmedAnchor(
                                        at: value.startLocation,
                                        canvasSize: canvasSize
                                    )
                                }
                                if let index = activeMeshAnchorIndex {
                                    controller.updateGeometryMeshExtendConfirmedAnchor(index: index, to: point)
                                } else {
                                    controller.beginGeometryMeshExtendPreviewDrag(
                                        from: unproject(value.startLocation, canvasSize: canvasSize),
                                        to: point
                                    )
                                    activeMeshPreviewDrag = controller.isGeometryMeshExtendPreviewActive
                                }
                            } else {
                                controller.updateGeometryMeshExtendDraft(apex: point)
                                activeMeshPreviewDrag = true
                            }

                        case .pointByPoint:
                            return

                        case .knife:
                            let point = unproject(value.location, canvasSize: canvasSize)
                            if controller.geometryEditorKnifeLine == nil {
                                controller.beginGeometryKnifeLine(at: unproject(value.startLocation, canvasSize: canvasSize))
                            }
                            controller.updateGeometryKnifeLine(to: point)

                        case .displacementExtrude, .scaleExtrude:
                            let point = unproject(value.location, canvasSize: canvasSize)
                            if controller.geometryEditorExtrudeDraft == nil {
                                controller.beginGeometryExtrudeDrag(at: unproject(value.startLocation, canvasSize: canvasSize))
                            }
                            controller.updateGeometryExtrudeDrag(to: point)
                        }
                    }
                    .onEnded { value in
                        switch controller.geometryEditorTool {
                        case .panView:
                            lastPanScreenPoint = nil

                        case .standalonePoints:
                            controller.createStandalonePointGeometry(at: unproject(value.location, canvasSize: canvasSize))

                        case .pointByPoint:
                            controller.appendGeometryDraftPoint(unproject(value.location, canvasSize: canvasSize))
                        case .freehand:
                            controller.finaliseGeometryFreehandStroke()
                        case .pressureTrace:
                            controller.finaliseGeometryPressureTrace()
                        case .meshExtend:
                            if controller.geometryEditorMeshExtendDraft == nil,
                               let target = hitTestSegment(at: value.location, canvasSize: canvasSize) {
                                controller.beginGeometryMeshExtend(
                                    layerID: target.layerID,
                                    polygonID: target.polygonID,
                                    openCurveID: target.openCurveID,
                                    segmentID: target.segmentID,
                                    apex: unproject(value.location, canvasSize: canvasSize)
                                )
                            } else if activeMeshPreviewDrag {
                                controller.continueGeometryMeshExtendDraft()
                            }
                            activeMeshAnchorIndex = nil
                            activeMeshPreviewDrag = false
                            activeSegmentDragTarget = nil
                            lastDragWorldPoint = nil
                            dragUndoRecorded = false
                        case .points:
                            if activeSelectionCanvasDrag {
                                controller.executeGeometryEditorPendingAutoWelds()
                                controller.endGeometrySelectionDragGesture()
                            } else if activeDragTarget == nil,
                               let start = rubberBandStart,
                               let end = rubberBandEnd,
                               rubberBandRect(start: start, end: end).width > 4,
                               rubberBandRect(start: start, end: end).height > 4 {
                                selectPoints(in: rubberBandRect(start: start, end: end), canvasSize: canvasSize, additive: rubberBandAddsToSelection)
                            } else if activeDragTarget == nil,
                                      let target = hitTestPoint(at: value.location, canvasSize: canvasSize) {
                                selectPointStack(target, additive: additiveSelectionModifierActive, toggle: toggleSelectionModifierActive)
                            } else if activeDragTarget == nil {
                                controller.clearGeometryEditorSelection()
                            }
                            activeDragTarget = nil
                            activeSelectionCanvasDrag = false
                            activeClickOnlySelection = false
                            lastDragWorldPoint = nil
                            controller.clearGeometryEditorAutoWeldCandidates()
                            rubberBandStart = nil
                            rubberBandEnd = nil
                            rubberBandAddsToSelection = false
                            dragUndoRecorded = false
                        case .edges:
                            if activeSelectionCanvasDrag {
                                controller.executeGeometryEditorPendingAutoWelds()
                                controller.endGeometrySelectionDragGesture()
                            } else if activeSegmentDragTarget == nil,
                               let start = rubberBandStart,
                               let end = rubberBandEnd,
                               rubberBandRect(start: start, end: end).width > 4,
                               rubberBandRect(start: start, end: end).height > 4 {
                                selectSegments(in: rubberBandRect(start: start, end: end), canvasSize: canvasSize, additive: rubberBandAddsToSelection)
                            } else if activeSegmentDragTarget == nil,
                               let target = hitTestSegment(at: value.location, canvasSize: canvasSize) {
                                selectSegment(target, additive: additiveSelectionModifierActive, toggle: toggleSelectionModifierActive)
                            } else if activeSegmentDragTarget == nil {
                                controller.clearGeometryEditorSelection()
                            }
                            activeSegmentDragTarget = nil
                            activeSelectionCanvasDrag = false
                            lastDragWorldPoint = nil
                            controller.clearGeometryEditorAutoWeldCandidates()
                            rubberBandStart = nil
                            rubberBandEnd = nil
                            rubberBandAddsToSelection = false
                            dragUndoRecorded = false
                        case .polygons:
                            if activePolygonDragTarget == nil,
                               let start = rubberBandStart,
                               let end = rubberBandEnd,
                               rubberBandRect(start: start, end: end).width > 4,
                               rubberBandRect(start: start, end: end).height > 4 {
                                selectPolygons(
                                    in: rubberBandRect(start: start, end: end),
                                    canvasSize: canvasSize,
                                    additive: rubberBandAddsToSelection
                                )
                            } else if activePolygonDragTarget == nil,
                                      let target = hitTestPolygon(at: value.location, canvasSize: canvasSize) {
                                controller.selectGeometryPolygon(
                                    layerID: target.layerID,
                                    polygonID: target.polygonID,
                                    additive: additiveSelectionModifierActive,
                                    toggle: toggleSelectionModifierActive
                                )
                            } else if activePolygonDragTarget == nil {
                                controller.clearGeometryEditorSelection()
                            }
                            activePolygonDragTarget = nil
                            lastDragWorldPoint = nil
                            controller.executeGeometryEditorPendingAutoWelds()
                            rubberBandStart = nil
                            rubberBandEnd = nil
                            rubberBandAddsToSelection = false
                            dragUndoRecorded = false
                        case .openCurves:
                            if activeOpenCurveDragTarget == nil,
                               let start = rubberBandStart,
                               let end = rubberBandEnd,
                               rubberBandRect(start: start, end: end).width > 4,
                               rubberBandRect(start: start, end: end).height > 4 {
                                selectOpenCurves(
                                    in: rubberBandRect(start: start, end: end),
                                    canvasSize: canvasSize,
                                    additive: rubberBandAddsToSelection
                                )
                            } else if activeOpenCurveDragTarget == nil,
                               let target = hitTestOpenCurve(at: value.location, canvasSize: canvasSize) {
                                controller.selectGeometryOpenCurve(
                                    layerID: target.layerID,
                                    openCurveID: target.openCurveID,
                                    additive: additiveSelectionModifierActive,
                                    toggle: toggleSelectionModifierActive
                                )
                            } else if activeOpenCurveDragTarget == nil {
                                controller.clearGeometryEditorSelection()
                            }
                            activeOpenCurveDragTarget = nil
                            lastDragWorldPoint = nil
                            controller.executeGeometryEditorPendingAutoWelds()
                            rubberBandStart = nil
                            rubberBandEnd = nil
                            rubberBandAddsToSelection = false
                            dragUndoRecorded = false
                        case .knife:
                            controller.updateGeometryKnifeLine(to: unproject(value.location, canvasSize: canvasSize))
                            controller.finishGeometryKnifeCut()

                        case .displacementExtrude, .scaleExtrude:
                            controller.updateGeometryExtrudeDrag(to: unproject(value.location, canvasSize: canvasSize))
                            controller.finishGeometryExtrude()
                        }
                    }
            )
            .background(
                GeometryKeyCaptureView { event in
                    guard controller.isGeometryEditorActive else { return false }
                    let key  = event.charactersIgnoringModifiers?.lowercased() ?? ""
                    let cmd  = event.modifierFlags.contains(.command)
                    let shft = event.modifierFlags.contains(.shift)

                    // ⌘Z / ⌘⇧Z — undo/redo
                    if cmd && key == "z" {
                        if shft { controller.redoGeometryEdit() }
                        else    { controller.undoGeometryEdit() }
                        return true
                    }
                    // ⌘X / ⌘C / ⌘V — cut / copy / paste (cut and paste blocked when morph locked)
                    if cmd && key == "x" {
                        if !controller.isCurrentGeometryMorphTargetLocked { controller.cutSelectedGeometry() }
                        return true
                    }
                    if cmd && key == "c" { controller.copySelectedGeometry(); return true }
                    if cmd && key == "v" {
                        if !controller.isCurrentGeometryMorphTargetLocked { controller.pasteGeometry() }
                        return true
                    }
                    // ⌫ Delete key (keyCode 51) — delete selected geometry (blocked when morph locked)
                    if !cmd && event.keyCode == 51 {
                        if !controller.isCurrentGeometryMorphTargetLocked {
                            controller.deleteSelectedGeometry()
                        }
                        return true
                    }
                    // p — finalise polygon/open-curve draft
                    if key == "p" {
                        controller.finaliseGeometryDraftPolygon()
                        return true
                    }
                    // Escape — cancel mesh extend draft
                    if key == "\u{1B}" {
                        controller.cancelGeometryMeshExtendDraft()
                        return true
                    }
                    return false
                }
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let (scale, origin) = viewTransform(size: size)
        let projectPoint: (Vector2D) -> CGPoint = { project($0, scale: scale, origin: origin) }

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.105, green: 0.108, blue: 0.12)))
        drawReferenceImage(ctx: ctx, project: projectPoint)
        drawGrid(ctx: ctx, size: size, project: projectPoint)

        for layer in document.layers where layerCanDraw(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                draw(
                    polygon: polygon,
                    isEditable: layerCanEdit(layer),
                    ctx: ctx,
                    project: projectPoint
                )
            }
            for curve in layer.openCurves where curve.isVisible {
                draw(
                    curve: curve,
                    isEditable: layerCanEdit(layer),
                    ctx: ctx,
                    project: projectPoint
                )
            }
            for point in layer.points where point.isVisible {
                draw(
                    standalonePoint: point,
                    isEditable: layerCanEdit(layer),
                    ctx: ctx,
                    project: projectPoint
                )
            }
        }

        if selectedLayerCanEdit {
            drawDraft(ctx: ctx, project: projectPoint)
            drawMeshExtendPreview(ctx: ctx, project: projectPoint)
            drawFreehandPreview(ctx: ctx, project: projectPoint)
            drawPressureTracePreview(ctx: ctx, project: projectPoint)
        }
        drawKnifeLine(ctx: ctx, project: projectPoint)
        drawExtrudePreview(ctx: ctx, project: projectPoint)
        drawRubberBand(ctx: ctx)
    }

    private func drawReferenceImage(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        guard controller.geometryEditorShowsReferenceImage,
              let image = controller.geometryEditorReferenceImage
        else { return }
        let topLeft = project(Vector2D(x: -0.52, y: -0.52))
        let bottomRight = project(Vector2D(x: 0.52, y: 0.52))
        let bounds = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        guard bounds.width > 1, bounds.height > 1 else { return }

        let imageSize = image.size
        let imageAspect = imageSize.width > 0 && imageSize.height > 0
            ? imageSize.width / imageSize.height
            : 1
        let boundsAspect = bounds.width / bounds.height
        let drawSize: CGSize
        if imageAspect > boundsAspect {
            drawSize = CGSize(width: bounds.width, height: bounds.width / imageAspect)
        } else {
            drawSize = CGSize(width: bounds.height * imageAspect, height: bounds.height)
        }
        let rect = CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        var imageContext = ctx
        imageContext.opacity = max(0, min(1, controller.geometryEditorReferenceImageOpacity))
        imageContext.draw(Image(nsImage: image), in: rect)
        imageContext.fill(Path(bounds), with: .color(Color.white.opacity(0.18)))
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize, project: (Vector2D) -> CGPoint) {
        // Use min/max so the rect is always well-formed regardless of Y orientation.
        let c1 = project(Vector2D(x: -0.52, y: -0.52))
        let c2 = project(Vector2D(x:  0.52, y:  0.52))
        let border = Path(CGRect(
            x: min(c1.x, c2.x), y: min(c1.y, c2.y),
            width: abs(c2.x - c1.x), height: abs(c2.y - c1.y)
        ))
        ctx.stroke(border, with: .color(Color.white.opacity(0.28)), lineWidth: 1)

        guard controller.geometryEditorShowsGrid else { return }
        switch controller.geometryEditorGridDetail {
        case .quadrants:
            break
        case .standard:
            drawGridLines(ctx: ctx, step: 0.104, color: Color.white.opacity(0.08), lineWidth: 1, project: project)
        case .fine:
            drawGridLines(ctx: ctx, step: 0.026, color: Color.gray.opacity(0.18), lineWidth: 0.55, project: project)
            drawGridLines(ctx: ctx, step: 0.104, color: Color(red: 0.10, green: 0.22, blue: 0.38).opacity(0.75), lineWidth: 0.8, project: project)
            drawGridLines(ctx: ctx, step: 0.26, color: Color(red: 0.28, green: 0.46, blue: 0.72).opacity(0.72), lineWidth: 1.0, project: project)
        }
        var axes = Path()
        axes.move(to: project(Vector2D(x: 0, y: -0.52)))
        axes.addLine(to: project(Vector2D(x: 0, y: 0.52)))
        axes.move(to: project(Vector2D(x: -0.52, y: 0)))
        axes.addLine(to: project(Vector2D(x: 0.52, y: 0)))
        ctx.stroke(axes, with: .color(Color.white.opacity(0.34)), lineWidth: 1.1)
    }

    private func drawGridLines(
        ctx: GraphicsContext,
        step: Double,
        color: Color,
        lineWidth: CGFloat,
        project: (Vector2D) -> CGPoint
    ) {
        var path = Path()
        var value = -0.52
        while value <= 0.52001 {
            path.move(to: project(Vector2D(x: value, y: -0.52)))
            path.addLine(to: project(Vector2D(x: value, y: 0.52)))
            path.move(to: project(Vector2D(x: -0.52, y: value)))
            path.addLine(to: project(Vector2D(x: 0.52, y: value)))
            value += step
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func draw(
        polygon: EditableClosedPolygon,
        isEditable: Bool,
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
        let strokeColor = isEditable
            ? Color(red: 0.36, green: 0.82, blue: 0.50)
            : Color.gray.opacity(0.7)
        let pressureColor = isEditable
            ? Color.orange
            : Color.gray.opacity(0.7)
        let handleColor = isEditable
            ? Color(red: 0.24, green: 0.50, blue: 0.34).opacity(0.7)
            : Color.gray.opacity(0.35)

        if controller.geometryEditorShowsControlPoints {
            var handles = Path()
            for segment in polygon.segments {
                guard let a0 = pointMap[segment.startAnchorID],
                      let c0 = pointMap[segment.controlOutID],
                      let c1 = pointMap[segment.controlInID],
                      let a1 = pointMap[segment.endAnchorID]
                else { continue }
                handles.move(to: project(a0))
                handles.addLine(to: project(c0))
                handles.move(to: project(a1))
                handles.addLine(to: project(c1))
            }
            ctx.stroke(handles, with: .color(handleColor), lineWidth: 0.8)
        }
        var path = Path()
        var didMove = false
        var weldedPath = Path()
        for segment in polygon.segments {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            if !didMove {
                path.move(to: project(a0))
                didMove = true
            }
            path.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            if isEditable && isWelded(segment) {
                weldedPath.move(to: project(a0))
                weldedPath.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            }
            if isEditable && isAutoWeldCandidate(segment.id) {
                weldedPath.move(to: project(a0))
                weldedPath.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            }
        }
        path.closeSubpath()
        if isPolygonSelected(polygon) {
            ctx.fill(path, with: .color(Color(red: 0.36, green: 0.82, blue: 0.50).opacity(0.12)))
            ctx.stroke(path, with: .color(Color.white.opacity(0.8)), lineWidth: 3.0)
        }
        ctx.stroke(weldedPath, with: .color(weldedEdgeColor.opacity(0.95)), lineWidth: 3.1)
        if hasPressureVariation(polygon.pressures) || hasPressureProfileVariation(polygon.segmentPressureProfiles) {
            drawPressureSegments(
                segments: polygon.segments,
                pointMap: pointMap,
                pressures: polygon.pressures,
                pressureProfile: { polygon.pressureProfile(for: $0) },
                closed: true,
                ctx: ctx,
                project: project,
                color: pressureColor
            )
        } else {
            ctx.stroke(path, with: .color(strokeColor), lineWidth: isEditable ? 1.6 : 1.2)
        }
        drawSelectedSegments(
            polygon: polygon,
            pointMap: pointMap,
            ctx: ctx,
            project: project
        )

        drawPointsBatched(
            points: polygon.points,
            isEditable: isEditable,
            showControls: controller.geometryEditorShowsControlPoints,
            selectionIDs: controller.geometryEditorSelection.pointIDs,
            ctx: ctx,
            project: project
        )
    }

    private func draw(
        curve: EditableOpenCurve,
        isEditable: Bool,
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
        let strokeColor = isEditable
            ? Color(red: 0.36, green: 0.82, blue: 0.50)
            : Color.gray.opacity(0.7)
        let pressureColor = isEditable
            ? Color.orange
            : Color.gray.opacity(0.7)
        let handleColor = isEditable
            ? Color(red: 0.24, green: 0.50, blue: 0.34).opacity(0.7)
            : Color.gray.opacity(0.35)

        var handles = Path()
        var path = Path()
        var weldedPath = Path()
        var didMove = false
        for segment in curve.segments {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            if controller.geometryEditorShowsControlPoints {
                handles.move(to: project(a0))
                handles.addLine(to: project(c0))
                handles.move(to: project(a1))
                handles.addLine(to: project(c1))
            }
            if !didMove {
                path.move(to: project(a0))
                didMove = true
            }
            path.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            if isEditable && isWelded(segment) {
                weldedPath.move(to: project(a0))
                weldedPath.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            }
            if isEditable && isAutoWeldCandidate(segment.id) {
                weldedPath.move(to: project(a0))
                weldedPath.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
            }
        }
        if controller.geometryEditorShowsControlPoints {
            ctx.stroke(handles, with: .color(handleColor), lineWidth: 0.8)
        }
        if isOpenCurveSelected(curve) {
            ctx.stroke(path, with: .color(Color.white.opacity(0.8)), lineWidth: 3.0)
        }
        ctx.stroke(weldedPath, with: .color(weldedEdgeColor.opacity(0.95)), lineWidth: 3.1)
        if hasPressureVariation(curve.pressures) || hasPressureProfileVariation(curve.segmentPressureProfiles) {
            drawPressureSegments(
                segments: curve.segments,
                pointMap: pointMap,
                pressures: curve.pressures,
                pressureProfile: { curve.pressureProfile(for: $0) },
                closed: false,
                ctx: ctx,
                project: project,
                color: pressureColor
            )
        } else {
            ctx.stroke(path, with: .color(strokeColor), lineWidth: isEditable ? 1.6 : 1.2)
        }
        drawSelectedOpenCurveSegments(
            curve: curve,
            pointMap: pointMap,
            ctx: ctx,
            project: project
        )

        drawPointsBatched(
            points: curve.points,
            isEditable: isEditable,
            showControls: controller.geometryEditorShowsControlPoints,
            selectionIDs: controller.geometryEditorSelection.pointIDs,
            ctx: ctx,
            project: project
        )
    }

    private func drawPressureSegments(
        segments: [EditableCubicSegment],
        pointMap: [EditableGeometryID: Vector2D],
        pressures: [Double],
        pressureProfile: (EditableGeometryID) -> [Double]?,
        closed: Bool,
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint,
        color: Color
    ) {
        guard !segments.isEmpty else { return }
        for (index, segment) in segments.enumerated() {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            let p0 = pressureValue(pressures, at: index)
            let p1: Double
            if closed {
                p1 = pressureValue(pressures, at: (index + 1) % max(1, segments.count))
            } else {
                p1 = pressureValue(pressures, at: index + 1)
            }
            let pressure = max(0.05, min(1.0, (p0 + p1) * 0.5))
            if let profile = pressureProfile(segment.id), profile.count >= 2 {
                drawProfiledCubicSegment(
                    a0: a0,
                    c0: c0,
                    c1: c1,
                    a1: a1,
                    pressures: profile,
                    ctx: ctx,
                    project: project,
                    color: color
                )
            } else {
                var segmentPath = Path()
                segmentPath.move(to: project(a0))
                segmentPath.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
                ctx.stroke(
                    segmentPath,
                    with: .color(color.opacity(0.48 + pressure * 0.52)),
                    style: StrokeStyle(lineWidth: 0.8 + CGFloat(pressure) * 3.2, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func drawProfiledCubicSegment(
        a0: Vector2D,
        c0: Vector2D,
        c1: Vector2D,
        a1: Vector2D,
        pressures: [Double],
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint,
        color: Color
    ) {
        let count = pressures.count
        guard count >= 2 else { return }
        for index in 0..<(count - 1) {
            let t0 = Double(index) / Double(count - 1)
            let t1 = Double(index + 1) / Double(count - 1)
            let p0 = cubicPoint(a0, c0, c1, a1, t: t0)
            let p1 = cubicPoint(a0, c0, c1, a1, t: t1)
            let pressure = max(0.05, min(1.0, (pressures[index] + pressures[index + 1]) * 0.5))
            var path = Path()
            path.move(to: project(p0))
            path.addLine(to: project(p1))
            ctx.stroke(
                path,
                with: .color(color.opacity(0.48 + pressure * 0.52)),
                style: StrokeStyle(lineWidth: 0.8 + CGFloat(pressure) * 3.2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func hasPressureVariation(_ pressures: [Double]) -> Bool {
        pressures.contains { abs($0 - 1.0) > 0.01 }
    }

    private func hasPressureProfileVariation(_ profiles: [EditableGeometryID: [Double]]?) -> Bool {
        profiles?.values.contains { hasPressureVariation($0) } ?? false
    }

    private func pressureValue(_ pressures: [Double], at index: Int) -> Double {
        guard !pressures.isEmpty else { return 1.0 }
        let clamped = min(max(index, 0), pressures.count - 1)
        return max(0.05, min(1.0, pressures[clamped]))
    }

    // Batches all point circles for one polygon or curve into at most 4 path fills/strokes,
    // instead of one CGPath allocation + draw call per point (which is O(13 k) for the Farm fence layer).
    private func drawPointsBatched(
        points: [EditableCubicPoint],
        isEditable: Bool,
        showControls: Bool,
        selectionIDs: Set<EditableGeometryID>,
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        guard isEditable else {
            // Non-editable layers: single grey pass, no per-point weld/selection checks.
            var grey = Path()
            for point in points where point.kind == .anchor || showControls {
                let loc = project(point.position)
                let r: CGFloat = point.kind == .anchor ? 3.6 : 2.6
                grey.addEllipse(in: CGRect(x: loc.x - r, y: loc.y - r, width: r * 2, height: r * 2))
            }
            if !grey.isEmpty {
                ctx.fill(grey, with: .color(Color.gray.opacity(0.75)))
            }
            return
        }

        var yellowPath  = Path()
        var weldedPath2 = Path()
        var bluePath    = Path()
        var selOutline  = Path()

        for point in points where point.kind == .anchor || showControls {
            let loc = project(point.position)
            let r: CGFloat = point.kind == .anchor ? 3.6 : 2.6
            let rect = CGRect(x: loc.x - r, y: loc.y - r, width: r * 2, height: r * 2)

            if point.kind == .anchor {
                if isWelded(point.id) {
                    weldedPath2.addEllipse(in: rect)
                } else {
                    yellowPath.addEllipse(in: rect)
                }
            } else {
                bluePath.addEllipse(in: rect)
            }

            if selectionIDs.contains(point.id) {
                let ro = CGRect(
                    x: loc.x - r - 3, y: loc.y - r - 3,
                    width: (r + 3) * 2, height: (r + 3) * 2
                )
                selOutline.addEllipse(in: ro)
            }
        }

        if !yellowPath.isEmpty  { ctx.fill(yellowPath,  with: .color(Color.yellow)) }
        if !weldedPath2.isEmpty { ctx.fill(weldedPath2, with: .color(weldedAnchorColor)) }
        if !bluePath.isEmpty    { ctx.fill(bluePath,    with: .color(Color(red: 0.42, green: 0.62, blue: 1.0))) }
        if !selOutline.isEmpty  { ctx.stroke(selOutline, with: .color(Color.white), lineWidth: 1.2) }
    }

    private func drawPoint(_ point: EditableCubicPoint, isEditable: Bool, ctx: GraphicsContext, at location: CGPoint) {
        let radius: CGFloat = point.kind == .anchor ? 3.6 : 2.6
        let color: Color
        if isEditable {
            if point.kind == .anchor, isWelded(point.id) {
                color = weldedAnchorColor
            } else {
                color = point.kind == .anchor
                    ? Color.yellow
                    : Color(red: 0.42, green: 0.62, blue: 1.0)
            }
        } else {
            color = Color.gray.opacity(0.75)
        }
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: location.x - radius,
                y: location.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(color)
        )
        if isEditable && controller.geometryEditorSelection.pointIDs.contains(point.id) {
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: location.x - radius - 3,
                    y: location.y - radius - 3,
                    width: (radius + 3) * 2,
                    height: (radius + 3) * 2
                )),
                with: .color(Color.white),
                lineWidth: 1.2
            )
        }
    }

    private func draw(
        standalonePoint point: EditableStandalonePoint,
        isEditable: Bool,
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        let location = project(point.position)
        let pressure = max(0.05, min(1.0, point.pressure))
        let color = isEditable && abs(pressure - 1.0) > 0.01
            ? Color.orange
            : (isEditable ? Color.yellow : Color.gray.opacity(0.75))
        let radius: CGFloat = 3.0 + CGFloat(pressure) * 3.0
        ctx.stroke(
            Path(ellipseIn: CGRect(
                x: location.x - radius - 2,
                y: location.y - radius - 2,
                width: (radius + 2) * 2,
                height: (radius + 2) * 2
            )),
            with: .color(color.opacity(0.85)),
            lineWidth: 1.2
        )
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: location.x - radius,
                y: location.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(color)
        )
        if isEditable && controller.geometryEditorSelection.pointIDs.contains(point.id) {
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: location.x - radius - 5,
                    y: location.y - radius - 5,
                    width: (radius + 5) * 2,
                    height: (radius + 5) * 2
                )),
                with: .color(Color.white),
                lineWidth: 1.2
            )
        }
    }

    private func isWelded(_ pointID: EditableGeometryID) -> Bool {
        document.weldedPointIDs(containing: pointID).count > 1
    }

    private func isWelded(_ segment: EditableCubicSegment) -> Bool {
        segment.pointIDs.contains { isWelded($0) }
    }

    private func isAutoWeldCandidate(_ segmentID: EditableGeometryID) -> Bool {
        controller.geometryEditorAutoWeldSegmentIDs.contains(segmentID)
    }

    private func drawDraft(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        let points = controller.geometryEditorDraftPoints
        guard !points.isEmpty else { return }

        if points.count >= 2 {
            var preview = Path()
            preview.move(to: project(points[0]))
            for point in points.dropFirst() {
                preview.addLine(to: project(point))
            }
            ctx.stroke(preview, with: .color(Color.orange.opacity(0.65)), lineWidth: 1.2)
        }

        if points.count >= 3 {
            var closing = Path()
            closing.move(to: project(points[points.count - 1]))
            closing.addLine(to: project(points[0]))
            ctx.stroke(closing, with: .color(Color.orange.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }

        let autoCurvePoints = automaticBezierPoints(for: points)
        if autoCurvePoints.count >= 4 {
            var completed = Path()
            completed.move(to: project(points[0]))
            for base in stride(from: 0, to: autoCurvePoints.count, by: 4) {
                completed.addCurve(
                    to: project(autoCurvePoints[base + 3]),
                    control1: project(autoCurvePoints[base + 1]),
                    control2: project(autoCurvePoints[base + 2])
                )
            }
            ctx.stroke(completed, with: .color(Color.orange), lineWidth: 1.6)
        }

        for point in points {
            let location = project(point)
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: location.x - 4,
                    y: location.y - 4,
                    width: 8,
                    height: 8
                )),
                with: .color(Color.orange)
            )
        }
    }

    private func drawMeshExtendPreview(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        guard let draft = controller.geometryEditorMeshExtendDraft else { return }
        let start = project(draft.start)
        let end = project(draft.end)
        let stableVertices = [draft.start, draft.end] + draft.confirmedAnchors
        var previewVertices = stableVertices
        if draft.isPreviewActive {
            let insertionIndex = max(0, min(draft.confirmedAnchors.count, draft.activeEdgeStartIndex - 1))
            previewVertices.insert(draft.apex, at: insertionIndex + 2)
        }
        var base = Path()
        base.move(to: start)
        base.addCurve(
            to: end,
            control1: project(draft.controlOut),
            control2: project(draft.controlIn)
        )
        ctx.stroke(base, with: .color(Color.white.opacity(0.9)), lineWidth: 3.0)
        ctx.stroke(base, with: .color(Color.orange), lineWidth: 1.6)

        var preview = Path()
        preview.move(to: end)
        for vertex in previewVertices.dropFirst(2) {
            preview.addLine(to: project(vertex))
        }
        preview.addLine(to: start)
        ctx.stroke(
            preview,
            with: .color(Color.orange.opacity(controller.canFinaliseGeometryMeshExtend ? 0.85 : 0.35)),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [6, 4])
        )
        var fill = Path()
        fill.move(to: start)
        for vertex in previewVertices.dropFirst() {
            fill.addLine(to: project(vertex))
        }
        fill.closeSubpath()
        if draft.isPreviewActive || !draft.confirmedAnchors.isEmpty {
            ctx.fill(fill, with: .color(Color.orange.opacity(0.08)))
        }
        for point in draft.confirmedAnchors {
            let location = project(point)
            ctx.fill(
                Path(ellipseIn: CGRect(x: location.x - 4, y: location.y - 4, width: 8, height: 8)),
                with: .color(Color.red.opacity(0.85))
            )
        }
        for index in 1..<stableVertices.count {
            let nextIndex = index == stableVertices.count - 1 ? 0 : index + 1
            let handle = project(Vector2D(
                x: (stableVertices[index].x + stableVertices[nextIndex].x) / 2,
                y: (stableVertices[index].y + stableVertices[nextIndex].y) / 2
            ))
            let isActive = draft.activeEdgeStartIndex == index
            ctx.fill(
                Path(ellipseIn: CGRect(x: handle.x - 6, y: handle.y - 6, width: 12, height: 12)),
                with: .color(Color.red.opacity(isActive ? 1.0 : 0.65))
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: handle.x - 8, y: handle.y - 8, width: 16, height: 16)),
                with: .color(Color.white.opacity(isActive ? 0.9 : 0.45)),
                lineWidth: 1.2
            )
        }
        if draft.isPreviewActive {
            let apex = project(draft.apex)
            ctx.fill(
                Path(ellipseIn: CGRect(x: apex.x - 5, y: apex.y - 5, width: 10, height: 10)),
                with: .color(Color.red)
            )
        }
    }

    private func drawFreehandPreview(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        let points = controller.geometryEditorFreehandPoints
        guard points.count >= 2 else { return }
        let hasPressure = controller.geometryEditorFreehandPressures.contains { $0 < 0.99 }
        drawPressurePolyline(
            points: points,
            pressures: controller.geometryEditorFreehandPressures,
            ctx: ctx,
            project: project,
            color: hasPressure ? Color(red: 0.95, green: 0.58, blue: 1.0) : Color(red: 0.36, green: 0.82, blue: 0.50),
            baseWidth: hasPressure ? 0.9 : 1.7,
            widthRange: hasPressure ? 3.2 : 0.0
        )
        if points.count > 5,
           let last = points.last,
           last.distance(to: points[0]) < 0.021 {
            let start = project(points[0])
            ctx.stroke(
                Path(ellipseIn: CGRect(x: start.x - 8, y: start.y - 8, width: 16, height: 16)),
                with: .color(Color(red: 0.95, green: 0.58, blue: 1.0)),
                lineWidth: 1.4
            )
        }
    }

    private func drawPressureTracePreview(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        drawPressurePolyline(
            points: controller.geometryEditorPressureTracePoints,
            pressures: controller.geometryEditorPressureTracePressures,
            ctx: ctx,
            project: project,
            color: Color(red: 1.0, green: 0.42, blue: 0.22),
            baseWidth: 0.8,
            widthRange: 4.0
        )
    }

    private func drawPressurePolyline(
        points: [Vector2D],
        pressures: [Double],
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint,
        color: Color,
        baseWidth: CGFloat,
        widthRange: CGFloat
    ) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let p0 = pressureValue(pressures, at: index)
            let p1 = pressureValue(pressures, at: index + 1)
            let pressure = CGFloat((p0 + p1) * 0.5)
            var path = Path()
            path.move(to: project(points[index]))
            path.addLine(to: project(points[index + 1]))
            ctx.stroke(
                path,
                with: .color(color.opacity(0.48 + Double(pressure) * 0.52)),
                style: StrokeStyle(lineWidth: baseWidth + pressure * widthRange, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawKnifeLine(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        guard let line = controller.geometryEditorKnifeLine,
              line.start.distance(to: line.end) > 0.000_1
        else { return }
        let start = project(line.start)
        let end = project(line.end)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        ctx.stroke(
            path,
            with: .color(Color.red.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])
        )
        for point in [start, end] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                with: .color(Color.red.opacity(0.9))
            )
        }
    }

    private func drawExtrudePreview(ctx: GraphicsContext, project: (Vector2D) -> CGPoint) {
        guard let draft = controller.geometryEditorExtrudeDraft,
              let document = controller.geometryEditorDocument
        else { return }

        let sources = controller.extrudePreviewSegments(in: document)
        guard !sources.isEmpty else { return }

        let topColor = Color(red: 0.8, green: 0.45, blue: 1.0).opacity(0.9)
        let connColor = Color.white.opacity(0.28)
        let topStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 3])
        let connStyle = StrokeStyle(lineWidth: 1.0, lineCap: .round)

        for seg in sources {
            guard let oA0 = document.point(id: seg.startAnchorID)?.position,
                  let oC1 = document.point(id: seg.controlOutID)?.position,
                  let oC2 = document.point(id: seg.controlInID)?.position,
                  let oA3 = document.point(id: seg.endAnchorID)?.position
            else { continue }

            let lA0: Vector2D
            let lC1: Vector2D
            let lC2: Vector2D
            let lA3: Vector2D

            switch draft.mode {
            case .displacement:
                let d = draft.dragDelta
                lA0 = oA0 + d; lC1 = oC1 + d; lC2 = oC2 + d; lA3 = oA3 + d
            case .scale:
                let centroid = sources.reduce(Vector2D.zero) { acc, s in
                    var sum = acc
                    if let p = document.point(id: s.startAnchorID)?.position { sum = sum + p }
                    if let p = document.point(id: s.endAnchorID)?.position   { sum = sum + p }
                    return sum
                } * (1.0 / Double(sources.count * 2))
                let f = draft.scaleFactor
                func sc(_ p: Vector2D) -> Vector2D { centroid + (p - centroid) * f }
                lA0 = sc(oA0); lC1 = sc(oC1); lC2 = sc(oC2); lA3 = sc(oA3)
            }

            // Top edge (displaced/scaled, direction reversed: lA3→lA0 with lC2,lC1)
            var topPath = Path()
            topPath.move(to: project(lA3))
            topPath.addCurve(to: project(lA0), control1: project(lC2), control2: project(lC1))
            ctx.stroke(topPath, with: .color(topColor), style: topStyle)

            // Left and right connectors
            var connPath = Path()
            connPath.move(to: project(oA0)); connPath.addLine(to: project(lA0))
            connPath.move(to: project(oA3)); connPath.addLine(to: project(lA3))
            ctx.stroke(connPath, with: .color(connColor), style: connStyle)
        }
    }


    private func currentPressure() -> Double {
        let pressure = Double(NSApp.currentEvent?.pressure ?? 1.0)
        return pressure > 0 ? min(max(pressure, 0.05), 1.0) : 1.0
    }

    private func project(_ point: Vector2D, scale: CGFloat, origin: CGPoint) -> CGPoint {
        // Y-up: positive Y is toward the top of the canvas (smaller screen-Y).
        // origin is the screen position of the top-left corner (world x=-0.52, y=+0.52).
        CGPoint(
            x: origin.x + CGFloat((point.x + 0.52) * 1000) * scale,
            y: origin.y + CGFloat((0.52 - point.y) * 1000) * scale
        )
    }

    private func viewTransform(size: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let canvasSide = min(size.width, size.height)
        let scale = (canvasSide / 1040) * CGFloat(controller.geometryEditorViewZoom)
        let centre = controller.geometryEditorViewCentre
        // origin = top-left corner of the canvas square in screen space.
        // In Y-up, that corner is world (−0.52, +0.52).  The view centre maps to the
        // screen midpoint, so: origin.y = screenMid − project_y_offset_for_centre
        // project(centre.y) = origin.y + (0.52 − centre.y)*1000*scale = screenMid
        // → origin.y = screenMid − (0.52 − centre.y)*1000*scale
        let origin = CGPoint(
            x: size.width  / 2 - CGFloat((centre.x + 0.52) * 1000) * scale,
            y: size.height / 2 - CGFloat((0.52 - centre.y) * 1000) * scale
        )
        return (scale, origin)
    }

    private func viewTransform(canvasSize: CGFloat) -> (scale: CGFloat, origin: CGPoint) {
        viewTransform(size: CGSize(width: canvasSize, height: canvasSize))
    }

    private func unproject(_ point: CGPoint, canvasSize: CGFloat) -> Vector2D {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        let clampedX = min(max(point.x, 0), canvasSize)
        let clampedY = min(max(point.y, 0), canvasSize)
        return Vector2D(
            x:  Double((clampedX - origin.x) / (1000 * scale)) - 0.52,
            y: -(Double((clampedY - origin.y) / (1000 * scale)) - 0.52)
        )
    }

    private var hasPointGroupSelection: Bool {
        controller.geometryEditorSelection.pointIDs.count > 1
    }

    private var hasSegmentGroupSelection: Bool {
        controller.geometryEditorSelection.segmentIDs.count > 1
    }

    private func canBeginSelectedPointGroupDrag(at location: CGPoint, canvasSize: CGFloat) -> Bool {
        guard hasPointGroupSelection,
              !additiveSelectionModifierActive,
              !toggleSelectionModifierActive,
              let bounds = selectedPointGroupBounds(canvasSize: canvasSize)
        else { return false }
        return bounds.insetBy(dx: -14, dy: -14).contains(location)
    }

    private func canBeginSelectedSegmentGroupDrag(at location: CGPoint, canvasSize: CGFloat) -> Bool {
        guard hasSegmentGroupSelection,
              !additiveSelectionModifierActive,
              !toggleSelectionModifierActive,
              let bounds = selectedSegmentGroupBounds(canvasSize: canvasSize)
        else { return false }
        return bounds.insetBy(dx: -14, dy: -14).contains(location)
    }

    private func selectedPointGroupBounds(canvasSize: CGFloat) -> CGRect? {
        let selection = controller.geometryEditorSelection
        guard let layerID = selection.layerID, !selection.pointIDs.isEmpty else { return nil }
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var points: [CGPoint] = []

        for layer in document.layers where layer.id == layerID && layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                for point in polygon.points where selection.pointIDs.contains(point.id) {
                    points.append(project(point.position, scale: scale, origin: origin))
                }
            }
            for curve in layer.openCurves where curve.isVisible {
                for point in curve.points where selection.pointIDs.contains(point.id) {
                    points.append(project(point.position, scale: scale, origin: origin))
                }
            }
            for point in layer.points where point.isVisible && selection.pointIDs.contains(point.id) {
                points.append(project(point.position, scale: scale, origin: origin))
            }
        }

        return bounds(for: points)
    }

    private func selectedSegmentGroupBounds(canvasSize: CGFloat) -> CGRect? {
        let selection = controller.geometryEditorSelection
        guard let layerID = selection.layerID, !selection.segmentIDs.isEmpty else { return nil }
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var points: [CGPoint] = []

        for layer in document.layers where layer.id == layerID && layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible && selection.polygonIDs.contains(polygon.id) {
                let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
                for segment in polygon.segments where selection.segmentIDs.contains(segment.id) {
                    for pointID in segment.pointIDs {
                        if let point = pointMap[pointID] {
                            points.append(project(point, scale: scale, origin: origin))
                        }
                    }
                }
            }
            for curve in layer.openCurves where curve.isVisible && selection.openCurveIDs.contains(curve.id) {
                let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
                for segment in curve.segments where selection.segmentIDs.contains(segment.id) {
                    for pointID in segment.pointIDs {
                        if let point = pointMap[pointID] {
                            points.append(project(point, scale: scale, origin: origin))
                        }
                    }
                }
            }
        }

        return bounds(for: points)
    }

    private func bounds(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func hitTestPoint(at location: CGPoint, canvasSize: CGFloat) -> GeometryPointHit? {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var bestHit: GeometryPointHit?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for layer in document.layers where layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                for point in polygon.points {
                    let screen = project(point.position, scale: scale, origin: origin)
                    let distance = hypot(screen.x - location.x, screen.y - location.y)
                    let hitRadius: CGFloat = point.kind == .anchor ? 10 : 8
                    if distance <= hitRadius, distance < bestDistance {
                        bestDistance = distance
                        bestHit = GeometryPointHit(layerID: layer.id, polygonID: polygon.id, openCurveID: nil, standalonePointID: nil, pointID: point.id)
                    }
                }
            }
            for curve in layer.openCurves where curve.isVisible {
                for point in curve.points {
                    let screen = project(point.position, scale: scale, origin: origin)
                    let distance = hypot(screen.x - location.x, screen.y - location.y)
                    let hitRadius: CGFloat = point.kind == .anchor ? 10 : 8
                    if distance <= hitRadius, distance < bestDistance {
                        bestDistance = distance
                        bestHit = GeometryPointHit(layerID: layer.id, polygonID: nil, openCurveID: curve.id, standalonePointID: nil, pointID: point.id)
                    }
                }
            }
            for point in layer.points where point.isVisible {
                let screen = project(point.position, scale: scale, origin: origin)
                let distance = hypot(screen.x - location.x, screen.y - location.y)
                if distance <= 11, distance < bestDistance {
                    bestDistance = distance
                    bestHit = GeometryPointHit(layerID: layer.id, polygonID: nil, openCurveID: nil, standalonePointID: point.id, pointID: point.id)
                }
            }
        }

        return bestHit
    }

    private func hitTestMeshConfirmedAnchor(at location: CGPoint, canvasSize: CGFloat) -> Int? {
        guard let draft = controller.geometryEditorMeshExtendDraft else { return nil }
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, anchor) in draft.confirmedAnchors.enumerated() {
            let screen = project(anchor, scale: scale, origin: origin)
            let distance = hypot(screen.x - location.x, screen.y - location.y)
            if distance <= 12, distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func hitTestSegment(at location: CGPoint, canvasSize: CGFloat) -> GeometrySegmentHit? {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var bestHit: GeometrySegmentHit?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let hitRadius: CGFloat = 14

        for layer in document.layers.reversed() where layerCanEdit(layer) {
            for polygon in layer.polygons.reversed() where polygon.isVisible {
                let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
                for segment in polygon.segments {
                    guard let a0 = pointMap[segment.startAnchorID],
                          let c0 = pointMap[segment.controlOutID],
                          let c1 = pointMap[segment.controlInID],
                          let a1 = pointMap[segment.endAnchorID]
                    else { continue }
                    let distance = distanceToCubic(
                        location,
                        from: project(a0, scale: scale, origin: origin),
                        control1: project(c0, scale: scale, origin: origin),
                        control2: project(c1, scale: scale, origin: origin),
                        to: project(a1, scale: scale, origin: origin)
                    )
                    if distance <= hitRadius, distance < bestDistance {
                        bestDistance = distance
                        bestHit = GeometrySegmentHit(layerID: layer.id, polygonID: polygon.id, openCurveID: nil, segmentID: segment.id)
                    }
                }
            }
            for curve in layer.openCurves.reversed() where curve.isVisible {
                let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
                for segment in curve.segments {
                    guard let a0 = pointMap[segment.startAnchorID],
                          let c0 = pointMap[segment.controlOutID],
                          let c1 = pointMap[segment.controlInID],
                          let a1 = pointMap[segment.endAnchorID]
                    else { continue }
                    let distance = distanceToCubic(
                        location,
                        from: project(a0, scale: scale, origin: origin),
                        control1: project(c0, scale: scale, origin: origin),
                        control2: project(c1, scale: scale, origin: origin),
                        to: project(a1, scale: scale, origin: origin)
                    )
                    if distance <= hitRadius, distance < bestDistance {
                        bestDistance = distance
                        bestHit = GeometrySegmentHit(layerID: layer.id, polygonID: nil, openCurveID: curve.id, segmentID: segment.id)
                    }
                }
            }
        }

        return bestHit
    }

    private func hitTestPolygon(at location: CGPoint, canvasSize: CGFloat) -> GeometryPolygonHit? {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)

        for layer in document.layers.reversed() where layerCanEdit(layer) {
            for polygon in layer.polygons.reversed() where polygon.isVisible {
                // Fast AABB reject before building the full bezier path.
                guard screenBounds(for: polygon, scale: scale, origin: origin).contains(location) else { continue }
                let polygonPath = path(for: polygon, scale: scale, origin: origin)
                if polygonPath.contains(location) {
                    return GeometryPolygonHit(layerID: layer.id, polygonID: polygon.id)
                }
            }
        }
        return nil
    }

    private func hitTestOpenCurve(at location: CGPoint, canvasSize: CGFloat) -> GeometryOpenCurveHit? {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var bestHit: GeometryOpenCurveHit?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let hitRadius: CGFloat = 14

        for layer in document.layers.reversed() where layerCanEdit(layer) {
            for curve in layer.openCurves.reversed() where curve.isVisible {
                let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
                for segment in curve.segments {
                    guard let a0 = pointMap[segment.startAnchorID],
                          let c0 = pointMap[segment.controlOutID],
                          let c1 = pointMap[segment.controlInID],
                          let a1 = pointMap[segment.endAnchorID]
                    else { continue }
                    let distance = distanceToCubic(
                        location,
                        from: project(a0, scale: scale, origin: origin),
                        control1: project(c0, scale: scale, origin: origin),
                        control2: project(c1, scale: scale, origin: origin),
                        to: project(a1, scale: scale, origin: origin)
                    )
                    if distance <= hitRadius, distance < bestDistance {
                        bestDistance = distance
                        bestHit = GeometryOpenCurveHit(layerID: layer.id, openCurveID: curve.id)
                    }
                }
            }
        }

        return bestHit
    }

    private func selectPolygons(in rect: CGRect, canvasSize: CGFloat, additive: Bool = false) {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var firstLayerID: EditableGeometryID?
        var selected = Set<EditableGeometryID>()

        for layer in document.layers where layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                let box = screenBounds(for: polygon, scale: scale, origin: origin)
                guard rect.intersects(box) else { continue }
                if firstLayerID == nil {
                    firstLayerID = layer.id
                }
                if firstLayerID == layer.id {
                    selected.insert(polygon.id)
                }
            }
        }

        if let firstLayerID, !selected.isEmpty {
            controller.selectGeometryPolygons(layerID: firstLayerID, polygonIDs: selected, additive: additive)
        } else if !additive {
            controller.clearGeometryEditorSelection()
        }
    }

    private func screenBounds(
        for polygon: EditableClosedPolygon,
        scale: CGFloat,
        origin: CGPoint
    ) -> CGRect {
        let points = polygon.points.map { project($0.position, scale: scale, origin: origin) }
        guard let first = points.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func screenBounds(
        for curve: EditableOpenCurve,
        scale: CGFloat,
        origin: CGPoint
    ) -> CGRect {
        let points = curve.points.map { project($0.position, scale: scale, origin: origin) }
        guard let first = points.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func path(
        for polygon: EditableClosedPolygon,
        scale: CGFloat,
        origin: CGPoint
    ) -> Path {
        let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
        var path = Path()
        var didMove = false
        for segment in polygon.segments {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            if !didMove {
                path.move(to: project(a0, scale: scale, origin: origin))
                didMove = true
            }
            path.addCurve(
                to: project(a1, scale: scale, origin: origin),
                control1: project(c0, scale: scale, origin: origin),
                control2: project(c1, scale: scale, origin: origin)
            )
        }
        path.closeSubpath()
        return path
    }

    private func automaticBezierPoints(for anchors: [Vector2D]) -> [Vector2D] {
        guard anchors.count >= 2 else { return [] }
        let segmentCount = anchors.count - 1
        var points: [Vector2D] = []
        points.reserveCapacity(segmentCount * 4)
        for index in 0..<segmentCount {
            let a0 = anchors[index]
            let a1 = anchors[index + 1]
            let delta = a1 - a0
            points.append(a0)
            points.append(a0 + delta * (1.0 / 3.0))
            points.append(a0 + delta * (2.0 / 3.0))
            points.append(a1)
        }
        return points
    }

    private func drawSelectedSegments(
        polygon: EditableClosedPolygon,
        pointMap: [EditableGeometryID: Vector2D],
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        guard controller.geometryEditorSelection.polygonIDs.contains(polygon.id),
              !controller.geometryEditorSelection.segmentIDs.isEmpty
        else { return }

        var selected = Path()
        for segment in polygon.segments where controller.geometryEditorSelection.segmentIDs.contains(segment.id) {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            selected.move(to: project(a0))
            selected.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
        }
        ctx.stroke(selected, with: .color(Color.white), lineWidth: 4)
        ctx.stroke(selected, with: .color(Color.orange), lineWidth: 2)
    }

    private func drawSelectedOpenCurveSegments(
        curve: EditableOpenCurve,
        pointMap: [EditableGeometryID: Vector2D],
        ctx: GraphicsContext,
        project: (Vector2D) -> CGPoint
    ) {
        guard controller.geometryEditorSelection.openCurveIDs.contains(curve.id),
              !controller.geometryEditorSelection.segmentIDs.isEmpty
        else { return }

        var selected = Path()
        for segment in curve.segments where controller.geometryEditorSelection.segmentIDs.contains(segment.id) {
            guard let a0 = pointMap[segment.startAnchorID],
                  let c0 = pointMap[segment.controlOutID],
                  let c1 = pointMap[segment.controlInID],
                  let a1 = pointMap[segment.endAnchorID]
            else { continue }
            selected.move(to: project(a0))
            selected.addCurve(to: project(a1), control1: project(c0), control2: project(c1))
        }
        ctx.stroke(selected, with: .color(Color.white), lineWidth: 4)
        ctx.stroke(selected, with: .color(Color.orange), lineWidth: 2)
    }

    private func selectPoint(_ target: GeometryPointHit, additive: Bool = false, toggle: Bool = false) {
        if let polygonID = target.polygonID {
            controller.selectGeometryPoint(
                layerID: target.layerID,
                polygonID: polygonID,
                pointID: target.pointID,
                additive: additive,
                toggle: toggle
            )
        } else if let openCurveID = target.openCurveID {
            controller.selectGeometryOpenCurvePoint(
                layerID: target.layerID,
                openCurveID: openCurveID,
                pointID: target.pointID,
                additive: additive,
                toggle: toggle
            )
        } else if let standalonePointID = target.standalonePointID {
            controller.selectGeometryStandalonePoint(
                layerID: target.layerID,
                pointID: standalonePointID,
                additive: additive,
                toggle: toggle
            )
        }
    }

    private func selectPointStack(_ target: GeometryPointHit, additive: Bool = false, toggle: Bool = false) {
        guard !toggle,
              let layer = document.layers.first(where: { $0.id == target.layerID }),
              let targetPosition = pointPosition(id: target.pointID, in: layer)
        else {
            selectPoint(target, additive: additive, toggle: toggle)
            return
        }

        let weldedIDs = document.weldedPointIDs(containing: target.pointID)
        let stackTolerance = 0.002
        var polygonPoints: [(polygonID: EditableGeometryID, pointID: EditableGeometryID)] = []
        var openCurvePoints: [(openCurveID: EditableGeometryID, pointID: EditableGeometryID)] = []
        var standalonePointIDs = Set<EditableGeometryID>()

        for polygon in layer.polygons where polygon.isVisible {
            for point in polygon.points where weldedIDs.contains(point.id) || point.position.distance(to: targetPosition) <= stackTolerance {
                polygonPoints.append((polygon.id, point.id))
            }
        }
        for curve in layer.openCurves where curve.isVisible {
            for point in curve.points where weldedIDs.contains(point.id) || point.position.distance(to: targetPosition) <= stackTolerance {
                openCurvePoints.append((curve.id, point.id))
            }
        }
        for point in layer.points where point.isVisible &&
            (weldedIDs.contains(point.id) || point.position.distance(to: targetPosition) <= stackTolerance) {
            standalonePointIDs.insert(point.id)
        }

        if polygonPoints.count + openCurvePoints.count + standalonePointIDs.count > 1 {
            controller.selectGeometryPoints(
                layerID: target.layerID,
                polygonPoints: polygonPoints,
                openCurvePoints: openCurvePoints,
                standalonePointIDs: standalonePointIDs,
                additive: additive
            )
        } else {
            selectPoint(target, additive: additive, toggle: toggle)
        }
    }

    private func pointPosition(id pointID: EditableGeometryID, in layer: EditableGeometryLayer) -> Vector2D? {
        for polygon in layer.polygons {
            if let point = polygon.point(id: pointID) { return point.position }
        }
        for curve in layer.openCurves {
            if let point = curve.point(id: pointID) { return point.position }
        }
        if let point = layer.points.first(where: { $0.id == pointID }) {
            return point.position
        }
        return nil
    }

    private var additiveSelectionModifierActive: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.shift) || flags.contains(.command)
    }

    private var toggleSelectionModifierActive: Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    private func selectSegment(_ target: GeometrySegmentHit, additive: Bool = false, toggle: Bool = false) {
        if let polygonID = target.polygonID {
            controller.selectGeometrySegment(
                layerID: target.layerID,
                polygonID: polygonID,
                segmentID: target.segmentID,
                additive: additive,
                toggle: toggle
            )
        } else if let openCurveID = target.openCurveID {
            controller.selectGeometryOpenCurveSegment(
                layerID: target.layerID,
                openCurveID: openCurveID,
                segmentID: target.segmentID,
                additive: additive,
                toggle: toggle
            )
        }
    }

    private func drawRubberBand(ctx: GraphicsContext) {
        guard (
            controller.geometryEditorTool == .points ||
            controller.geometryEditorTool == .edges ||
            controller.geometryEditorTool == .openCurves ||
            controller.geometryEditorTool == .polygons
        ),
              let start = rubberBandStart,
              let end = rubberBandEnd
        else { return }
        let rect = rubberBandRect(start: start, end: end)
        guard rect.width > 1, rect.height > 1 else { return }
        let path = Path(rect)
        ctx.fill(path, with: .color(Color.accentColor.opacity(0.12)))
        ctx.stroke(path, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }

    private func rubberBandRect(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func selectPoints(in rect: CGRect, canvasSize: CGFloat, additive: Bool) {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var firstLayerID: EditableGeometryID?
        var polygonPoints: [(polygonID: EditableGeometryID, pointID: EditableGeometryID)] = []
        var openCurvePoints: [(openCurveID: EditableGeometryID, pointID: EditableGeometryID)] = []
        var standalonePointIDs = Set<EditableGeometryID>()

        for layer in document.layers where layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                for point in polygon.points where point.kind == .anchor || controller.geometryEditorShowsControlPoints {
                    let screen = project(point.position, scale: scale, origin: origin)
                    guard rect.contains(screen) else { continue }
                    if firstLayerID == nil {
                        firstLayerID = layer.id
                    }
                    if firstLayerID == layer.id {
                        polygonPoints.append((polygon.id, point.id))
                    }
                }
            }
            for curve in layer.openCurves where curve.isVisible {
                for point in curve.points where point.kind == .anchor || controller.geometryEditorShowsControlPoints {
                    let screen = project(point.position, scale: scale, origin: origin)
                    guard rect.contains(screen) else { continue }
                    if firstLayerID == nil {
                        firstLayerID = layer.id
                    }
                    if firstLayerID == layer.id {
                        openCurvePoints.append((curve.id, point.id))
                    }
                }
            }
            for point in layer.points where point.isVisible {
                let screen = project(point.position, scale: scale, origin: origin)
                guard rect.contains(screen) else { continue }
                if firstLayerID == nil {
                    firstLayerID = layer.id
                }
                if firstLayerID == layer.id {
                    standalonePointIDs.insert(point.id)
                }
            }
        }

        if let firstLayerID, (!polygonPoints.isEmpty || !openCurvePoints.isEmpty || !standalonePointIDs.isEmpty) {
            controller.selectGeometryPoints(
                layerID: firstLayerID,
                polygonPoints: polygonPoints,
                openCurvePoints: openCurvePoints,
                standalonePointIDs: standalonePointIDs,
                additive: additive
            )
        } else if !additive {
            controller.clearGeometryEditorSelection()
        }
    }

    private func selectOpenCurves(in rect: CGRect, canvasSize: CGFloat, additive: Bool) {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var firstLayerID: EditableGeometryID?
        var selected = Set<EditableGeometryID>()

        for layer in document.layers where layerCanEdit(layer) {
            for curve in layer.openCurves where curve.isVisible {
                let box = screenBounds(for: curve, scale: scale, origin: origin)
                guard rect.intersects(box) else { continue }
                if firstLayerID == nil {
                    firstLayerID = layer.id
                }
                if firstLayerID == layer.id {
                    selected.insert(curve.id)
                }
            }
        }

        if let firstLayerID, !selected.isEmpty {
            controller.selectGeometryOpenCurves(layerID: firstLayerID, openCurveIDs: selected, additive: additive)
        } else if !additive {
            controller.clearGeometryEditorSelection()
        }
    }

    private func selectSegments(in rect: CGRect, canvasSize: CGFloat, additive: Bool) {
        let (scale, origin) = viewTransform(canvasSize: canvasSize)
        var firstLayerID: EditableGeometryID?
        var polygonSegments: [(polygonID: EditableGeometryID, segmentID: EditableGeometryID)] = []
        var openCurveSegments: [(openCurveID: EditableGeometryID, segmentID: EditableGeometryID)] = []

        for layer in document.layers where layerCanEdit(layer) {
            for polygon in layer.polygons where polygon.isVisible {
                let pointMap = Dictionary(uniqueKeysWithValues: polygon.points.map { ($0.id, $0.position) })
                for segment in polygon.segments {
                    guard let start = pointMap[segment.startAnchorID],
                          let end = pointMap[segment.endAnchorID]
                    else { continue }
                    let midpoint = project(
                        Vector2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                        scale: scale,
                        origin: origin
                    )
                    guard rect.contains(midpoint) else { continue }
                    if firstLayerID == nil {
                        firstLayerID = layer.id
                    }
                    if firstLayerID == layer.id {
                        polygonSegments.append((polygon.id, segment.id))
                    }
                }
            }
            for curve in layer.openCurves where curve.isVisible {
                let pointMap = Dictionary(uniqueKeysWithValues: curve.points.map { ($0.id, $0.position) })
                for segment in curve.segments {
                    guard let start = pointMap[segment.startAnchorID],
                          let end = pointMap[segment.endAnchorID]
                    else { continue }
                    let midpoint = project(
                        Vector2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                        scale: scale,
                        origin: origin
                    )
                    guard rect.contains(midpoint) else { continue }
                    if firstLayerID == nil {
                        firstLayerID = layer.id
                    }
                    if firstLayerID == layer.id {
                        openCurveSegments.append((curve.id, segment.id))
                    }
                }
            }
        }

        if let firstLayerID, (!polygonSegments.isEmpty || !openCurveSegments.isEmpty) {
            controller.selectGeometrySegments(
                layerID: firstLayerID,
                polygonSegments: polygonSegments,
                openCurveSegments: openCurveSegments,
                additive: additive
            )
        } else if !additive {
            controller.clearGeometryEditorSelection()
        }
    }

    private func distanceToCubic(
        _ point: CGPoint,
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        var previous = start
        for index in 1...48 {
            let t = CGFloat(index) / 48
            let current = cubicPoint(t, start, control1, control2, end)
            best = min(best, distanceToSegment(point, previous, current))
            previous = current
        }
        return best
    }

    private func cubicPoint(
        _ t: CGFloat,
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint
    ) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    private func cubicPoint(
        _ p0: Vector2D,
        _ p1: Vector2D,
        _ p2: Vector2D,
        _ p3: Vector2D,
        t: Double
    ) -> Vector2D {
        let mt = 1.0 - t
        return p0 * (mt * mt * mt)
            + p1 * (3.0 * mt * mt * t)
            + p2 * (3.0 * mt * t * t)
            + p3 * (t * t * t)
    }

    private func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private var selectedLayerCanEdit: Bool {
        guard let id = controller.selectedGeometryEditorLayerID,
              let layer = document.layers.first(where: { $0.id == id })
        else { return false }
        return layerCanEdit(layer)
    }

    private func layerCanDraw(_ layer: EditableGeometryLayer) -> Bool {
        guard let panelLayer = controller.geometryEditorLayers.first(where: { $0.id == layer.id }) else {
            return layer.isVisible
        }
        return layer.isVisible && panelLayer.isVisible
    }

    private func layerCanEdit(_ layer: EditableGeometryLayer) -> Bool {
        guard layerCanDraw(layer) else { return false }
        guard let panelLayer = controller.geometryEditorLayers.first(where: { $0.id == layer.id }) else {
            return layer.isEditable
        }
        return layer.isEditable && panelLayer.isEditable
    }

    private func isPolygonSelected(_ polygon: EditableClosedPolygon) -> Bool {
        controller.geometryEditorSelection.polygonIDs.contains(polygon.id) &&
        controller.geometryEditorSelection.pointIDs.isEmpty &&
        controller.geometryEditorSelection.segmentIDs.isEmpty &&
        controller.geometryEditorTool == .polygons
    }

    private func isOpenCurveSelected(_ curve: EditableOpenCurve) -> Bool {
        controller.geometryEditorSelection.openCurveIDs.contains(curve.id) &&
        controller.geometryEditorSelection.pointIDs.isEmpty &&
        controller.geometryEditorSelection.segmentIDs.isEmpty &&
        controller.geometryEditorTool == .openCurves
    }
}

private struct GeometryPointHit: Equatable {
    var layerID: EditableGeometryID
    var polygonID: EditableGeometryID?
    var openCurveID: EditableGeometryID?
    var standalonePointID: EditableGeometryID?
    var pointID: EditableGeometryID
}

private struct GeometryPolygonHit: Equatable {
    var layerID: EditableGeometryID
    var polygonID: EditableGeometryID
}

private struct GeometryOpenCurveHit: Equatable {
    var layerID: EditableGeometryID
    var openCurveID: EditableGeometryID
}

private struct GeometrySegmentHit: Equatable {
    var layerID: EditableGeometryID
    var polygonID: EditableGeometryID?
    var openCurveID: EditableGeometryID?
    var segmentID: EditableGeometryID
}

private struct GeometryKeyCaptureView: NSViewRepresentable {
    var handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handle = handle
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.handle = handle
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if handle?(event) == true {
                return
            }
            super.keyDown(with: event)
        }
    }
}

// MARK: - Wireframe canvas

private struct WireframeCanvas: View {
    let polygons: [Polygon2D]

    var body: some View {
        Canvas { ctx, size in
            draw(ctx: ctx, size: size)
        }
    }

    // MARK: Layout

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let allPts = polygons.flatMap { $0.points }
        guard !allPts.isEmpty else { return }

        // Bounding box
        var minX = allPts[0].x, maxX = allPts[0].x
        var minY = allPts[0].y, maxY = allPts[0].y
        for p in allPts {
            if p.x < minX { minX = p.x }; if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }; if p.y > maxY { maxY = p.y }
        }

        let dataW   = max(maxX - minX, 1e-6)
        let dataH   = max(maxY - minY, 1e-6)
        let pad     = max(dataW, dataH) * 0.15
        let paddedW = dataW + pad * 2
        let paddedH = dataH + pad * 2
        let w       = Double(size.width)
        let h       = Double(size.height)
        let scale   = min(w / paddedW, h / paddedH)
        let ox      = (w - paddedW * scale) / 2 - (minX - pad) * scale
        let oy      = (h - paddedH * scale) / 2 + (maxY + pad) * scale

        func sc(_ v: Vector2D) -> CGPoint {
            CGPoint(x: v.x * scale + ox, y: oy - v.y * scale)
        }

        for poly in polygons {
            guard !poly.points.isEmpty else { continue }
            switch poly.type {
            case .spline:     drawSpline(ctx: ctx, poly: poly, sc: sc, closed: true)
            case .openSpline: drawSpline(ctx: ctx, poly: poly, sc: sc, closed: false)
            case .line:       drawLinePolygon(ctx: ctx, poly: poly, sc: sc)
            case .point:      drawPoint(ctx: ctx, poly: poly, sc: sc)
            case .oval:       drawOval(ctx: ctx, poly: poly, sc: sc)
            }
        }
    }

    // MARK: Colors

    private static let wireGreen     = Color(red: 0.31, green: 0.78, blue: 0.47)
    private static let wireGreenDark = Color(red: 0.18, green: 0.50, blue: 0.28)
    private static let wireAnchor    = Color.yellow
    private static let wireCP        = Color(red: 0.35, green: 0.55, blue: 1.0)

    // MARK: Spline

    private func drawSpline(ctx: GraphicsContext, poly: Polygon2D,
                            sc: (Vector2D) -> CGPoint, closed: Bool) {
        let segCount = poly.points.count / 4
        guard segCount > 0 else { return }

        // Control handles (drawn behind main path)
        for i in 0..<segCount {
            let b  = i * 4
            let a0 = sc(poly.points[b])
            let c0 = sc(poly.points[b + 1])
            let c1 = sc(poly.points[b + 2])
            let a1 = sc(poly.points[b + 3])
            var h  = Path()
            h.move(to: a0); h.addLine(to: c0)
            h.move(to: a1); h.addLine(to: c1)
            ctx.stroke(h, with: .color(Self.wireGreenDark.opacity(0.7)), lineWidth: 0.75)
            for cp in [c0, c1] {
                let r: CGFloat = 2.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cp.x - r, y: cp.y - r, width: r * 2, height: r * 2)),
                    with: .color(Self.wireCP.opacity(0.85))
                )
            }
        }

        // Main path
        var path = Path()
        path.move(to: sc(poly.points[0]))
        for i in 0..<segCount {
            let b = i * 4
            path.addCurve(
                to:       sc(poly.points[b + 3]),
                control1: sc(poly.points[b + 1]),
                control2: sc(poly.points[b + 2])
            )
        }
        if closed { path.closeSubpath() }
        ctx.stroke(path, with: .color(Self.wireGreen.opacity(0.9)), lineWidth: 1.5)

        // Anchor circles (one per segment start)
        for i in 0..<segCount {
            let a = sc(poly.points[i * 4])
            let r: CGFloat = 3.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)),
                with: .color(Self.wireAnchor)
            )
        }
    }

    // MARK: Line polygon

    private func drawLinePolygon(ctx: GraphicsContext, poly: Polygon2D,
                                 sc: (Vector2D) -> CGPoint) {
        let pts = poly.points.map(sc)
        var path = Path()
        path.move(to: pts[0])
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        ctx.stroke(path, with: .color(Self.wireGreen.opacity(0.9)), lineWidth: 1.5)
        for pt in pts {
            let r: CGFloat = 3.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(Self.wireAnchor)
            )
        }
    }

    // MARK: Point

    private func drawPoint(ctx: GraphicsContext, poly: Polygon2D,
                           sc: (Vector2D) -> CGPoint) {
        let pt = sc(poly.points[0])
        let r: CGFloat = 4
        var cross = Path()
        cross.move(to: CGPoint(x: pt.x - r, y: pt.y)); cross.addLine(to: CGPoint(x: pt.x + r, y: pt.y))
        cross.move(to: CGPoint(x: pt.x, y: pt.y - r)); cross.addLine(to: CGPoint(x: pt.x, y: pt.y + r))
        ctx.stroke(cross, with: .color(.cyan), lineWidth: 1.5)
    }

    // MARK: Oval

    private func drawOval(ctx: GraphicsContext, poly: Polygon2D,
                          sc: (Vector2D) -> CGPoint) {
        guard poly.points.count >= 2 else { return }
        let c  = sc(poly.points[0])
        let rp = sc(poly.points[1])
        let rx = abs(rp.x - c.x), ry = abs(rp.y - c.y)
        ctx.stroke(
            Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)),
            with: .color(Self.wireGreen.opacity(0.9)), lineWidth: 1.5
        )
        let r: CGFloat = 3.5
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(Self.wireAnchor)
        )
    }
}
