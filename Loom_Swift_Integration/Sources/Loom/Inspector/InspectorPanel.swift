import AppKit
import SwiftUI
import LoomEngine

// Right-side inspector panel (280 px).
// Delegates to per-tab inspector views.
struct InspectorPanel: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if controller.selectedTimelineKF != nil {
                    KeyframeInspector()
                        .environmentObject(controller)
                }
                if controller.selectedRendererTimelineKF != nil {
                    KeyframeInspector()
                        .environmentObject(controller)
                }
                if controller.selectedCameraKF != nil {
                    CameraKeyframeInspector()
                        .environmentObject(controller)
                }
                inspectorContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch controller.selectedTab {
        case .global:
            GlobalInspector()
                .environmentObject(controller)
        case .geometry:
            if controller.isGeometryEditorActive {
                GeometryEditorShellInspector()
                    .environmentObject(controller)
            } else if controller.selectedGeometryKey != nil {
                GeometryInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a geometry set.")
            }
        case .subdivision:
            if controller.selectedSubdivisionIndex != nil {
                SubdivisionInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a sprite or subdivision set to edit params.")
            }
        case .sprites:
            if controller.selectedSpriteID != nil {
                SpritesInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a sprite.")
            }
        case .cycles:
            CyclesInspector()
                .environmentObject(controller)
        case .layers:
            if controller.selectedLayerIndex != nil {
                LayersInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a layer.")
            }
        case .lights:
            if controller.selectedLightIndex != nil {
                LightsInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a light.")
            }
        case .audio:
            placeholderText("Select the Audio tab to work with audio.")
        case .rendering:
            if controller.selectedRendererIndex != nil {
                RenderingInspector()
                    .environmentObject(controller)
            } else {
                placeholderText("Select a renderer set.")
            }
        }
    }

    private func placeholderText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared inspector primitives
// Used by all per-tab inspector views in this module.

struct InspectorSection<Content: View>: View {
    let title: String
    private let isHighlighted: Bool
    private let content: Content
    private let collapseState: Binding<Bool>?
    private let trailingButton: AnyView?

    init(_ title: String, isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.title           = title
        self.isHighlighted   = isHighlighted
        self.content         = content()
        self.collapseState   = nil
        self.trailingButton  = nil
    }

    init(_ title: String, isCollapsed: Binding<Bool>, isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.title           = title
        self.isHighlighted   = isHighlighted
        self.content         = content()
        self.collapseState   = isCollapsed
        self.trailingButton  = nil
    }

    /// Collapsible section with an optional trailing button in the header.
    init<T: View>(_ title: String, isCollapsed: Binding<Bool>, isHighlighted: Bool = false,
                  @ViewBuilder trailing: () -> T,
                  @ViewBuilder content: () -> Content) {
        self.title           = title
        self.isHighlighted   = isHighlighted
        self.content         = content()
        self.collapseState   = isCollapsed
        self.trailingButton  = AnyView(trailing())
    }

    private var collapsed: Bool { collapseState?.wrappedValue ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let binding = collapseState {
                HStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: binding.wrappedValue ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { binding.wrappedValue.toggle() }
                    if let tb = trailingButton {
                        tb.padding(.trailing, 10).padding(.top, 6)
                    }
                }
            } else {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            if !collapsed {
                content
            }
            Divider().padding(.top, collapsed ? 0 : 4)
        }
        .background(Color.clear)
    }
}

/// A labelled row containing an arbitrary editor control.
struct InspectorField<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label   = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

/// A read-only label/value row.
struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

/// An editable `LoomColor` row backed by SwiftUI's `ColorPicker`.
struct LoomColorField: View {
    let label: String
    @Binding var color: LoomColor

    var body: some View {
        InspectorField(label) {
            ColorPicker("", selection: swiftUIBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 44, height: 22)
        }
    }

    private var swiftUIBinding: Binding<Color> {
        Binding {
            Color(red: color.rF, green: color.gF, blue: color.bF, opacity: color.aF)
        } set: { newColor in
            let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor.black
            color = LoomColor(
                r: clamp255(ns.redComponent),
                g: clamp255(ns.greenComponent),
                b: clamp255(ns.blueComponent),
                a: clamp255(ns.alphaComponent)
            )
        }
    }

    private func clamp255(_ v: CGFloat) -> Int {
        Int(max(0, min(255, (v * 255 + 0.5).rounded(.down))))
    }
}

/// Compact mini-list used inside the inspector for selecting an item within a set.
struct InspectorPickList<T>: View {
    let items: [T]
    let labelFor: (T) -> String
    @Binding var selection: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                let selected = selection == idx
                HStack(spacing: 6) {
                    Text("\(idx)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                    Text(labelFor(item))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { selection = idx }
            }
        }
    }
}

// MARK: - Geometry inspector

private struct GeometryInspector: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        if let key = controller.selectedGeometryKey {
            let parts  = key.split(separator: "/", maxSplits: 1)
            let folder = parts.count == 2 ? String(parts[0]) : "—"
            let name   = parts.count == 2 ? String(parts[1]) : key

            InspectorSection("Geometry") {
                Button("Edit Geometry") {
                    controller.enterGeometryEditor()
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
                InspectorRow(label: "Folder", value: folder)
                InspectorRow(label: "Name",   value: name)
            }
            switch folder {
            case "polygonSets":
                if let def = polygonSetDef(named: name) { polygonSetSection(def: def) }
            case "regularPolygons":
                if let def = polygonSetDef(named: name), let rp = def.regularParams {
                    regularPolygonSection(rp: rp, name: name)
                }
            case "curveSets":
                if let def = curveSetDef(named: name) { curveSetSection(def: def) }
            case "pointSets":
                if let def = pointSetDef(named: name) { pointSetSection(def: def) }
            default:
                EmptyView()
            }
            QuickSetupSection(folder: folder, geoName: name)
                .environmentObject(controller)
            CycleSetupSection(folder: folder, geoName: name)
                .environmentObject(controller)
            PipelinesSection(geoName: name)
                .environmentObject(controller)
        }
    }

    // MARK: Lookup helpers

    private func polygonSetDef(named name: String) -> PolygonSetDef? {
        controller.projectConfig?.polygonConfig.library.polygonSets.first { $0.name == name }
    }

    private func curveSetDef(named name: String) -> OpenCurveSetDef? {
        controller.projectConfig?.curveConfig.library.curveSets.first { $0.name == name }
    }

    private func pointSetDef(named name: String) -> PointSetDef? {
        controller.projectConfig?.pointConfig.library.pointSets.first { $0.name == name }
    }

    // MARK: Section views

    @ViewBuilder
    private func polygonSetSection(def: PolygonSetDef) -> some View {
        let folder = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
        InspectorSection("Polygon Set") {
            InspectorRow(label: "Type", value: def.polygonType.rawValue)
            if def.regularParams != nil {
                InspectorRow(label: "Source", value: "algorithmic")
            } else if def.filename.isEmpty {
                InspectorRow(label: "File", value: "—")
            } else {
                InspectorRow(label: "File", value: def.filename)
                if !fileExists(folder: folder, filename: def.filename) {
                    relinkRow(name: def.name, folder: folder)
                }
            }
        }
    }

    @ViewBuilder
    private func regularPolygonSection(rp: RegularPolygonParams, name: String) -> some View {
        InspectorSection("Regular Polygon") {
            InspectorField("Points") {
                TextField("", value: bindRegularInt(\.totalPoints, name: name), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 50)
            }
            InspectorField("Inner r") {
                TextField("", value: bindRegular(\.internalRadius, name: name),
                          format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 60)
            }
            InspectorField("Offset") {
                TextField("", value: bindRegular(\.offset, name: name),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 55)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Scale X") {
                TextField("", value: bindRegular(\.scaleX, name: name),
                          format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 55)
            }
            InspectorField("Scale Y") {
                TextField("", value: bindRegular(\.scaleY, name: name),
                          format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 55)
            }
            InspectorField("Rotation") {
                TextField("", value: bindRegular(\.rotationAngle, name: name),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 12, design: .monospaced)).frame(width: 55)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func curveSetSection(def: OpenCurveSetDef) -> some View {
        InspectorSection("Curve Set") {
            InspectorRow(label: "Folder", value: def.folder)
            InspectorRow(label: "File",   value: def.filename.isEmpty ? "—" : def.filename)
            if !def.filename.isEmpty, let key = controller.selectedGeometryKey {
                let name = String(key.split(separator: "/", maxSplits: 1).last ?? "")
                if !fileExists(folder: def.folder, filename: def.filename) {
                    relinkRow(name: name, folder: def.folder)
                }
            }
        }
    }

    @ViewBuilder
    private func pointSetSection(def: PointSetDef) -> some View {
        InspectorSection("Point Set") {
            InspectorRow(label: "Folder", value: def.folder)
            InspectorRow(label: "File",   value: def.filename.isEmpty ? "—" : def.filename)
            if !def.filename.isEmpty, let key = controller.selectedGeometryKey {
                let name = String(key.split(separator: "/", maxSplits: 1).last ?? "")
                if !fileExists(folder: def.folder, filename: def.filename) {
                    relinkRow(name: name, folder: def.folder)
                }
            }
        }
    }

    // MARK: Missing-file helpers

    private func fileExists(folder: String, filename: String) -> Bool {
        controller.geometryFileURL(folder: folder, filename: filename)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? true
    }

    @ViewBuilder
    private func relinkRow(name: String, folder: String) -> some View {
        let candidates = controller.candidateRelinkFiles(for: name, folder: folder)
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("File not found")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Spacer()
            Menu("Re-link…") {
                if !candidates.isEmpty {
                    ForEach(candidates.prefix(5), id: \.self) { url in
                        Button(url.lastPathComponent) {
                            controller.relinkGeometryFile(name: name, folder: folder, toURL: url)
                        }
                    }
                    Divider()
                }
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.title                  = "Locate Missing File"
                    panel.message                = "Choose the replacement geometry file for \"\(name)\""
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories    = false
                    panel.allowedContentTypes     = [.json, .xml]
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        controller.relinkGeometryFile(name: name, folder: folder, toURL: url)
                    }
                }
            }
            .font(.system(size: 11))
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: Binding helpers

    private func bindRegular(_ kp: WritableKeyPath<RegularPolygonParams, Double>, name: String) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.polygonConfig.library.polygonSets
                    .first(where: { $0.name == name })?.regularParams?[keyPath: kp] ?? 0.0
            },
            set: { val in
                ctl.updateProjectConfig { cfg in
                    guard let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == name }) else { return }
                    cfg.polygonConfig.library.polygonSets[idx].regularParams?[keyPath: kp] = val
                }
            }
        )
    }

    private func bindRegularInt(_ kp: WritableKeyPath<RegularPolygonParams, Int>, name: String) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.polygonConfig.library.polygonSets
                    .first(where: { $0.name == name })?.regularParams?[keyPath: kp] ?? 0
            },
            set: { val in
                ctl.updateProjectConfig { cfg in
                    guard let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == name }) else { return }
                    cfg.polygonConfig.library.polygonSets[idx].regularParams?[keyPath: kp] = val
                }
            }
        )
    }

}

private struct GeometryEditorShellInspector: View {
    @EnvironmentObject private var controller: AppController
    @State private var geometryName = ""
    @State private var createCollapsed = false
    @State private var weldCollapsed = false
    @State private var multiplyCollapsed = false
    @State private var transformCollapsed = false
    @State private var deformCollapsed = false
    @State private var showSavePointSetPopover = false
    @State private var newPointSetName = ""
    @State private var editingPointSetID: UUID? = nil
    @State private var editingPointSetName = ""
    @State private var viewCollapsed = false
    @State private var parametricCollapsed = false
    @State private var scaleAxis = "XY"
    @State private var showingDuplicateToLayerAlert = false
    @State private var duplicateLayerName = ""
    @State private var scaleSliderValue = 0.0
    @State private var rotateSliderValue = 0.0
    @State private var rotateAngleDegrees: Double = 0.0
    @State private var transformPivot = GeometryTransformPivot.commonCentre

