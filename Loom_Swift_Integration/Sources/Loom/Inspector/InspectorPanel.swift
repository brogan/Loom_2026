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
    private let content: Content
    private let collapseState: Binding<Bool>?

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title        = title
        self.content      = content()
        self.collapseState = nil
    }

    init(_ title: String, isCollapsed: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title        = title
        self.content      = content()
        self.collapseState = isCollapsed
    }

    private var collapsed: Bool { collapseState?.wrappedValue ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let binding = collapseState {
                Button { binding.wrappedValue.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: binding.wrappedValue ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            if !collapsed {
                content
            }
            Divider().padding(.top, collapsed ? 0 : 4)
        }
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
                HStack {
                    Spacer()
                    Button("Edit…") {
                        controller.enterGeometryEditor()
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                }
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
        InspectorSection("Polygon Set") {
            InspectorRow(label: "Type", value: def.polygonType.rawValue)
            if def.regularParams != nil {
                InspectorRow(label: "Source", value: "algorithmic")
            } else {
                InspectorRow(label: "File", value: def.filename.isEmpty ? "—" : def.filename)
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
        }
    }

    @ViewBuilder
    private func pointSetSection(def: PointSetDef) -> some View {
        InspectorSection("Point Set") {
            InspectorRow(label: "Folder", value: def.folder)
            InspectorRow(label: "File",   value: def.filename.isEmpty ? "—" : def.filename)
        }
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
    @State private var editCollapsed = false
    @State private var weldCollapsed = false
    @State private var multiplyCollapsed = false
    @State private var transformCollapsed = false
    @State private var viewCollapsed = false
    @State private var deleteCollapsed = false
    @State private var fileCollapsed = false
    @State private var parametricCollapsed = false
    @State private var scaleAxis = "XY"
    @State private var scaleSliderValue = 0.0
    @State private var rotateSliderValue = 0.0
    @State private var transformPivot = GeometryTransformPivot.commonCentre

    var body: some View {
        let morphLocked = controller.isCurrentGeometryMorphTargetLocked
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection("Geometry Editor") {
                InspectorRow(label: "Mode", value: "closed polygons")
                InspectorRow(label: "Tool", value: controller.geometryEditorTool.rawValue)
                InspectorRow(label: "Anchors", value: "\(controller.selectedGeometryAnchorCount)")
                if morphLocked {
                    InspectorRow(label: "Lock", value: "Morph target — topology locked")
                }
            }

            if let parameters = controller.selectedRegularPolygonParameters {
                InspectorSection("Regular Polygon", isCollapsed: $parametricCollapsed) {
                    regularPolygonParametersSection(parameters)
                }
            }

            InspectorSection("Create", isCollapsed: $createCollapsed) {
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
                    Spacer()
                }
                iconRow {
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
                }
            }
            .disabled(morphLocked)

            InspectorSection("Edit", isCollapsed: $editCollapsed) {
                iconRow {
                    iconButton(help: "Edit points", selected: controller.geometryEditorTool == .points) {
                        PointCircleIcon()
                    } action: {
                        controller.startGeometryEditMode(.points)
                    }
                    iconButton(help: "Edit edges", selected: controller.geometryEditorTool == .edges) {
                        EdgeGeometryIcon()
                    } action: {
                        controller.startGeometryEditMode(.edges)
                    }
                    iconButton(help: "Edit open curves", selected: controller.geometryEditorTool == .openCurves) {
                        OpenCurveGeometryIcon()
                    } action: {
                        controller.startGeometryEditMode(.openCurves)
                    }
                    iconButton(help: "Edit polygons", selected: controller.geometryEditorTool == .polygons) {
                        PolygonGeometryIcon()
                    } action: {
                        controller.startGeometryEditMode(.polygons)
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(help: "Cut selected objects", disabled: !controller.canCutCopySelectedGeometry || morphLocked) {
                        Image(systemName: "scissors").font(.system(size: 15))
                    } action: {
                        controller.cutSelectedGeometry()
                    }
                    iconButton(help: "Copy selected objects", disabled: !controller.canCutCopySelectedGeometry) {
                        CopyGeometryIcon()
                    } action: {
                        controller.copySelectedGeometry()
                    }
                    iconButton(help: "Paste at last click position", disabled: !controller.canPasteGeometry || morphLocked) {
                        PasteGeometryIcon()
                    } action: {
                        controller.pasteGeometry()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(help: "Snap selected anchors to grid, leaving control points unchanged") {
                        AnchorSnapIcon()
                    } action: {
                        controller.snapGeometryEditorSelectionToGrid(anchorOnly: true)
                    }
                    iconButton(help: "Snap selected points to grid, or all active layer points if nothing is selected") {
                        SnapAllPointsIcon()
                    } action: {
                        controller.snapGeometryEditorSelectionToGrid(anchorOnly: false)
                    }
                    iconButton(help: "Reset control points", disabled: !controller.canResetSelectedGeometryControls) {
                        SteeringWheelIcon()
                    } action: {
                        controller.resetSelectedGeometryControls()
                    }
                    Spacer()
                }
                iconRow {
                    iconTextButton("Undo", help: "Undo", disabled: !controller.canUndoGeometryEdit) {
                        controller.undoGeometryEdit()
                    }
                    iconTextButton("Redo", help: "Redo", disabled: !controller.canRedoGeometryEdit) {
                        controller.redoGeometryEdit()
                    }
                    Spacer()
                }
            }

            InspectorSection("Weld", isCollapsed: $weldCollapsed) {
                iconRow {
                    Toggle("", isOn: $controller.geometryEditorAutoWeld)
                        .labelsHidden()
                        .help("Auto weld")
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
                    iconButton(help: "Duplicate", disabled: !controller.canDuplicateSelectedGeometry) {
                        Image(systemName: "plus.square.on.square").font(.system(size: 15))
                    } action: {
                        controller.duplicateSelectedGeometry()
                    }
                    iconButton(
                        help: "Knife: drag a cut line through polygons or open curves. Click again to leave knife mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .knife
                    ) {
                        RazorBladeIcon()
                    } action: {
                        controller.startKnifeGeometryCut()
                    }
                    iconButton(
                        help: "Knife scope: cut through all visible layers",
                        disabled: controller.geometryEditorTool != .knife,
                        selected: controller.geometryEditorTool == .knife && controller.geometryEditorKnifeCutsAllVisibleLayers
                    ) {
                        KnifeLayerStackIcon()
                    } action: {
                        controller.geometryEditorKnifeCutsAllVisibleLayers.toggle()
                    }
                    Spacer()
                }
                iconRow {
                    iconButton(
                        help: "Displacement extrude: select edges, polygons, or open curves, then drag to push a copy sideways and stitch quads back to the originals. Click again to leave extrude mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .displacementExtrude
                    ) {
                        DisplacementExtrudeIcon()
                    } action: {
                        controller.startDisplacementExtrude()
                    }
                    iconButton(
                        help: "Scale extrude: select edges, polygons, or open curves, then drag right/up to grow an outer ring or left/down for an inner ring, stitched to the originals. Click again to leave extrude mode.",
                        disabled: !controller.selectedGeometryEditorLayerCanEditForUI,
                        selected: controller.geometryEditorTool == .scaleExtrude
                    ) {
                        ScaleExtrudeIcon()
                    } action: {
                        controller.startScaleExtrude()
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
                InspectorField("Pivot") {
                    Picker("", selection: $transformPivot) {
                        Text("Local").tag(GeometryTransformPivot.localCentre)
                        Text("Common").tag(GeometryTransformPivot.commonCentre)
                        Text("Canvas").tag(GeometryTransformPivot.absoluteCentre)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                iconRow {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Scale")
                    Slider(
                        value: $scaleSliderValue,
                        in: -100...100,
                        onEditingChanged: handleScaleSliderEditing
                    )
                    .disabled(!controller.canTransformSelectedGeometry)
                    .help("Scale")
                }
                iconRow {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Rotate")
                    Slider(
                        value: $rotateSliderValue,
                        in: -100...100,
                        onEditingChanged: handleRotateSliderEditing
                    )
                    .disabled(!controller.canTransformSelectedGeometry)
                    .help("Rotate")
                }
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
                    iconButton(help: "Centre selected geometry, or the active layer if nothing is selected") {
                        Image(systemName: "scope").font(.system(size: 15))
                    } action: {
                        controller.centreGeometryEditorViewOnSelectionOrLayer()
                    }
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
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }

            InspectorSection("Delete", isCollapsed: $deleteCollapsed) {
                iconRow {
                    iconButton(help: "Delete selected geometry", disabled: !controller.canDeleteSelectedGeometry || morphLocked) {
                        DeleteSelectedGeometryIcon()
                    } action: {
                        controller.deleteSelectedGeometry()
                    }
                    iconButton(help: "Delete all geometry in active layer", disabled: !controller.canDeleteAllLayerGeometry || morphLocked) {
                        DeleteAllLayerGeometryIcon()
                    } action: {
                        controller.deleteAllLayerGeometry()
                    }
                    Spacer()
                }
            }

            InspectorSection("File", isCollapsed: $fileCollapsed) {
                InspectorField("Name") {
                    TextField("", text: $geometryName)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                        .frame(width: 130)
                }
                iconRow {
                    iconButton(help: "Save geometry document", disabled: controller.geometryEditorDocument == nil) {
                        SaveDocumentIcon()
                    } action: {
                        controller.saveGeometryEditorDocument(named: geometryName)
                        geometryName = currentGeometryName
                    }
                    iconButton(help: "Reload geometry document from disk", disabled: controller.selectedGeometryKey == nil) {
                        LoadDocumentIcon()
                    } action: {
                        controller.reloadGeometryEditorDocumentFromDisk()
                    }
                    Spacer()
                }
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
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
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
            .help(help)
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

private struct PointCircleIcon: View {
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.5)
            Circle().fill().frame(width: 4, height: 4)
        }
        .padding(4)
    }
}

private struct PolygonGeometryIcon: View {
    var body: some View {
        Rectangle()
            .stroke(lineWidth: 1.5)
            .padding(5)
    }
}

private struct OpenCurveGeometryIcon: View {
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

private struct EdgeGeometryIcon: View {
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

private struct SnapAllPointsIcon: View {
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

private struct AnchorSnapIcon: View {
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

private struct SteeringWheelIcon: View {
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

private struct CopyGeometryIcon: View {
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

private struct PasteGeometryIcon: View {
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

private struct DeleteSelectedGeometryIcon: View {
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

private struct DeleteAllLayerGeometryIcon: View {
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

private struct SaveDocumentIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let r = proxy.frame(in: .local)
            let w = r.width; let h = r.height
            let midX = r.minX + w * 0.50
            let arrowTop = r.minY + h * 0.12
            let arrowTip = r.minY + h * 0.72
            let headHalf = w * 0.28
            let lineY = r.minY + h * 0.88
            // Shaft
            Path { path in
                path.move(to:    CGPoint(x: midX, y: arrowTop))
                path.addLine(to: CGPoint(x: midX, y: arrowTip))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5))
            // Arrowhead pointing down
            Path { path in
                path.move(to:    CGPoint(x: midX - headHalf, y: arrowTip - h*0.22))
                path.addLine(to: CGPoint(x: midX,            y: arrowTip))
                path.addLine(to: CGPoint(x: midX + headHalf, y: arrowTip - h*0.22))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Base line
            Path { path in
                path.move(to:    CGPoint(x: r.minX + w*0.10, y: lineY))
                path.addLine(to: CGPoint(x: r.minX + w*0.90, y: lineY))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .padding(2)
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

// MARK: - Quick Setup section

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
        InspectorSection("Quick Setup") {
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
            InspectorField("Subdiv set") {
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
            InspectorField("Sprite") {
                TextField("", text: $qsSpriteName)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
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
            HStack(spacing: 6) {
                Circle()
                    .fill(pipelineExists ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(pipelineExists ? "Pipeline ready" : "Pipeline not built")
                    .font(.system(size: 11))
                    .foregroundStyle(pipelineExists ? Color.primary : Color.secondary)
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
            // Layer change: don't reset base name — user may intentionally share set names
            // across layers of the same file.
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
    }

    // MARK: - Layout helper

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
    private var recommendedSubdivSetName: String { "\(baseStem)_Subdivide" }
    private var recommendedQuickSetupSubdivSetName: String {
        if sourceIsCleanParametricRegularPolygon {
            return Self.noSubdivisionName
        }
        return sourceSupportsSubdivision ? recommendedSubdivSetName : Self.noSubdivisionName
    }
    private var recommendedShapeSetName: String { "\(baseStem)_Shapes" }
    private var recommendedShapeName: String { "\(sourceNameStem)_Shape" }
    private var recommendedSpriteSetName: String { "\(baseStem)_Sprites" }
    private var recommendedSpriteName: String { "\(sourceNameStem)_Sprite" }
    private var recommendedRendererSetName: String { "\(baseStem)_Renderers" }
    private var recommendedRendererName: String { "\(sourceNameStem)_Renderer" }
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