    var body: some View {
        let morphLocked = controller.isCurrentGeometryMorphTargetLocked
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection("Geometry Editor") {
                geometryNameAndSaveRow
                InspectorRow(label: "Mode", value: geometryModeLabel)
                InspectorRow(label: "Tool", value: controller.geometryEditorTool.rawValue)
                InspectorRow(label: "Anchors", value: "\(controller.selectedGeometryAnchorCount)")
                if morphLocked {
                    InspectorRow(label: "Lock", value: "Morph target — topology locked")
                }
            }

            geometryUtilitySection(morphLocked: morphLocked)

            if let parameters = controller.selectedRegularPolygonParameters {
                InspectorSection("Regular Polygon", isCollapsed: $parametricCollapsed) {
                    regularPolygonParametersSection(parameters)
                }
            }

            InspectorSection("Create", isCollapsed: $createCollapsed, isHighlighted: controller.geometryEditorTool.isCreateMode) {
                iconRow {
                    iconButton(
                        help: "Create standalone points",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .standalonePoints
                    ) {
                        PointCircleIcon()
                    } action: {
                        controller.startStandalonePointGeometryCreation()
                    }
                    iconButton(help: "Create oval") {
                        OvalGeometryIcon()
                    } action: {
                        controller.createOvalGeometry()
                    }
                    iconButton(help: "Create regular polygon") {
                        Image(systemName: "star").font(.system(size: 15))
                    } action: {
                        controller.createRegularPolygonGeometry()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(
                        help: "Point by point",
                        disabled: false,
                        selected: controller.geometryEditorTool == .pointByPoint
                    ) {
                        PointByPointIcon()
                    } action: {
                        controller.startPointByPointGeometryCreation()
                    }
                    Text("Finalise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                    iconButton(help: "Finalise polygon", disabled: !controller.canFinaliseGeometryDraftPolygon) {
                        PolygonGeometryIcon()
                    } action: {
                        controller.finaliseGeometryDraftPolygon()
                    }
                    iconButton(help: "Finalise open curve", disabled: !controller.canFinaliseGeometryDraftOpenCurve) {
                        OpenCurveGeometryIcon()
                    } action: {
                        controller.finaliseGeometryDraftOpenCurve()
                    }
                    iconButton(help: "Clear draft", disabled: controller.geometryEditorDraftPoints.isEmpty) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    } action: {
                        controller.clearGeometryDraft()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(
                        help: "Mesh extend: drag from an edge, release to add a temporary vertex, drag temporary vertices to adjust, P or Finalise Polygon to commit. Click again to leave mesh mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .meshExtend
                    ) {
                        Image(systemName: "square.grid.3x3").font(.system(size: 15))
                    } action: {
                        controller.startMeshExtendGeometryCreation()
                    }
                    iconButton(help: "Fill triangle from two connected selected edges", disabled: !controller.canFillSelectedGeometryTriangle) {
                        Image(systemName: "triangle").font(.system(size: 15))
                    } action: {
                        controller.fillSelectedGeometryTriangle()
                    }
                    iconButton(help: "Fill quad from two connected selected edges", disabled: !controller.canFillSelectedGeometryQuad) {
                        Image(systemName: "square").font(.system(size: 15))
                    } action: {
                        controller.fillSelectedGeometryQuad()
                    }
                    iconButton(help: "Fill selected closed mesh hole", disabled: !controller.canFillSelectedGeometryHole) {
                        Image(systemName: "square.dashed").font(.system(size: 15))
                    } action: {
                        controller.fillSelectedGeometryHole()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(
                        help: "Freehand draw",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .freehand
                    ) {
                        Image(systemName: "pencil.tip").font(.system(size: 15))
                    } action: {
                        controller.startFreehandGeometryCreation()
                    }
                    Slider(value: $controller.geometryEditorFreehandDetail, in: 0...1)
                        .help("Freehand detail")
                        .modifier(LoomHoverHelp("Freehand detail"))
                }
                iconRow {
                    iconButton(
                        help: "Pressure Trace: trace over selected geometry to add pressure sensitivity",
                        disabled: !controller.canPressureTraceSelectedGeometry || morphLocked,
                        selected: controller.geometryEditorTool == .pressureTrace
                    ) {
                        PressureTraceIcon()
                    } action: {
                        controller.startPressureTraceGeometryEdit()
                    }
                    iconButton(
                        help: "Clear pressure sensitivity from selected geometry",
                        disabled: !controller.canClearPressureSelectedGeometry || morphLocked
                    ) {
                        Image(systemName: "eraser").font(.system(size: 15))
                    } action: {
                        controller.clearPressureForSelectedGeometry()
                    }
                    Spacer()
                }
            }
            .disabled(morphLocked)

            InspectorSection("Weld", isCollapsed: $weldCollapsed) {
                iconRow {
                    Toggle("", isOn: $controller.geometryEditorAutoWeld)
                        .labelsHidden()
                        .help("Auto weld")
                        .modifier(LoomHoverHelp("Auto weld"))
                    iconButton(help: "Weld selected points or edges", disabled: !controller.canWeldSelectedGeometry) {
                        Image(systemName: "link.badge.plus").font(.system(size: 15))
                    } action: {
                        controller.weldSelectedGeometry()
                    }
                    iconButton(help: "Weld adjacent edges", disabled: !controller.canWeldAdjacentGeometryEdges) {
                        Image(systemName: "link").font(.system(size: 15))
                    } action: {
                        controller.weldAdjacentGeometryEdges()
                    }
                    Slider(value: $controller.geometryEditorWeldTolerance, in: 0...1)
                        .frame(width: 58)
                        .help("Weld tolerance: left is stricter, right accepts looser edge matches")
                        .modifier(LoomHoverHelp("Weld tolerance: left is stricter, right accepts looser edge matches"))
                    iconButton(help: "Break welds on selected geometry", disabled: !controller.canUnweldSelectedGeometry) {
                        ExplodeWeldIcon()
                    } action: {
                        controller.unweldSelectedGeometry()
                    }
                    Spacer()
                }
            }

            InspectorSection("Multiply", isCollapsed: $multiplyCollapsed) {
                iconRow {
                    iconButton(help: "Duplicate to same layer", disabled: !controller.canDuplicateSelectedGeometry) {
                        Image(systemName: "plus.square.fill").font(.system(size: 15))
                    } action: {
                        controller.duplicateSelectedGeometry()
                    }
                    iconButton(help: "Duplicate to new layer", disabled: !controller.canDuplicateSelectedGeometry) {
                        Image(systemName: "plus.square.on.square").font(.system(size: 15))
                    } action: {
                        duplicateLayerName = ""
                        showingDuplicateToLayerAlert = true
                    }
                    iconButton(
                        help: "Displacement extrude: select edges, polygons, or open curves, then drag to push a copy sideways and stitch quads back to the originals. Choose another tool to leave extrude mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .displacementExtrude
                    ) {
                        DisplacementExtrudeIcon()
                    } action: {
                        controller.startDisplacementExtrude()
                    }
                    iconButton(
                        help: "Scale extrude: select edges, polygons, or open curves, then drag right/up to grow an outer ring or left/down for an inner ring, stitched to the originals. Choose another tool to leave extrude mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .scaleExtrude
                    ) {
                        ScaleExtrudeIcon()
                    } action: {
                        controller.startScaleExtrude()
                    }
                    iconButton(
                        help: "Knife: drag a cut line through polygons or open curves. Choose another tool to leave knife mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .knife
                    ) {
                        RazorBladeIcon()
                    } action: {
                        controller.startKnifeGeometryCut()
                    }
                    iconButton(
                        help: "Cut through all visible layers (drag mode only — anchor-point cuts always target the polygon's own layer)",
                        disabled: controller.geometryEditorTool != .knife,
                        selected: controller.geometryEditorTool == .knife && controller.geometryEditorKnifeCutsAllVisibleLayers
                    ) {
                        KnifeLayerStackIcon()
                    } action: {
                        controller.geometryEditorKnifeCutsAllVisibleLayers.toggle()
                    }
                    iconButton(
                        help: "Curved knife: drag a cut curve, adjust control handles, then press K to cut.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .curvedKnife
                    ) {
                        CurvedRazorBladeIcon()
                    } action: {
                        controller.startCurvedKnifeGeometryCut()
                    }
                    iconButton(
                        help: "Cut through all visible layers (drag mode only — anchor-point cuts always target the polygon's own layer)",
                        disabled: controller.geometryEditorTool != .curvedKnife,
                        selected: controller.geometryEditorTool == .curvedKnife && controller.geometryEditorCurvedKnifeCutsAllVisibleLayers
                    ) {
                        KnifeLayerStackIcon()
                    } action: {
                        controller.geometryEditorCurvedKnifeCutsAllVisibleLayers.toggle()
                    }
                    Spacer()
                }
            }
            .disabled(morphLocked)

            InspectorSection("Transform", isCollapsed: $transformCollapsed) {
                iconRow {
                    iconButton(help: "Flip horizontally", disabled: !controller.canTransformSelectedGeometry) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size: 14))
                    } action: {
                        controller.flipSelectedGeometryHorizontally()
                    }
                    iconButton(help: "Flip vertically", disabled: !controller.canTransformSelectedGeometry) {
                        Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down").font(.system(size: 14))
                    } action: {
                        controller.flipSelectedGeometryVertically()
                    }
                    Spacer()
                }
                InspectorField("Scale Axis") {
                    Picker("", selection: $scaleAxis) {
                        Text("XY").tag("XY")
                        Text("X").tag("X")
                        Text("Y").tag("Y")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                iconRow {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Scale")
                        .modifier(LoomHoverHelp("Scale"))
                    Slider(
                        value: $scaleSliderValue,
                        in: -100...100,
                        onEditingChanged: handleScaleSliderEditing
                    )
                    .disabled(!controller.canTransformSelectedGeometry)
                    .help("Scale")
                    .modifier(LoomHoverHelp("Scale"))
                }
                InspectorField("Rotation Pivot") {
                    Picker("", selection: $transformPivot) {
                        Text("Local").tag(GeometryTransformPivot.localCentre)
                        Text("Common").tag(GeometryTransformPivot.commonCentre)
                        Text("Canvas").tag(GeometryTransformPivot.absoluteCentre)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                iconRow {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Rotate")
                        .modifier(LoomHoverHelp("Rotate"))
                    Slider(
                        value: $rotateSliderValue,
                        in: -100...100,
                        onEditingChanged: handleRotateSliderEditing
                    )
                    .disabled(!controller.canTransformSelectedGeometry)
                    .help("Rotate")
                    .modifier(LoomHoverHelp("Rotate"))
                }
                InspectorField("Angle °") {
                    FloatEntryField(
                        value: $rotateAngleDegrees,
                        width: 62,
                        fractionDigits: 1,
                        help: "Rotate selection by entered degrees using the Rotation Pivot; press Return to apply",
                        onCommit: { degrees in
                            guard degrees != 0 else { return }
                            controller.rotateSelectedGeometry(degrees: degrees, pivot: transformPivot)
                            rotateAngleDegrees = 0
                        }
                    )
                    .disabled(!controller.canTransformSelectedGeometry)
                }
            }

            InspectorSection("Deform", isCollapsed: $deformCollapsed) {
                // Operation
                InspectorField("Operation") {
                    Picker("", selection: Binding(
                        get: { controller.deformOperation },
                        set: { controller.deformOperation = $0 }
                    )) {
                        ForEach(DeformOperation.allCases, id: \.self) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Centre indicator
                InspectorField("Centre") {
                    if let c = controller.deformCenter {
                        Text(String(format: "%.3f, %.3f", c.x, c.y))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click canvas to set")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Radius
                InspectorField("Radius") {
                    HStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { controller.deformRadius },
                                set: { controller.deformRadius = $0 }
                            ),
                            in: 0.01...1.0
                        )
                        Text(String(format: "%.2f", controller.deformRadius))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                // Falloff
                InspectorField("Falloff") {
                    Picker("", selection: Binding(
                        get: { controller.deformFalloff },
                        set: { controller.deformFalloff = $0 }
                    )) {
                        ForEach(DeformFalloff.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Invert falloff
                InspectorField("Invert") {
                    Toggle("", isOn: Binding(
                        get: { controller.deformInvertFalloff },
                        set: { controller.deformInvertFalloff = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .modifier(LoomHoverHelp("Invert falloff: maximum effect at the radius edge, zero at the centre — useful for deforming tips rather than roots"))

                // Sector constraint
                InspectorField("Sector") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { controller.deformSectorEnabled },
                            set: { controller.deformSectorEnabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        if controller.deformSectorEnabled {
                            Text(String(format: "%.0f° – %.0f°",
                                        controller.deformSectorStartAngle,
                                        controller.deformSectorEndAngle))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .modifier(LoomHoverHelp("Restrict deformation to a wedge sector. Drag the two white circle handles on the canvas to set the arc boundaries; the shaded region is excluded."))

                // Named point set filter
                let pointSets = controller.deformPointSets
                InspectorField("Point Set") {
                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { controller.activeDeformPointSetID },
                            set: { controller.activeDeformPointSetID = $0 }
                        )) {
                            Text("None").tag(UUID?.none)
                            ForEach(pointSets) { set in
                                Text(set.name).tag(UUID?.some(set.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        // Save current selection as a new set
                        Button {
                            newPointSetName = "Set \(pointSets.count + 1)"
                            showSavePointSetPopover = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Save current point selection as a named set")
                        .popover(isPresented: $showSavePointSetPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Save Point Set")
                                    .font(.headline)
                                TextField("Name", text: $newPointSetName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)
                                    .onSubmit {
                                        controller.saveSelectionAsDeformPointSet(name: newPointSetName)
                                        showSavePointSetPopover = false
                                    }
                                HStack {
                                    Button("Cancel") { showSavePointSetPopover = false }
                                    Spacer()
                                    Button("Save") {
                                        controller.saveSelectionAsDeformPointSet(name: newPointSetName)
                                        showSavePointSetPopover = false
                                    }
                                    .disabled(newPointSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(14)
                            .frame(width: 218)
                        }

                        // Rename active set
                        if let activeID = controller.activeDeformPointSetID,
                           pointSets.contains(where: { $0.id == activeID }) {
                            Button {
                                if let set = pointSets.first(where: { $0.id == activeID }) {
                                    editingPointSetID = activeID
                                    editingPointSetName = set.name
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Rename this point set")
                            .popover(isPresented: Binding(
                                get: { editingPointSetID != nil },
                                set: { if !$0 { editingPointSetID = nil } }
                            ), arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Rename Point Set")
                                        .font(.headline)
                                    TextField("Name", text: $editingPointSetName)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 180)
                                        .onSubmit {
                                            if let id = editingPointSetID {
                                                controller.renameDeformPointSet(id: id, name: editingPointSetName)
                                            }
                                            editingPointSetID = nil
                                        }
                                    HStack {
                                        Button("Cancel") { editingPointSetID = nil }
                                        Spacer()
                                        Button("Rename") {
                                            if let id = editingPointSetID {
                                                controller.renameDeformPointSet(id: id, name: editingPointSetName)
                                            }
                                            editingPointSetID = nil
                                        }
                                        .disabled(editingPointSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(14)
                                .frame(width: 218)
                            }

                            // Delete active set
                            Button {
                                controller.deleteDeformPointSet(id: activeID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this point set")
                        }
                    }
                }
                .modifier(LoomHoverHelp("Filter deformation to a named set of points. Select points, press +, name the set. Switch between sets via the dropdown. Works across topologically identical layers (morph lock)."))

                // Intensity
                InspectorField("Intensity") {
                    HStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { controller.deformIntensity },
                                set: { controller.deformIntensity = $0 }
                            ),
                            in: 0.0...2.0
                        )
                        Text(String(format: "%.2f", controller.deformIntensity))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                // Operation-specific fields
                switch controller.deformOperation {
                case .rotate:
                    InspectorField("Angle °") {
                        FloatEntryField(
                            value: Binding(
                                get: { controller.deformAngle },
                                set: { controller.deformAngle = $0 }
                            ),
                            width: 62,
                            fractionDigits: 1,
                            help: "Rotation angle in degrees; also updated live by dragging the yellow handle"
                        )
                    }
                case .scale:
                    InspectorField("Amount %") {
                        FloatEntryField(
                            value: Binding(
                                get: { controller.deformScale },
                                set: { controller.deformScale = $0 }
                            ),
                            width: 62,
                            fractionDigits: 1,
                            help: "Scale amount as percentage; also updated live by dragging the cyan handle"
                        )
                    }
                case .push:
                    InspectorField("Push X") {
                        FloatEntryField(
                            value: Binding(
                                get: { controller.deformPushX },
                                set: { controller.deformPushX = $0 }
                            ),
                            width: 62,
                            fractionDigits: 3,
                            help: "Horizontal displacement; also updated live by dragging the orange handle"
                        )
                    }
                    InspectorField("Push Y") {
                        FloatEntryField(
                            value: Binding(
                                get: { controller.deformPushY },
                                set: { controller.deformPushY = $0 }
                            ),
                            width: 62,
                            fractionDigits: 3,
                            help: "Vertical displacement; also updated live by dragging the orange handle"
                        )
                    }
                }

                // Reference layers (before / after ghost overlays)
                let layerOptions = controller.geometryEditorLayers
                InspectorField("Before") {
                    Picker("", selection: Binding(
                        get: { controller.deformBeforeLayerID },
                        set: { controller.deformBeforeLayerID = $0 }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(layerOptions) { layer in
                            Text(layer.name).tag(Optional(layer.id))
                        }
                    }
                    .labelsHidden()
                }
                .modifier(LoomHoverHelp("Show this layer as a blue ghost overlay while deforming"))

                InspectorField("After") {
                    Picker("", selection: Binding(
                        get: { controller.deformAfterLayerID },
                        set: { controller.deformAfterLayerID = $0 }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(layerOptions) { layer in
                            Text(layer.name).tag(Optional(layer.id))
                        }
                    }
                    .labelsHidden()
                }
                .modifier(LoomHoverHelp("Show this layer as an orange ghost overlay while deforming"))

                // Apply / Reset row
                HStack(spacing: 8) {
                    Button("Reset to Base") {
                        controller.resetToDeformOrigin()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!controller.deformHasOrigin)
                    .modifier(LoomHoverHelp("Undo all deformations back to the state when the Deform tool was first activated"))

                    Spacer()

                    Button("Apply") {
                        controller.applyDeform()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(controller.deformCenter == nil)
                    .modifier(LoomHoverHelp("Apply current deform parameters as a new undo step"))
                }
                .padding(.top, 4)
            }

            InspectorSection("View", isCollapsed: $viewCollapsed) {
                iconRow {
                    iconButton(help: "Zoom in") {
                        Image(systemName: "plus.magnifyingglass").font(.system(size: 15))
                    } action: {
                        controller.zoomGeometryEditorIn()
                    }
                    iconButton(help: "Zoom out") {
                        Image(systemName: "minus.magnifyingglass").font(.system(size: 15))
                    } action: {
                        controller.zoomGeometryEditorOut()
                    }
                    // Pan button: single-click toggles pan mode; double-click resets
                    // the pan origin back to centre without changing the active mode.
                    let isPanSelected = controller.geometryEditorTool == .panView
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isPanSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 15))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .foregroundStyle(Color.primary)
                    }
                    .onTapGesture(count: 2) {
                        controller.resetGeometryEditorViewPan()
                    }
                    .onTapGesture(count: 1) {
                        if isPanSelected {
                            controller.startGeometryEditMode(.points)
                        } else {
                            controller.startGeometryEditMode(.panView)
                        }
                    }
                    .modifier(InstantGeometryTooltip("Pan view: drag canvas to scroll the editor view. Double-click to reset pan position."))
                    iconButton(
                        help: "Show or hide grid",
                        selected: controller.geometryEditorShowsGrid
                    ) {
                        Image(systemName: "grid").font(.system(size: 15))
                    } action: {
                        controller.geometryEditorShowsGrid.toggle()
                    }
                    iconButton(
                        help: "Show or hide control points",
                        selected: controller.geometryEditorShowsControlPoints
                    ) {
                        PointCircleIcon()
                    } action: {
                        controller.geometryEditorShowsControlPoints.toggle()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(help: "Load reference image") {
                        Image(systemName: "photo").font(.system(size: 15))
                    } action: {
                        controller.loadGeometryEditorReferenceImage()
                    }
                    iconButton(
                        help: "Show or hide reference image",
                        disabled: controller.geometryEditorReferenceImage == nil,
                        selected: controller.geometryEditorShowsReferenceImage
                    ) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 15))
                    } action: {
                        controller.geometryEditorShowsReferenceImage.toggle()
                    }
                    Slider(value: $controller.geometryEditorReferenceImageOpacity, in: 0...1)
                        .frame(width: 58)
                        .disabled(controller.geometryEditorReferenceImage == nil)
                        .help("Reference image opacity")
                        .modifier(LoomHoverHelp("Reference image opacity"))
                    iconButton(
                        help: "Clear reference image",
                        disabled: controller.geometryEditorReferenceImage == nil
                    ) {
                        Image(systemName: "xmark.circle").font(.system(size: 15))
                    } action: {
                        controller.clearGeometryEditorReferenceImage()
                    }
                    Spacer()
                }
                iconRow {
                    let sources = controller.referenceGeometrySources
                    let hasRef  = controller.geometryEditorReferenceGeometryKey != nil
                    Picker("", selection: Binding(
                        get: { controller.geometryEditorReferenceGeometryKey ?? "" },
                        set: { controller.setReferenceGeometryKey($0.isEmpty ? nil : $0) }
                    )) {
                        Text("— geometry ref —").tag("")
                        ForEach(sources, id: \.key) { src in
                            Text(src.name).tag(src.key)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .help("Reference geometry: overlay another geometry file as a guide")
                    .modifier(LoomHoverHelp("Reference geometry"))
                    iconButton(
                        help: "Show or hide reference geometry",
                        disabled: !hasRef,
                        selected: controller.geometryEditorShowsReferenceGeometry
                    ) {
                        Image(systemName: "square.on.square").font(.system(size: 15))
                    } action: {
                        controller.geometryEditorShowsReferenceGeometry.toggle()
                    }
                    Slider(value: $controller.geometryEditorReferenceGeometryOpacity, in: 0...1)
                        .frame(width: 58)
                        .disabled(!hasRef)
                        .help("Reference geometry opacity")
                        .modifier(LoomHoverHelp("Reference geometry opacity"))
                    iconButton(
                        help: "Clear reference geometry",
                        disabled: !hasRef
                    ) {
                        Image(systemName: "xmark.circle").font(.system(size: 15))
                    } action: {
                        controller.clearReferenceGeometry()
                    }
                }
                HStack(spacing: 7) {
                    Picker("", selection: $controller.geometryEditorGridDetail) {
                        ForEach(GeometryEditorGridDetail.allCases) { detail in
                            Text(detail.rawValue).tag(detail)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 86)
                    .help("Grid detail")
                    .modifier(LoomHoverHelp("Grid detail"))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }

        }
        .onAppear { geometryName = currentGeometryName }
        .onChange(of: controller.selectedGeometryKey) { _, _ in
            geometryName = currentGeometryName
        }
        .onChange(of: scaleSliderValue) { _, value in
            controller.updateScaleTransformGesture(sliderValue: value, axis: scaleAxis, pivot: transformPivot)
        }
        .onChange(of: rotateSliderValue) { _, value in
            controller.updateRotateTransformGesture(sliderValue: value, pivot: transformPivot)
        }
        .onChange(of: scaleAxis) { _, _ in
            guard scaleSliderValue != 0 else { return }
            controller.updateScaleTransformGesture(sliderValue: scaleSliderValue, axis: scaleAxis, pivot: transformPivot)
        }
        .onChange(of: transformPivot) { _, _ in
            if scaleSliderValue != 0 {
                controller.updateScaleTransformGesture(sliderValue: scaleSliderValue, axis: scaleAxis, pivot: transformPivot)
            }
            if rotateSliderValue != 0 {
                controller.updateRotateTransformGesture(sliderValue: rotateSliderValue, pivot: transformPivot)
            }
        }
    }

    private var geometryModeLabel: String {
        guard let document = controller.geometryEditorDocument else { return "no file" }
        let selectedLayer = controller.selectedGeometryEditorLayerID.flatMap { id in
            document.layers.first { $0.id == id }
        } ?? document.layers.first { $0.id == document.activeLayerID }

        guard let layer = selectedLayer else { return "no layer" }

        var parts: [String] = []
        if !layer.polygons.isEmpty { parts.append("closed polygons") }
        if !layer.openCurves.isEmpty { parts.append("open curves") }
        if !layer.points.isEmpty { parts.append("points") }
        return parts.isEmpty ? "empty layer" : parts.joined(separator: " + ")
    }

    private func geometryUtilitySection(morphLocked: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    iconButton(help: "Undo", disabled: !controller.canUndoGeometryEdit) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 15))
                    } action: {
                        controller.undoGeometryEdit()
                    }
                    iconButton(help: "Redo", disabled: !controller.canRedoGeometryEdit) {
                        Image(systemName: "arrow.uturn.forward").font(.system(size: 15))
                    } action: {
                        controller.redoGeometryEdit()
                    }
                }

                Divider().frame(height: 20)

                Spacer(minLength: 0)

                Divider().frame(height: 20)

                svgExportButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
        .alert("New Layer Name", isPresented: $showingDuplicateToLayerAlert) {
            TextField("Layer name", text: $duplicateLayerName)
            Button("Duplicate") {
                controller.duplicateSelectedGeometryToNewLayer(named: duplicateLayerName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected geometry will be copied to a new layer at its current position.")
        }
    }

    private var geometryNameAndSaveRow: some View {
        HStack(spacing: 8) {
            Text("Name")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            TextField("", text: $geometryName)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 12))
                .frame(minWidth: 90, maxWidth: .infinity)
            saveGeometryButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var saveGeometryButton: some View {
        let disabled = controller.geometryEditorDocument == nil
        return Button {
            controller.saveGeometryEditorDocument(named: geometryName)
            geometryName = currentGeometryName
        } label: {
            SaveToFolderIcon()
                .frame(width: 24, height: 18)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : saveStateColor)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(disabled ? Color.secondary.opacity(0.25) : saveStateColor, lineWidth: 1.2)
        )
        .help(saveStateHelp)
    }

    private var saveStateColor: Color {
        switch controller.geometryEditorSaveState {
        case .unchanged:
            return Color.secondary
        case .unsaved:
            return Color.orange
        case .saved:
            return Color.green
        }
    }

    private var saveStateHelp: String {
        switch controller.geometryEditorSaveState {
        case .unchanged:
            return "Save geometry document"
        case .unsaved:
            return "Save geometry document: unsaved changes"
        case .saved:
            return "Geometry saved"
        }
    }

    @ViewBuilder
    private func regularPolygonParametersSection(_ parameters: EditableRegularPolygonParameters) -> some View {
        InspectorField("Sides") {
            Stepper(
                "\(parameters.sides)",
                value: Binding(
                    get: { controller.selectedRegularPolygonParameters?.sides ?? parameters.sides },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters { $0.sides = newValue }
                    }
                ),
                in: 3...64
            )
            .font(.system(size: 12))
            .help("Regular polygon sides")
        }
        InspectorField("Radius") {
            Slider(
                value: Binding(
                    get: { controller.selectedRegularPolygonParameters?.radius ?? parameters.radius },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters { $0.radius = newValue }
                    }
                ),
                in: 0.02...0.8
            )
            Text(String(format: "%.2f", parameters.radius))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        InspectorField("Inner") {
            Slider(
                value: Binding(
                    get: { controller.selectedRegularPolygonParameters?.innerRadius ?? parameters.innerRadius },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters { $0.innerRadius = newValue }
                    }
                ),
                in: 0.05...1.0
            )
            Text(String(format: "%.2f", parameters.innerRadius))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        InspectorField("Scale X") {
            Slider(
                value: Binding(
                    get: { controller.selectedRegularPolygonParameters?.scaleX ?? parameters.scaleX },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters { $0.scaleX = newValue }
                    }
                ),
                in: 0.1...3.0
            )
            Text(String(format: "%.2f", parameters.scaleX))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        InspectorField("Scale Y") {
            Slider(
                value: Binding(
                    get: { controller.selectedRegularPolygonParameters?.scaleY ?? parameters.scaleY },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters { $0.scaleY = newValue }
                    }
                ),
                in: 0.1...3.0
            )
            Text(String(format: "%.2f", parameters.scaleY))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        InspectorField("Rotation") {
            Slider(
                value: Binding(
                    get: {
                        let current = controller.selectedRegularPolygonParameters?.rotationRadians ?? parameters.rotationRadians
                        return current * 180.0 / .pi
                    },
                    set: { newValue in
                        controller.updateSelectedRegularPolygonParameters {
                            $0.rotationRadians = newValue * .pi / 180.0
                        }
                    }
                ),
                in: -180...180
            )
            Text("\(Int((parameters.rotationRadians * 180.0 / .pi).rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var svgExportButton: some View {
        let disabled = controller.geometryEditorDocument == nil
        return Button {
            controller.saveGeometryLayerAsSVG()
        } label: {
            SVGExportIcon()
                .frame(width: 24, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.secondary)
        .disabled(disabled)
        .help("Save active layer as SVG wireframe to svgs/")
    }

    private var currentGeometryName: String {
        guard let key = controller.selectedGeometryKey else { return "Untitled Polygon" }
        return String(key.split(separator: "/", maxSplits: 1).last ?? "")
    }

    private func handleScaleSliderEditing(_ isEditing: Bool) {
        if isEditing {
            controller.beginGeometryTransformGesture()
        } else {
            controller.endGeometryTransformGesture()
            scaleSliderValue = 0
        }
    }

    private func handleRotateSliderEditing(_ isEditing: Bool) {
        if isEditing {
            controller.beginGeometryTransformGesture()
        } else {
            controller.endGeometryTransformGesture()
            rotateSliderValue = 0
        }
    }

    private func iconRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
    }

    private func iconButton<Content: View>(
        help: String,
        disabled: Bool = false,
        selected: Bool = false,
        size: CGFloat = 22,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .modifier(InstantGeometryTooltip(help))
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.primary)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func iconTextButton(
        _ title: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .disabled(disabled)
            .font(.system(size: 11))
            .modifier(InstantGeometryTooltip(help))
    }

    private func inspectorButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = true,
        selected: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(title, action: action)
            .disabled(disabled)
            .font(.system(size: 12))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func compactButton(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .disabled(disabled)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity)
    }
}

private struct InstantGeometryTooltip: ViewModifier {
    let text: String
    @EnvironmentObject private var controller: AppController

    init(_ text: String) {
        self.text = text
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    controller.hoverHelpText = text
                } else if controller.hoverHelpText == text {
                    controller.hoverHelpText = ""
                }
            }
    }
}

private struct PointCircleIcon: View {
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.5)
            Circle().fill().frame(width: 4, height: 4)
        }
        .padding(4)
    }
}

struct EditPointsIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let dotRadius: CGFloat = 2
            let gap: CGFloat = 3
            let innerRadius = dotRadius + gap
            let outerRadius = size / 2 - 0.75

            Path { path in
                path.move(to: CGPoint(x: centre.x, y: centre.y - innerRadius))
                path.addLine(to: CGPoint(x: centre.x, y: centre.y - outerRadius))
                path.move(to: CGPoint(x: centre.x + innerRadius, y: centre.y))
                path.addLine(to: CGPoint(x: centre.x + outerRadius, y: centre.y))
                path.move(to: CGPoint(x: centre.x, y: centre.y + innerRadius))
                path.addLine(to: CGPoint(x: centre.x, y: centre.y + outerRadius))
                path.move(to: CGPoint(x: centre.x - innerRadius, y: centre.y))
                path.addLine(to: CGPoint(x: centre.x - outerRadius, y: centre.y))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            Circle()
                .fill()
                .frame(width: 4, height: 4)
                .position(centre)
        }
        .padding(4)
    }
}

struct PressureTraceIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.12, y: h * 0.68))
                path.addCurve(
                    to: CGPoint(x: w * 0.88, y: h * 0.34),
                    control1: CGPoint(x: w * 0.32, y: h * 0.18),
                    control2: CGPoint(x: w * 0.58, y: h * 0.88)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
            Circle()
                .fill()
                .frame(width: w * 0.18, height: w * 0.18)
                .position(x: w * 0.72, y: h * 0.42)
            Circle()
                .stroke(lineWidth: 1.2)
                .frame(width: w * 0.32, height: w * 0.32)
                .position(x: w * 0.72, y: h * 0.42)
        }
        .padding(4)
    }
}

struct PolygonGeometryIcon: View {
    var body: some View {
        Rectangle()
            .stroke(lineWidth: 1.5)
            .padding(5)
    }
}

struct OpenCurveGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let rect = proxy.frame(in: .local)
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.30))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.24),
                    control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .padding(4)
    }
}

struct EdgeGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let rect = proxy.frame(in: .local)
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY - rect.height * 0.30))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.30))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .padding(4)
    }
}

private struct ExplodeWeldIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let inner = min(rect.width, rect.height) * 0.16
            let outer = min(rect.width, rect.height) * 0.42
            Path { path in
                for index in 0..<8 {
                    let angle = CGFloat(index) * .pi / 4
                    let start = CGPoint(
                        x: centre.x + cos(angle) * inner,
                        y: centre.y + sin(angle) * inner
                    )
                    let end = CGPoint(
                        x: centre.x + cos(angle) * outer,
                        y: centre.y + sin(angle) * outer
                    )
                    path.move(to: start)
                    path.addLine(to: end)
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            Circle()
                .stroke(lineWidth: 1.2)
                .frame(width: rect.width * 0.26, height: rect.height * 0.26)
                .position(centre)
        }
        .padding(3)
    }
}

private struct RazorBladeIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local).insetBy(dx: 3.5, dy: 3.5)
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.18))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.04))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.20))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.02))
                path.closeSubpath()
            }
            .fill()

            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY - rect.height * 0.12))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.23))
            }
            .stroke(Color(nsColor: .controlBackgroundColor), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.06))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.30))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.18))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY + rect.height * 0.06))
                path.closeSubpath()
            }
            .fill()
        }
        .padding(1)
    }
}

private struct CurvedRazorBladeIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let p0 = CGPoint(x: w * 0.08, y: h * 0.78)
            let c1 = CGPoint(x: w * 0.22, y: h * 0.18)
            let c2 = CGPoint(x: w * 0.72, y: h * 0.85)
            let p3 = CGPoint(x: w * 0.92, y: h * 0.25)
            Path { path in
                path.move(to: p0)
                path.addCurve(to: p3, control1: c1, control2: c2)
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 2]))
            Path { path in
                path.addEllipse(in: CGRect(x: c1.x - 2.5, y: c1.y - 2.5, width: 5, height: 5))
                path.addEllipse(in: CGRect(x: c2.x - 2.5, y: c2.y - 2.5, width: 5, height: 5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
            Path { path in
                path.move(to: p0); path.addLine(to: c1)
                path.move(to: p3); path.addLine(to: c2)
            }
            .stroke(style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [2, 2]))
        }
        .padding(2)
    }
}

struct SnapAllPointsIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "grid")
                .font(.system(size: 13))
                .opacity(0.75)
            Circle()
                .fill()
                .frame(width: 4, height: 4)
                .offset(x: -4, y: -4)
            Circle()
                .fill()
                .frame(width: 4, height: 4)
                .offset(x: 4, y: 0)
            Circle()
                .fill()
                .frame(width: 4, height: 4)
                .offset(x: -1, y: 5)
        }
        .padding(3)
    }
}

private struct SnapAnchorPointsIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "grid")
                .font(.system(size: 13))
                .opacity(0.75)
            Circle()
                .stroke(lineWidth: 1.2)
                .frame(width: 12, height: 12)
            Circle()
                .fill()
                .frame(width: 4.5, height: 4.5)
        }
        .padding(3)
    }
}

struct AnchorSnapIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local).insetBy(dx: 4, dy: 3)
            let centreX = rect.midX
            Path { path in
                path.move(to: CGPoint(x: centreX, y: rect.minY + rect.height * 0.22))
                path.addLine(to: CGPoint(x: centreX, y: rect.maxY - rect.height * 0.18))
                path.move(to: CGPoint(x: centreX - rect.width * 0.22, y: rect.minY + rect.height * 0.38))
                path.addLine(to: CGPoint(x: centreX + rect.width * 0.22, y: rect.minY + rect.height * 0.38))
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.34))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.34),
                    control: CGPoint(x: centreX, y: rect.maxY + rect.height * 0.10)
                )
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.34))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.48))
                path.move(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.34))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.48))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            Circle()
                .stroke(lineWidth: 1.3)
                .frame(width: rect.width * 0.30, height: rect.width * 0.30)
                .position(x: centreX, y: rect.minY + rect.height * 0.14)
        }
        .padding(2)
    }
}

struct SteeringWheelIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) * 0.38
            Path { path in
                path.addEllipse(in: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                path.addEllipse(in: CGRect(
                    x: centre.x - radius * 0.18,
                    y: centre.y - radius * 0.18,
                    width: radius * 0.36,
                    height: radius * 0.36
                ))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            Path { path in
                path.move(to: centre)
                path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius * 0.78))
                path.move(to: centre)
                path.addLine(to: CGPoint(x: centre.x - radius * 0.72, y: centre.y - radius * 0.20))
                path.move(to: centre)
                path.addLine(to: CGPoint(x: centre.x + radius * 0.72, y: centre.y - radius * 0.20))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .padding(3)
    }
}

private struct OvalGeometryIcon: View {
    var body: some View {
        Ellipse()
            .stroke(lineWidth: 1.5)
            .frame(width: 10, height: 19)
    }
}

private struct PointByPointIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let points = [
                CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY - rect.height * 0.20),
                CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.38),
                CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.40),
                CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.12)
            ]
            ZStack {
                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                    path.addLine(to: points[2])
                    path.addLine(to: points[3])
                }
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[3])
                }
                .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [4, 3]))
                ForEach(0..<points.count, id: \.self) { index in
                    Circle()
                        .fill()
                        .frame(width: 4.5, height: 4.5)
                        .position(points[index])
                }
            }
        }
        .padding(2)
    }
}

private struct KnifeLayerStackIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let left = rect.minX + rect.width * 0.16
            let right = rect.maxX - rect.width * 0.16
            let topX = rect.midX
            let layerWidth = rect.width * 0.28
            let layerHeight = rect.height * 0.16
            Path { path in
                func addLayer(y: CGFloat) {
                    path.move(to: CGPoint(x: topX, y: y))
                    path.addLine(to: CGPoint(x: right, y: y + layerHeight))
                    path.addLine(to: CGPoint(x: topX, y: y + layerHeight * 2))
                    path.addLine(to: CGPoint(x: left, y: y + layerHeight))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: left, y: y + layerHeight))
                    path.addLine(to: CGPoint(x: left + layerWidth, y: y + layerHeight * 2.45))
                    path.addLine(to: CGPoint(x: topX, y: y + layerHeight * 2))
                    path.move(to: CGPoint(x: right, y: y + layerHeight))
                    path.addLine(to: CGPoint(x: right - layerWidth, y: y + layerHeight * 2.45))
                    path.addLine(to: CGPoint(x: topX, y: y + layerHeight * 2))
                }

                addLayer(y: rect.minY + rect.height * 0.16)
                addLayer(y: rect.minY + rect.height * 0.34)
                addLayer(y: rect.minY + rect.height * 0.52)
            }
            .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .padding(2)
    }
}

private struct DisplacementExtrudeIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let mx = r.midX
            Path { path in
                // Bottom edge (original) — horizontal bar
                path.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY + r.height * 0.22))
                path.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.midY + r.height * 0.22))
                // Top edge (displaced) — horizontal bar above
                path.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY - r.height * 0.28))
                path.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.midY - r.height * 0.28))
                // Left connector
                path.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY + r.height * 0.22))
                path.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY - r.height * 0.28))
                // Right connector
                path.move(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.midY + r.height * 0.22))
                path.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.midY - r.height * 0.28))
                // Upward arrow from midpoint of top edge
                path.move(to: CGPoint(x: mx, y: r.midY - r.height * 0.28))
                path.addLine(to: CGPoint(x: mx, y: r.minY + r.height * 0.08))
                path.move(to: CGPoint(x: mx - r.width * 0.13, y: r.minY + r.height * 0.22))
                path.addLine(to: CGPoint(x: mx, y: r.minY + r.height * 0.08))
                path.addLine(to: CGPoint(x: mx + r.width * 0.13, y: r.minY + r.height * 0.22))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .padding(2)
    }
}

private struct ScaleExtrudeIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            Path { path in
                // Outer ring (larger, dashed)
                let outerRect = CGRect(
                    x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.06,
                    width: r.width * 0.88, height: r.height * 0.88
                )
                path.addEllipse(in: outerRect)
                // Inner ring (smaller, solid)
                let innerRect = CGRect(
                    x: r.minX + r.width * 0.26, y: r.minY + r.height * 0.26,
                    width: r.width * 0.48, height: r.height * 0.48
                )
                path.addEllipse(in: innerRect)
                // Short spokes connecting inner to outer at cardinal points
                let ox = r.midX; let oy = r.midY
                let iR = r.width * 0.24; let oR = r.width * 0.44
                for angle: Double in [0, .pi / 2, .pi, .pi * 1.5] {
                    let cosA = cos(angle); let sinA = sin(angle)
                    path.move(to: CGPoint(x: ox + iR * cosA, y: oy + iR * sinA))
                    path.addLine(to: CGPoint(x: ox + oR * cosA, y: oy + oR * sinA))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        .padding(2)
    }
}

struct CopyGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let w = r.width; let h = r.height
            // Back sheet (offset up-left)
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.08, y: r.minY + h * 0.08,
                               width: w * 0.60, height: h * 0.60),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
            // Front sheet (offset down-right)
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.32, y: r.minY + h * 0.32,
                               width: w * 0.60, height: h * 0.60),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .fill(Color(nsColor: .windowBackgroundColor))
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.32, y: r.minY + h * 0.32,
                               width: w * 0.60, height: h * 0.60),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
        }
        .padding(2)
    }
}

struct PasteGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let w = r.width; let h = r.height
            // Clipboard body
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.18, y: r.minY + h * 0.22,
                               width: w * 0.64, height: h * 0.70),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
            // Clip tab at top centre
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.36, y: r.minY + h * 0.08,
                               width: w * 0.28, height: h * 0.22),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .fill(Color(nsColor: .windowBackgroundColor))
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.36, y: r.minY + h * 0.08,
                               width: w * 0.28, height: h * 0.22),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
            // Small sheet on clipboard
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w * 0.28, y: r.minY + h * 0.38,
                               width: w * 0.44, height: h * 0.44),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0))
        }
        .padding(2)
    }
}

struct DeleteSelectedGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let w = r.width; let h = r.height
            // Dashed bounding square
            Path { path in
                path.addRoundedRect(
                    in: CGRect(x: r.minX + w*0.06, y: r.minY + h*0.06,
                               width: w*0.88, height: h*0.88),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            // Triangle inside
            Path { path in
                path.move(to:    CGPoint(x: r.minX + w*0.50, y: r.minY + h*0.22))
                path.addLine(to: CGPoint(x: r.minX + w*0.82, y: r.minY + h*0.78))
                path.addLine(to: CGPoint(x: r.minX + w*0.18, y: r.minY + h*0.78))
                path.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2))
        }
        .padding(2)
    }
}

struct DeleteAllLayerGeometryIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            Group {
                daliCircle(r)
                daliTriangle(r)
                daliStar(r)
            }
        }
        .padding(2)
    }

    private func daliCircle(_ r: CGRect) -> some View {
        Path { path in
            path.addEllipse(in: CGRect(x: r.minX + r.width*0.04, y: r.minY + r.height*0.04,
                                       width: r.width*0.46, height: r.height*0.46))
        }
        .stroke(style: StrokeStyle(lineWidth: 1.1))
    }

    private func daliTriangle(_ r: CGRect) -> some View {
        Path { path in
            path.move(to:    CGPoint(x: r.minX + r.width*0.30, y: r.minY + r.height*0.24))
            path.addLine(to: CGPoint(x: r.minX + r.width*0.72, y: r.minY + r.height*0.94))
            path.addLine(to: CGPoint(x: r.minX + r.width*0.06, y: r.minY + r.height*0.94))
            path.closeSubpath()
        }
        .stroke(style: StrokeStyle(lineWidth: 1.1))
    }

    private func daliStar(_ r: CGRect) -> some View {
        let cx = Double(r.minX + r.width * 0.70)
        let cy = Double(r.minY + r.height * 0.40)
        let outerR = Double(r.width) * 0.28
        let innerR = Double(r.width) * 0.12
        var path = Path()
        for i in 0..<5 {
            let oa = Double(i) * 2 * .pi / 5 - .pi / 2
            let ia = oa + .pi / 5
            let op = CGPoint(x: cx + outerR * cos(oa), y: cy + outerR * sin(oa))
            let ip = CGPoint(x: cx + innerR * cos(ia), y: cy + innerR * sin(ia))
            if i == 0 { path.move(to: op) } else { path.addLine(to: op) }
            path.addLine(to: ip)
        }
        path.closeSubpath()
        return path.stroke(style: StrokeStyle(lineWidth: 1.0))
    }
}

private struct SaveToFolderIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r  = proxy.frame(in: .local).insetBy(dx: 2, dy: 2)
            let w  = r.width, h = r.height
            // Folder outline: rectangle with tab at top-left
            Path { path in
                path.move(to:    CGPoint(x: r.minX,          y: r.minY + h*0.30))
                path.addLine(to: CGPoint(x: r.minX + w*0.28, y: r.minY + h*0.30))
                path.addLine(to: CGPoint(x: r.minX + w*0.37, y: r.minY + h*0.42))
                path.addLine(to: CGPoint(x: r.maxX,          y: r.minY + h*0.42))
                path.addLine(to: CGPoint(x: r.maxX,          y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX,          y: r.maxY))
                path.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Downward arrow centred in folder body
            let ax   = r.midX
            let atop = r.minY + h * 0.50
            let atip = r.maxY - h * 0.18
            let hh   = w * 0.20
            Path { path in
                path.move(to:    CGPoint(x: ax,      y: atop))
                path.addLine(to: CGPoint(x: ax,      y: atip))
                path.move(to:    CGPoint(x: ax - hh, y: atip - hh))
                path.addLine(to: CGPoint(x: ax,      y: atip))
                path.addLine(to: CGPoint(x: ax + hh, y: atip - hh))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .padding(1)
    }
}

private struct GeometryEditorSaveStateIndicator: View {
    let state: GeometryEditorSaveState

    var body: some View {
        Circle()
            .fill(fillColor)
            .stroke(Color.primary.opacity(0.55), lineWidth: 1.2)
            .frame(width: 10, height: 10)
            .help(helpText)
    }

    private var fillColor: Color {
        switch state {
        case .unchanged:
            return .clear
        case .unsaved:
            return Color.orange
        case .saved:
            return Color.green
        }
    }

    private var helpText: String {
        switch state {
        case .unchanged:
            return "No geometry changes since opening"
        case .unsaved:
            return "Unsaved geometry changes"
        case .saved:
            return "Geometry saved"
        }
    }
}

/// Folder outline with a diagonal arrow from the folder centre toward the upper-right corner.
struct FolderExportIcon: View {
    var strokeWidth: CGFloat = 1.5
    var compactFolder: Bool = false
    var showsInterlockedSVG: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let outer = proxy.frame(in: .local).insetBy(dx: 2, dy: 2)
            let folderWidth = compactFolder ? outer.width * 0.76 : outer.width
            let r = CGRect(
                x: outer.minX + (outer.width - folderWidth) * 0.5,
                y: outer.minY,
                width: folderWidth,
                height: outer.height
            )
            let w = r.width, h = r.height
            // Folder outline
            Path { path in
                path.move(to:    CGPoint(x: r.minX,          y: r.minY + h*0.30))
                path.addLine(to: CGPoint(x: r.minX + w*0.28, y: r.minY + h*0.30))
                path.addLine(to: CGPoint(x: r.minX + w*0.37, y: r.minY + h*0.42))
                path.addLine(to: CGPoint(x: r.maxX,          y: r.minY + h*0.42))
                path.addLine(to: CGPoint(x: r.maxX,          y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX,          y: r.maxY))
                path.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

            if showsInterlockedSVG {
                let textY = r.minY + h * 0.48
                Text("S")
                    .font(.system(size: max(7, h * 0.35), weight: .bold, design: .rounded))
                    .position(x: r.midX - w * 0.16, y: textY)
                Text("G")
                    .font(.system(size: max(7, h * 0.35), weight: .bold, design: .rounded))
                    .position(x: r.midX + w * 0.16, y: textY)
                Text("V")
                    .font(.system(size: max(10, h * 0.72), weight: .bold, design: .rounded))
                    .position(x: r.midX, y: r.minY + h * 0.62)
            } else {
                // Diagonal arrow: folder-body centre → upper-right
                let tailX = r.midX - w * 0.06
                let tailY = r.minY + h * 0.76
                let tipX  = r.maxX - w * 0.13
                let tipY  = r.minY + h * 0.53
                let dx = tipX - tailX, dy = tipY - tailY
                let len = (dx*dx + dy*dy).squareRoot()
                let ux = dx / len, uy = dy / len
                let px = -uy,      py = ux
                let hw = w * 0.16
                Path { path in
                    path.move(to:    CGPoint(x: tailX, y: tailY))
                    path.addLine(to: CGPoint(x: tipX,  y: tipY))
                    path.move(to:    CGPoint(x: tipX - ux*hw + px*hw*0.65, y: tipY - uy*hw + py*hw*0.65))
                    path.addLine(to: CGPoint(x: tipX,  y: tipY))
                    path.addLine(to: CGPoint(x: tipX - ux*hw - px*hw*0.65, y: tipY - uy*hw - py*hw*0.65))
                }
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .padding(1)
    }
}

struct SVGExportIcon: View {
    var body: some View {
        Text("SVG")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospaced()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoadDocumentIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let w = r.width; let h = r.height
            let midX = r.minX + w * 0.50
            let arrowBase = r.minY + h * 0.88
            let arrowTip = r.minY + h * 0.28
            let headHalf = w * 0.28
            let lineY = r.minY + h * 0.12
            // Shaft
            Path { path in
                path.move(to:    CGPoint(x: midX, y: arrowBase))
                path.addLine(to: CGPoint(x: midX, y: arrowTip))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5))
            // Arrowhead pointing up
            Path { path in
                path.move(to:    CGPoint(x: midX - headHalf, y: arrowTip + h*0.22))
                path.addLine(to: CGPoint(x: midX,            y: arrowTip))
                path.addLine(to: CGPoint(x: midX + headHalf, y: arrowTip + h*0.22))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Top line
            Path { path in
                path.move(to:    CGPoint(x: r.minX + w*0.10, y: lineY))
                path.addLine(to: CGPoint(x: r.minX + w*0.90, y: lineY))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .padding(2)
    }
}

// Bezier handle icon: small filled square (anchor) at lower-left with an arm
// extending to an open circle (control handle) at upper-right.  Visually
// pairs with CrosshairAnchorIcon — anchor is subordinate here, handle prominent.
struct ControlHandleIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let size  = min(rect.width, rect.height)
            let p1    = CGPoint(x: rect.minX + size * 0.28, y: rect.maxY - size * 0.28)
            let p2    = CGPoint(x: rect.maxX - size * 0.26, y: rect.minY + size * 0.26)
            let sq    = size * 0.13
            let cr    = size * 0.22
            Path { path in
                path.move(to: p1); path.addLine(to: p2)
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            Path { path in
                path.addRect(CGRect(x: p1.x - sq, y: p1.y - sq, width: sq * 2, height: sq * 2))
            }
            .fill()
            Path { path in
                path.addEllipse(in: CGRect(x: p2.x - cr, y: p2.y - cr, width: cr * 2, height: cr * 2))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5))
        }
        .padding(2)
    }
}

struct CrosshairAnchorIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let cx = rect.midX, cy = rect.midY
            let r   = min(rect.width, rect.height) * 0.27
            let gap = min(rect.width, rect.height) * 0.07
            Path { path in
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                path.move(to: CGPoint(x: cx, y: rect.minY + 2));   path.addLine(to: CGPoint(x: cx, y: cy - r - gap))
                path.move(to: CGPoint(x: cx, y: cy + r + gap));    path.addLine(to: CGPoint(x: cx, y: rect.maxY - 2))
                path.move(to: CGPoint(x: rect.minX + 2, y: cy));   path.addLine(to: CGPoint(x: cx - r - gap, y: cy))
                path.move(to: CGPoint(x: cx + r + gap, y: cy));    path.addLine(to: CGPoint(x: rect.maxX - 2, y: cy))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .padding(2)
    }
}

// MARK: - Quick Setup section

private struct PipelineIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let turnX: CGFloat = w * 0.72
            let hY:    CGFloat = h * 0.30
            let bendR: CGFloat = min(w * 0.18, h * 0.42)

            // Centerline: horizontal → smooth elbow → vertical
            var pipe = Path()
            pipe.move(to: CGPoint(x: 0, y: hY))
            pipe.addLine(to: CGPoint(x: turnX - bendR, y: hY))
            pipe.addQuadCurve(
                to:      CGPoint(x: turnX, y: hY + bendR),
                control: CGPoint(x: turnX, y: hY)
            )
            pipe.addLine(to: CGPoint(x: turnX, y: h))

            // Pipe outer wall (thick)
            ctx.stroke(pipe, with: .color(Color.secondary.opacity(0.50)),
                       style: StrokeStyle(lineWidth: 9, lineCap: .butt, lineJoin: .round))

            // Pipe inner channel (hollow look)
            ctx.stroke(pipe, with: .color(Color(NSColor.controlBackgroundColor).opacity(0.65)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .butt, lineJoin: .round))

            // → chevron in horizontal leg
            let cs: CGFloat = 3.5
            let ax = (turnX - bendR) * 0.46
            var chH = Path()
            chH.move(to: CGPoint(x: ax - cs * 0.7, y: hY - cs))
            chH.addLine(to: CGPoint(x: ax + cs * 0.3, y: hY))
            chH.addLine(to: CGPoint(x: ax - cs * 0.7, y: hY + cs))
            ctx.stroke(chH, with: .color(Color.primary.opacity(0.60)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // ↓ chevron in vertical leg
            let bx = turnX
            let by = hY + bendR + (h - hY - bendR) * 0.52
            var chV = Path()
            chV.move(to: CGPoint(x: bx - cs, y: by - cs * 0.7))
            chV.addLine(to: CGPoint(x: bx, y: by + cs * 0.3))
            chV.addLine(to: CGPoint(x: bx + cs, y: by - cs * 0.7))
            ctx.stroke(chV, with: .color(Color.primary.opacity(0.60)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct QuickSetupLayerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let layerID: UUID?
}

private struct QuickSetupSection: View {
    @EnvironmentObject private var controller: AppController
    let folder:  String
    let geoName: String

    @State private var qsLayerTargetID:   String      = QuickSetupSection.allVisibleLayerID
    @State private var qsBaseName:        String      = ""
    @State private var qsSubdivSetName:   String      = ""
    @State private var qsSpriteSetName:   String      = ""
    @State private var qsRendererSetName: String      = ""
    @State private var qsSpriteName:      String      = ""
    @State private var qsRendererName:    String      = ""
    @State private var qsRendererMode:    RendererMode = .filled

    var body: some View {
        VStack(spacing: 0) {
            PipelineIcon()
                .frame(width: 48, height: 30)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 5)
        InspectorSection("Quick Pipeline Setup") {
            pipelinePhaseHeader(.geometry)
            if layerOptions.count > 1 {
                InspectorField("Source") {
                    Picker("", selection: $qsLayerTargetID) {
                        ForEach(layerOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                }
                .loomHelp("Which geometry layer's polygons to use as the pipeline source. 'All Visible Layers' combines all visible layers into one shape.")
            }
            InspectorField("Base name") {
                TextField("", text: $qsBaseName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .onChange(of: qsBaseName) { _, _ in
                        applyRecommendedNames(overwrite: true)
                    }
            }
            .loomHelp("Root name used to auto-generate names for the shape, sprite, and renderer. Seeded from the geometry filename or selected layer name.")
            Divider().padding(.vertical, 4)
            pipelinePhaseHeader(.subdivision)
            InspectorField("Subdivision set") {
                Picker("", selection: $qsSubdivSetName) {
                    ForEach(subdivisionSetOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Subdivision parameter set applied to the generated shape. Choose None for raw unsubdivided geometry.")
            Divider().padding(.vertical, 4)
            pipelinePhaseHeader(.sprites)
            InspectorField("Sprite set") {
                Picker("", selection: $qsSpriteSetName) {
                    ForEach(spriteSetOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Sprite set that will contain the new sprite. Pick an existing set to add to it, or type a new name to create one.")
            InspectorField("Sprite") {
                TextField("", text: $qsSpriteName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Name of the sprite to create within the sprite set.")
            Divider().padding(.vertical, 4)
            pipelinePhaseHeader(.rendering)
            InspectorField("Renderer set") {
                Picker("", selection: $qsRendererSetName) {
                    ForEach(rendererSetOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Renderer set assigned to the new sprite. Pick an existing set to add to it, or type a new name to create one.")
            InspectorField("Renderer") {
                Picker("", selection: $qsRendererName) {
                    ForEach(rendererOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Name of the renderer to create within the renderer set.")
            InspectorField("Mode") {
                Picker("", selection: $qsRendererMode) {
                    ForEach(RendererMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .loomHelp("Drawing mode for the new renderer — Stroked (outline), Filled (solid), Filled+Stroked (both), Points (dot cloud), Brushed (stamps along path), Stamped (images at points).")
            Divider().padding(.vertical, 4)
            HStack(spacing: 6) {
                let n = controller.projectConfig.map { gatherPipelines(geoName: geoName, cfg: $0).count } ?? 0
                Circle()
                    .fill(n == 0 ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(n == 0 ? "No Pipelines" : n == 1 ? "1 Pipeline" : "\(n) Pipelines")
                    .font(.system(size: 11))
                    .foregroundStyle(n == 0 ? Color.secondary : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            actionButton("Make Pipeline") { makePipeline() }
                .disabled(!canMakePipeline)
        }
        .onAppear {
            qsLayerTargetID = initialLayerTargetID
            applyRecommendedNames(overwrite: false)
        }
        .onChange(of: geoName) { _, _ in
            qsLayerTargetID = initialLayerTargetID
            // Reset base name when the geometry file changes so it seeds from the new file stem.
            qsBaseName = stem
            applyRecommendedNames(overwrite: true)
        }
        .onChange(of: qsLayerTargetID) { _, _ in
            if let layer = selectedLayerOption, layer.layerID != nil {
                qsBaseName = sanitized(layer.name)
            } else {
                qsBaseName = stem
            }
            applyRecommendedNames(overwrite: true)
        }
        .onChange(of: sourceIsCleanParametricRegularPolygon) { _, isCleanParametricRegularPolygon in
            if isCleanParametricRegularPolygon {
                qsSubdivSetName = Self.noSubdivisionName
                qsRendererMode = .stroked
            }
        }
        .onChange(of: qsRendererSetName) { _, _ in
            if !rendererOptions.contains(qsRendererName) {
                qsRendererName = recommendedRendererName
            }
        }
        }  // VStack
    }

    // MARK: - Layout helper

    private func pipelinePhaseHeader(_ tab: AppTab) -> some View {
        HStack(spacing: 5) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 11))
            Text(tab.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .frame(maxWidth: .infinity)
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
    }

    // MARK: - Actions

    private static let allVisibleLayerID = "__all_visible_layers__"
    private static let noSubdivisionName = "None"

    private var canMakePipeline: Bool {
        !geoName.isEmpty &&
        !sourcePolygonSetName.isEmpty &&
        !clean(qsSubdivSetName).isEmpty &&
        !clean(qsSpriteSetName).isEmpty &&
        !clean(qsSpriteName).isEmpty &&
        !clean(qsRendererSetName).isEmpty &&
        !clean(qsRendererName).isEmpty
    }

    private var pipelineExists: Bool {
        guard let cfg = controller.projectConfig else { return false }
        let subdivSetName = selectedSubdivisionParamsSetName
        let shapeSetName = recommendedShapeSetName
        let shapeName = recommendedShapeName
        let polygonSetName = sourcePolygonSetName
        let spriteSetName = clean(qsSpriteSetName)
        let spriteName = clean(qsSpriteName)
        let rendererSetName = clean(qsRendererSetName)
        let rendererName = clean(qsRendererName)

        let hasPolygonSet = cfg.polygonConfig.library.polygonSets.contains {
            $0.name == polygonSetName && layerTargetMatches($0)
        }
        let hasSubdiv = subdivSetName.isEmpty || cfg.subdivisionConfig.paramsSets.contains { $0.name == subdivSetName }
        let hasShape = cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == shapeSetName })?
            .shapes
            .contains {
                $0.name == shapeName &&
                $0.sourceType == .polygonSet &&
                $0.polygonSetName == polygonSetName &&
                $0.subdivisionParamsSetName == subdivSetName
            } ?? false
        let hasRenderer = cfg.renderingConfig.library.rendererSets
            .first(where: { $0.name == rendererSetName })?
            .renderers
            .contains { $0.name == rendererName } ?? false
        let hasSprite = cfg.spriteConfig.library.spriteSets
            .first(where: { $0.name == spriteSetName })?
            .sprites
            .contains {
                $0.name == spriteName &&
                $0.shapeSetName == shapeSetName &&
                $0.shapeName == shapeName &&
                $0.rendererSetName == rendererSetName
            } ?? false

        return hasPolygonSet && hasSubdiv && hasShape && hasRenderer && hasSprite
    }

    private func makePipeline() {
        let polygonSetName = sourcePolygonSetName
        let subdivSetName = selectedSubdivisionParamsSetName
        let shapeSetName = recommendedShapeSetName
        let shapeName = recommendedShapeName
        let spriteSetName = clean(qsSpriteSetName)
        let spriteName = clean(qsSpriteName)
        let rendererSetName = clean(qsRendererSetName)
        let rendererName = clean(qsRendererName)
        let rendererMode = recommendedQuickSetupRendererMode

        controller.updateProjectConfig { cfg in
            upsertLayerTargetPolygonSet(in: &cfg, polygonSetName: polygonSetName)

            if !subdivSetName.isEmpty,
               !cfg.subdivisionConfig.paramsSets.contains(where: { $0.name == subdivSetName }) {
                let param = SubdivisionParams(name: "\(geoName)_quad_1", subdivisionType: .quad)
                cfg.subdivisionConfig.paramsSets.append(
                    SubdivisionParamsSet(name: subdivSetName, params: [param])
                )
            }

            let shape = ShapeDef(
                name: shapeName,
                sourceType: .polygonSet,
                polygonSetName: polygonSetName,
                subdivisionParamsSetName: subdivSetName
            )
            if let setIndex = cfg.shapeConfig.library.shapeSets.firstIndex(where: { $0.name == shapeSetName }) {
                if let shapeIndex = cfg.shapeConfig.library.shapeSets[setIndex].shapes
                    .firstIndex(where: { $0.name == shapeName }) {
                    cfg.shapeConfig.library.shapeSets[setIndex].shapes[shapeIndex] = shape
                } else {
                    cfg.shapeConfig.library.shapeSets[setIndex].shapes.append(shape)
                }
            } else {
                cfg.shapeConfig.library.shapeSets.append(ShapeSet(name: shapeSetName, shapes: [shape]))
            }

            var rendererSetIndex: Int
            if let existing = cfg.renderingConfig.library.rendererSets.firstIndex(where: { $0.name == rendererSetName }) {
                rendererSetIndex = existing
            } else {
                cfg.renderingConfig.library.rendererSets.append(RendererSet(name: rendererSetName))
                rendererSetIndex = cfg.renderingConfig.library.rendererSets.count - 1
            }

            let renderer = Renderer(
                name: rendererName,
                mode: rendererMode,
                strokeWidth: 1.0,
                strokeColor: .black,
                fillColor: LoomColor(r: 220, g: 220, b: 220)
            )
            if let rendererIndex = cfg.renderingConfig.library.rendererSets[rendererSetIndex].renderers
                .firstIndex(where: { $0.name == rendererName }) {
                cfg.renderingConfig.library.rendererSets[rendererSetIndex].renderers[rendererIndex] = renderer
            } else {
                cfg.renderingConfig.library.rendererSets[rendererSetIndex].renderers.append(renderer)
            }

            let sprite = SpriteDef(
                name: spriteName,
                shapeSetName: shapeSetName,
                shapeName: shapeName,
                rendererSetName: rendererSetName
            )
            if let setIndex = cfg.spriteConfig.library.spriteSets.firstIndex(where: { $0.name == spriteSetName }) {
                if let spriteIndex = cfg.spriteConfig.library.spriteSets[setIndex].sprites
                    .firstIndex(where: { $0.name == spriteName }) {
                    cfg.spriteConfig.library.spriteSets[setIndex].sprites[spriteIndex] = sprite
                } else {
                    cfg.spriteConfig.library.spriteSets[setIndex].sprites.append(sprite)
                }
            } else {
                cfg.spriteConfig.library.spriteSets.append(SpriteSet(name: spriteSetName, sprites: [sprite]))
            }
        }
    }

    private func upsertLayerTargetPolygonSet(in cfg: inout ProjectConfig, polygonSetName: String) {
        guard let selectedLayer = selectedLayerOption,
              let layerID = selectedLayer.layerID
        else { return }

        guard let documentDef = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == geoName }) else {
            return
        }

        var targetDef = PolygonSetDef(
            name: polygonSetName,
            folder: documentDef.folder,
            filename: documentDef.filename,
            polygonType: documentDef.polygonType,
            regularParams: nil,
            editableLayerID: layerID,
            editableLayerName: selectedLayer.name
        )
        if targetDef.folder.isEmpty {
            targetDef.folder = "polygonSets"
        }

        if let index = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == polygonSetName }) {
            cfg.polygonConfig.library.polygonSets[index] = targetDef
        } else {
            cfg.polygonConfig.library.polygonSets.append(targetDef)
        }
    }

    private func layerTargetMatches(_ def: PolygonSetDef) -> Bool {
        guard let selectedLayer = selectedLayerOption,
              let selectedLayerID = selectedLayer.layerID
        else {
            return def.name == geoName && def.editableLayerID == nil && clean(def.editableLayerName ?? "").isEmpty
        }
        return def.editableLayerID == selectedLayerID ||
            (def.editableLayerID == nil && clean(def.editableLayerName ?? "") == selectedLayer.name)
    }

    private func applyRecommendedNames(overwrite: Bool) {
        guard !geoName.isEmpty else { return }
        // Seed base name from the geo stem on first load only (never overwrite after user edits it).
        setIfNeeded(&qsBaseName, stem, overwrite: false)
        setIfNeeded(&qsSubdivSetName, recommendedQuickSetupSubdivSetName, overwrite: overwrite)
        setIfNeeded(&qsSpriteSetName, recommendedSpriteSetName, overwrite: overwrite)
        setIfNeeded(&qsSpriteName, recommendedSpriteName, overwrite: overwrite)
        setIfNeeded(&qsRendererSetName, recommendedRendererSetName, overwrite: overwrite)
        setIfNeeded(&qsRendererName, recommendedRendererName, overwrite: overwrite)
    }

    private func setIfNeeded(_ value: inout String, _ recommendation: String, overwrite: Bool) {
        if overwrite || clean(value).isEmpty {
            value = recommendation
        }
    }

    private var initialLayerTargetID: String {
        guard let def = controller.projectConfig?.polygonConfig.library.polygonSets.first(where: { $0.name == geoName }),
              let layerID = def.editableLayerID
        else { return Self.allVisibleLayerID }
        return layerID.uuidString
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitized(_ value: String) -> String {
        let cleaned = clean(value)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "Geometry" : result
    }

    private var stem: String {
        sanitized(geoName)
    }

    /// Stem used for set names (sprite set, renderer set, subdivision set, shape set).
    /// Populated from qsBaseName when the user has typed one; falls back to sourceNameStem.
    private var baseStem: String {
        let b = sanitized(qsBaseName)
        return b.isEmpty ? sourceNameStem : b
    }

    private var selectedLayerOption: QuickSetupLayerOption? {
        layerOptions.first { $0.id == qsLayerTargetID }
    }

    private var sourceNameStem: String {
        guard let selectedLayer = selectedLayerOption,
              selectedLayer.layerID != nil
        else { return stem }
        return "\(stem)_\(sanitized(selectedLayer.name))"
    }

    private var sourcePolygonSetName: String {
        guard let selectedLayer = selectedLayerOption,
              selectedLayer.layerID != nil
        else { return geoName }
        return sourceNameStem
    }

    // Set names use baseStem so users can give shared containers a generic label.
    // Item names (shape, sprite, renderer) remain source-specific so each layer
    // is distinguishable within its set.
    private var recommendedSubdivSetName: String { "\(stem)_\(baseStem)" }
    private var recommendedQuickSetupSubdivSetName: String {
        if sourceIsCleanParametricRegularPolygon {
            return Self.noSubdivisionName
        }
        return sourceSupportsSubdivision ? recommendedSubdivSetName : Self.noSubdivisionName
    }
    private var recommendedShapeSetName: String { "\(baseStem)_Shapes" }
    private var recommendedShapeName: String { "\(sourceNameStem)_Shape" }
    private var recommendedSpriteSetName: String { stem }
    private var recommendedSpriteName: String { baseStem }
    private var recommendedRendererSetName: String { "\(stem)_\(baseStem)" }
    private var recommendedRendererName: String { baseStem }
    private var recommendedQuickSetupRendererMode: RendererMode {
        sourceIsCleanParametricRegularPolygon ? .stroked : qsRendererMode
    }

    private var layerOptions: [QuickSetupLayerOption] {
        var options = [
            QuickSetupLayerOption(
                id: Self.allVisibleLayerID,
                name: "All visible layers",
                layerID: nil
            )
        ]
        guard folder == "polygonSets",
              let document = editableGeometryDocument
        else { return options }
        options.append(contentsOf: document.layers.map {
            QuickSetupLayerOption(id: $0.id.uuidString, name: $0.name, layerID: $0.id)
        })
        return options
    }

    private var editableGeometryDocument: EditableGeometryDocument? {
        if controller.selectedGeometryKey == "polygonSets/\(geoName)",
           let document = controller.geometryEditorDocument {
            return document
        }
        guard let projectURL = controller.projectURL,
              let def = controller.projectConfig?.polygonConfig.library.polygonSets.first(where: { $0.name == geoName }),
              !def.filename.isEmpty,
              def.filename.lowercased().hasSuffix(".json")
        else { return nil }
        let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
        return try? EditableGeometryJSONLoader.load(
            url: projectURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
        )
    }

    private var selectedSubdivisionParamsSetName: String {
        let value = clean(qsSubdivSetName)
        return value.caseInsensitiveCompare(Self.noSubdivisionName) == .orderedSame ? "" : value
    }

    private var sourceSupportsSubdivision: Bool {
        if folder == "regularPolygons" {
            return true
        }
        guard folder == "polygonSets" else {
            return false
        }
        guard let document = editableGeometryDocument else {
            return true
        }
        if let selectedLayer = selectedLayerOption,
           let layerID = selectedLayer.layerID {
            return document.layers
                .first(where: { $0.id == layerID })?
                .polygons
                .contains(where: { $0.isVisible }) ?? false
        }
        return document.layers.contains { layer in
            layer.isVisible && layer.polygons.contains(where: { $0.isVisible })
        }
    }

    private var sourceIsCleanParametricRegularPolygon: Bool {
        guard folder == "polygonSets",
              let document = editableGeometryDocument
        else { return false }
        let visiblePolygons: [EditableClosedPolygon]
        if let selectedLayer = selectedLayerOption,
           let layerID = selectedLayer.layerID {
            visiblePolygons = document.layers
                .first(where: { $0.id == layerID })?
                .polygons
                .filter(\.isVisible) ?? []
        } else {
            visiblePolygons = document.layers.flatMap { layer in
                layer.isVisible ? layer.polygons.filter(\.isVisible) : []
            }
        }
        guard visiblePolygons.count == 1,
              case .regularPolygon = visiblePolygons[0].parametricSource
        else { return false }
        return true
    }

    private var subdivisionSetOptions: [String] {
        guard sourceSupportsSubdivision else { return [Self.noSubdivisionName] }
        return uniqueOptions(
            [Self.noSubdivisionName, recommendedSubdivSetName] +
            (controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? [])
        )
    }

    private var spriteSetOptions: [String] {
        uniqueOptions([recommendedSpriteSetName] + (controller.projectConfig?.spriteConfig.library.spriteSets.map(\.name) ?? []))
    }

    private var rendererSetOptions: [String] {
        uniqueOptions([recommendedRendererSetName] + (controller.projectConfig?.renderingConfig.library.rendererSets.map(\.name) ?? []))
    }

    private var rendererOptions: [String] {
        let existing = controller.projectConfig?.renderingConfig.library.rendererSets
            .first(where: { $0.name == qsRendererSetName })?
            .renderers
            .map(\.name) ?? []
        return uniqueOptions([recommendedRendererName] + existing)
    }

    private func uniqueOptions(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var options: [String] = []
        for name in names.map(clean) where !name.isEmpty && !seen.contains(name) {
            options.append(name)
            seen.insert(name)
        }
        return options
    }
}

// MARK: - Pipeline summary & browser

private struct PipelineSummary: Identifiable {
    struct RendererEntry: Identifiable {
        let id: Int
        let name: String
        let mode: RendererMode
    }
    let id: Int
    let sourceName: String
    let polySetName: String
    let subdivSetName: String
    let shapeSetName: String
    let shapeName: String
    let spriteSetName: String
    let spriteName: String
    let rendererSetName: String
    let renderers: [RendererEntry]
}

private func gatherPipelines(geoName: String, cfg: ProjectConfig) -> [PipelineSummary] {
    let masterFilename = cfg.polygonConfig.library.polygonSets
        .first(where: { $0.name == geoName })?.filename ?? ""

    let relatedPolySets = cfg.polygonConfig.library.polygonSets.filter {
        $0.name == geoName ||
        (!masterFilename.isEmpty && $0.filename == masterFilename && $0.editableLayerID != nil)
    }

    var results: [PipelineSummary] = []
    for polySet in relatedPolySets {
        let sourceName = polySet.name == geoName
            ? "All visible layers"
            : (polySet.editableLayerName.flatMap { $0.isEmpty ? nil : $0 } ?? polySet.name)
        for shapeSet in cfg.shapeConfig.library.shapeSets {
            for shape in shapeSet.shapes where shape.polygonSetName == polySet.name {
                for spriteSet in cfg.spriteConfig.library.spriteSets {
                    for sprite in spriteSet.sprites
                    where sprite.shapeSetName == shapeSet.name && sprite.shapeName == shape.name {
                        let entries = (cfg.renderingConfig.library.rendererSets
                            .first(where: { $0.name == sprite.rendererSetName })?
                            .renderers ?? [])
                            .enumerated().map { i, r in
                                PipelineSummary.RendererEntry(id: i, name: r.name, mode: r.mode)
                            }
                        results.append(PipelineSummary(
                            id: results.count + 1,
                            sourceName: sourceName,
                            polySetName: polySet.name,
                            subdivSetName: shape.subdivisionParamsSetName,
                            shapeSetName: shapeSet.name,
                            shapeName: shape.name,
                            spriteSetName: spriteSet.name,
                            spriteName: sprite.name,
                            rendererSetName: sprite.rendererSetName,
                            renderers: entries
                        ))
                    }
                }
            }
        }
    }
    return results
}

private struct PipelinesSection: View {
    @EnvironmentObject private var controller: AppController
    let geoName: String
    @State private var isCollapsed = true

    var body: some View {
        let pipelines = controller.projectConfig.map { gatherPipelines(geoName: geoName, cfg: $0) } ?? []
        InspectorSection("Pipelines", isCollapsed: $isCollapsed, trailing: {
            Button { deleteAllPipelines(pipelines) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(pipelines.isEmpty ? Color.secondary.opacity(0.25) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(pipelines.isEmpty)
        }, content: {
            if pipelines.isEmpty {
                Text("No pipelines yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pipelines) { p in
                        // Header row: full inspector width, trash right-justified
                        HStack {
                            Text("Pipeline \(p.id)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Button { deletePipeline(p) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 3)

                        // Detail rows: horizontally scrollable
                        ScrollView(.horizontal, showsIndicators: false) {
                            pipelineDetail(p)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }

                        if p.id < pipelines.count { Divider() }
                    }
                }
            }
        })
    }

    private func pipelineDetail(_ p: PipelineSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            phaseHeader(.geometry)
            infoRow("Source",    p.sourceName)
            infoRow("Base name", p.spriteName)

            phaseHeader(.subdivision)
            infoRow("Set", p.subdivSetName.isEmpty ? "None" : p.subdivSetName)

            phaseHeader(.sprites)
            infoRow("Sprite set", p.spriteSetName)
            infoRow("Sprite",     p.spriteName)

            phaseHeader(.rendering)
            infoRow("Renderer set", p.rendererSetName)
            ForEach(p.renderers) { r in
                infoRow("Renderer", "\(r.name)  ·  \(r.mode.displayName)")
            }
        }
    }

    private func phaseHeader(_ tab: AppTab) -> some View {
        HStack(spacing: 5) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 10))
                .frame(width: 12)
            Text(tab.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color.secondary)
        .padding(.leading, 10)
        .padding(.top, 3)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .frame(width: 76, alignment: .trailing)
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 22)
    }

    private func deletePipeline(_ p: PipelineSummary) {
        controller.updateProjectConfig { cfg in
            // Remove sprite (and sprite set if now empty)
            if let si = cfg.spriteConfig.library.spriteSets.firstIndex(where: { $0.name == p.spriteSetName }) {
                cfg.spriteConfig.library.spriteSets[si].sprites.removeAll {
                    $0.name == p.spriteName && $0.shapeSetName == p.shapeSetName
                }
                if cfg.spriteConfig.library.spriteSets[si].sprites.isEmpty {
                    cfg.spriteConfig.library.spriteSets.remove(at: si)
                }
            }
            // Remove renderer set if no remaining sprites reference it
            if !p.rendererSetName.isEmpty {
                let stillUsed = cfg.spriteConfig.library.spriteSets
                    .flatMap { $0.sprites }
                    .contains { $0.rendererSetName == p.rendererSetName }
                if !stillUsed {
                    cfg.renderingConfig.library.rendererSets.removeAll { $0.name == p.rendererSetName }
                }
            }
            // Remove shape (and shape set if now empty)
            if let si = cfg.shapeConfig.library.shapeSets.firstIndex(where: { $0.name == p.shapeSetName }) {
                cfg.shapeConfig.library.shapeSets[si].shapes.removeAll { $0.name == p.shapeName }
                if cfg.shapeConfig.library.shapeSets[si].shapes.isEmpty {
                    cfg.shapeConfig.library.shapeSets.remove(at: si)
                }
            }
            // Remove subdivision params set if no remaining shapes reference it
            if !p.subdivSetName.isEmpty {
                let stillUsed = cfg.shapeConfig.library.shapeSets
                    .flatMap { $0.shapes }
                    .contains { $0.subdivisionParamsSetName == p.subdivSetName }
                if !stillUsed {
                    cfg.subdivisionConfig.paramsSets.removeAll { $0.name == p.subdivSetName }
                }
            }
            // Remove derived polygon set; leave the master geoName def untouched
            if p.polySetName != geoName {
                cfg.polygonConfig.library.polygonSets.removeAll { $0.name == p.polySetName }
            }
        }
    }

    private func deleteAllPipelines(_ pipelines: [PipelineSummary]) {
        pipelines.forEach { deletePipeline($0) }
    }
}

// MARK: - Cycle Setup section

/// Shown only when the geometry file has 2+ layers.
/// Creates shape sets for every layer + one sprite + one renderer + one cycle.
private struct CycleSetupSection: View {
    @EnvironmentObject private var controller: AppController
    let folder:  String
    let geoName: String

    static let noneSubdivName = "(None)"

    @State private var baseName:         String       = ""
    @State private var primaryLayerID:   String       = ""
    @State private var subdivSetName:    String       = CycleSetupSection.noneSubdivName
    @State private var spriteSetName:    String       = ""
    @State private var rendererSetName:  String       = ""
    @State private var rendererMode:     RendererMode = .filledStroked
    @State private var cycleName:        String       = ""
    @State private var holdFrames:       Int          = 4
    @State private var transitionFrames: Int          = 2

    var body: some View {
        let layers = geometryLayers
        guard layers.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(InspectorSection("Cycle Setup") {
            InspectorField("Base name") {
                TextField("", text: $baseName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .onChange(of: baseName) { _, _ in applyRecommendedNames(overwrite: true) }
            }
            .loomHelp("Root name for the generated cycle, sprite, and renderer set.")

            InspectorField("Primary layer") {
                Picker("", selection: $primaryLayerID) {
                    ForEach(layers, id: \.id) { layer in
                        Text(layer.name).tag(layer.id.uuidString)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
            }
            .loomHelp("The layer used as the visible sprite. All other layers become cycle states.")

            InspectorField("Subdivision set") {
                Picker("", selection: $subdivSetName) {
                    ForEach(subdivSetOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
            }
            .loomHelp("Subdivision parameter set applied to every layer's shape. Choose (None) for raw unsubdivided geometry.")

            InspectorField("Sprite set") {
                TextField("", text: $spriteSetName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }

            InspectorField("Renderer set") {
                TextField("", text: $rendererSetName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }

            InspectorField("Mode") {
                Picker("", selection: $rendererMode) {
                    ForEach(RendererMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
            }

            InspectorField("Cycle name") {
                TextField("", text: $cycleName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }

            InspectorField("Hold frames") {
                HStack(spacing: 4) {
                    Stepper("", value: $holdFrames, in: 1...120)
                        .labelsHidden()
                    Text("\(holdFrames)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28)
                }
            }
            .loomHelp("How many frames each geometry layer is held before transitioning.")

            InspectorField("Trans frames") {
                HStack(spacing: 4) {
                    Stepper("", value: $transitionFrames, in: 0...60)
                        .labelsHidden()
                    Text("\(transitionFrames)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28)
                }
            }
            .loomHelp("Cross-fade frames between states. 0 = hard cut.")

            Button("Make Cycle Setup") { makeCycleSetup(layers: layers) }
                .frame(maxWidth: .infinity)
                .font(.system(size: 11))
                .disabled(!canMake)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
        }
        .onAppear {
            if primaryLayerID.isEmpty, let first = layers.first {
                primaryLayerID = first.id.uuidString
            }
            applyRecommendedNames(overwrite: false)
        }
        .onChange(of: geoName) { _, _ in
            primaryLayerID = layers.first?.id.uuidString ?? ""
            applyRecommendedNames(overwrite: true)
        })
    }

    // MARK: - Helpers

    private var stem: String {
        let s = geoName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(chars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func applyRecommendedNames(overwrite: Bool) {
        func set(_ field: inout String, _ value: String) {
            if overwrite || field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                field = value
            }
        }
        let s = stem.isEmpty ? "cycle" : stem
        set(&baseName,        s)
        set(&spriteSetName,   s)
        set(&rendererSetName, "\(s)_renderer")
        set(&cycleName,       "\(s)Cycle")
    }

    private var canMake: Bool {
        !geoName.isEmpty &&
        !primaryLayerID.isEmpty &&
        !baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cycleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        geometryLayers.count >= 2
    }

    private var subdivSetOptions: [String] {
        let existing = controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? []
        var opts = [Self.noneSubdivName]
        for name in existing where !opts.contains(name) { opts.append(name) }
        return opts
    }

    private var geometryLayers: [EditableGeometryLayer] {
        guard folder == "polygonSets",
              let projectURL = controller.projectURL,
              let def = controller.projectConfig?.polygonConfig.library.polygonSets
                  .first(where: { $0.name == geoName }),
              !def.filename.isEmpty,
              def.filename.lowercased().hasSuffix(".json")
        else { return [] }

        let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
        let doc = try? EditableGeometryJSONLoader.load(
            url: projectURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
        )
        return doc?.layers ?? []
    }

    // MARK: - Build action

    private func makeCycleSetup(layers: [EditableGeometryLayer]) {
        guard let def = controller.projectConfig?.polygonConfig.library.polygonSets
                .first(where: { $0.name == geoName })
        else { return }

        let base            = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let spriteSet       = spriteSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rendSet         = rendererSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cycleNameClean  = cycleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryID       = primaryLayerID

        controller.updateProjectConfig { cfg in
            // 1. Polygon set + shape set per layer
            var cycleStates: [SpriteCycleState] = []
            var primaryShapeSetName = ""
            var primaryShapeName    = ""

            for layer in layers {
                let layerStem    = sanitize(layer.name)
                let polySetName  = "\(base)_\(layerStem)"
                let shapeSetName = "\(base)_\(layerStem)_Shapes"
                let shapeName    = "\(base)_\(layerStem)_Shape"

                // Polygon set
                let polyDef = PolygonSetDef(
                    name: polySetName,
                    folder: def.folder.isEmpty ? "polygonSets" : def.folder,
                    filename: def.filename,
                    polygonType: def.polygonType,
                    regularParams: nil,
                    editableLayerID: layer.id,
                    editableLayerName: layer.name
                )
                if let idx = cfg.polygonConfig.library.polygonSets.firstIndex(where: { $0.name == polySetName }) {
                    cfg.polygonConfig.library.polygonSets[idx] = polyDef
                } else {
                    cfg.polygonConfig.library.polygonSets.append(polyDef)
                }

                // Shape set
                let shape = ShapeDef(
                    name: shapeName,
                    sourceType: .polygonSet,
                    polygonSetName: polySetName,
                    subdivisionParamsSetName: subdivSetName == Self.noneSubdivName ? "" : subdivSetName
                )
                if let setIdx = cfg.shapeConfig.library.shapeSets.firstIndex(where: { $0.name == shapeSetName }) {
                    if let shpIdx = cfg.shapeConfig.library.shapeSets[setIdx].shapes
                            .firstIndex(where: { $0.name == shapeName }) {
                        cfg.shapeConfig.library.shapeSets[setIdx].shapes[shpIdx] = shape
                    } else {
                        cfg.shapeConfig.library.shapeSets[setIdx].shapes.append(shape)
                    }
                } else {
                    cfg.shapeConfig.library.shapeSets.append(ShapeSet(name: shapeSetName, shapes: [shape]))
                }

                // Cycle state for this layer
                let state = SpriteCycleState(
                    shapeSetName: shapeSetName,
                    shapeName: shapeName,
                    holdFrames: holdFrames,
                    transitionFrames: transitionFrames
                )
                cycleStates.append(state)

                if layer.id.uuidString == primaryID {
                    primaryShapeSetName = shapeSetName
                    primaryShapeName    = shapeName
                }
            }

            // 2. Renderer set (shared)
            let rendererName = base
            if !cfg.renderingConfig.library.rendererSets.contains(where: { $0.name == rendSet }) {
                let renderer = Renderer(
                    name: rendererName,
                    mode: rendererMode,
                    strokeWidth: 1.0,
                    strokeColor: .black,
                    fillColor: LoomColor(r: 220, g: 220, b: 220)
                )
                cfg.renderingConfig.library.rendererSets.append(
                    RendererSet(name: rendSet, renderers: [renderer])
                )
            }

            // 3. Cycle
            let cycle = SpriteCycle(name: cycleNameClean, loopMode: .loop, states: cycleStates)
            if let cyIdx = cfg.cycles.firstIndex(where: { $0.name == cycleNameClean }) {
                cfg.cycles[cyIdx] = cycle
            } else {
                cfg.cycles.append(cycle)
            }

            // 4. One sprite on the primary layer with the cycle assigned
            let spriteName = base
            let sprite = SpriteDef(
                name: spriteName,
                shapeSetName: primaryShapeSetName.isEmpty ? (cycleStates.first.map { $0.shapeSetName } ?? "") : primaryShapeSetName,
                shapeName: primaryShapeName.isEmpty ? (cycleStates.first.map { $0.shapeName } ?? "") : primaryShapeName,
                rendererSetName: rendSet,
                cycleName: cycleNameClean
            )
            if let setIdx = cfg.spriteConfig.library.spriteSets.firstIndex(where: { $0.name == spriteSet }) {
                if let sprIdx = cfg.spriteConfig.library.spriteSets[setIdx].sprites
                        .firstIndex(where: { $0.name == spriteName }) {
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites[sprIdx] = sprite
                } else {
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites.append(sprite)
                }
            } else {
                cfg.spriteConfig.library.spriteSets.append(SpriteSet(name: spriteSet, sprites: [sprite]))
            }
        }
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(chars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

// MARK: - RendererMode display names (Quick Setup)

private extension RendererMode {
    var displayName: String {
        switch self {
        case .points:        return "Points"
        case .stroked:       return "Stroked"
        case .filled:        return "Filled"
        case .filledStroked: return "Filled+Stroked"
        case .brushed:       return "Brushed"
        case .stenciled:     return "Stenciled"
        case .stamped:       return "Stamped"
        }
    }
}
