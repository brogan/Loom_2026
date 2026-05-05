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
    @State private var scaleAxis = "XY"
    @State private var scaleSliderValue = 0.0
    @State private var rotateSliderValue = 0.0
    @State private var transformPivot = GeometryTransformPivot.commonCentre

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection("Geometry Editor") {
                InspectorRow(label: "Mode", value: "closed polygons")
                InspectorRow(label: "Tool", value: controller.geometryEditorTool.rawValue)
                InspectorRow(label: "Anchors", value: "\(controller.selectedGeometryAnchorCount)")
            }

            InspectorSection("Create", isCollapsed: $createCollapsed) {
                iconRow {
                    iconButton(help: "Create points", disabled: true) { PointCircleIcon() }
                    Spacer()
                }
                iconRow {
                    iconButton(help: "Create oval", disabled: true) { OvalGeometryIcon() }
                    iconButton(help: "Create regular polygon", disabled: true) { Image(systemName: "star").font(.system(size: 15)) }
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
                    iconButton(help: "Mesh build", disabled: true) { Image(systemName: "square.grid.3x3").font(.system(size: 15)) }
                    iconButton(help: "Bitmap to polygon", disabled: true) { Image(systemName: "person.crop.rectangle").font(.system(size: 15)) }
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
                    iconTextButton("Undo", help: "Undo", disabled: !controller.canUndoGeometryEdit) {
                        controller.undoGeometryEdit()
                    }
                    iconTextButton("Redo", help: "Redo", disabled: !controller.canRedoGeometryEdit) {
                        controller.redoGeometryEdit()
                    }
                    Spacer()
                }
                iconRow {
                    iconTextButton("Reset Controls", help: "Reset control points", disabled: !controller.canResetSelectedGeometryControls) {
                        controller.resetSelectedGeometryControls()
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
                    iconButton(help: "Unweld selected geometry", disabled: !controller.canUnweldSelectedGeometry) {
                        Image(systemName: "link.slash").font(.system(size: 15))
                    } action: {
                        controller.unweldSelectedGeometry()
                    }
                    Slider(value: $controller.geometryEditorWeldTolerance, in: 0...1)
                        .frame(width: 58)
                        .help("Weld tolerance: left is stricter, right accepts looser edge matches")
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
                    iconButton(help: "Knife", disabled: true) { Image(systemName: "scissors").font(.system(size: 15)) }
                    iconButton(help: "Intersect", disabled: true) { Image(systemName: "circle.grid.cross").font(.system(size: 15)) }
                    Spacer()
                }
            }

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
                    iconButton(help: "Zoom in", disabled: true) { Image(systemName: "plus.magnifyingglass").font(.system(size: 15)) }
                    iconButton(help: "Zoom out", disabled: true) { Image(systemName: "minus.magnifyingglass").font(.system(size: 15)) }
                    iconButton(help: "Centre selected", disabled: true) { Image(systemName: "scope").font(.system(size: 15)) }
                    iconButton(help: "Toggle grid display", disabled: true) { Image(systemName: "grid").font(.system(size: 15)) }
                    iconButton(help: "Toggle control point display", disabled: true) { PointCircleIcon() }
                    Spacer()
                }
            }

            InspectorSection("Delete", isCollapsed: $deleteCollapsed) {
                inspectorButton("Only Selected Geometry", disabled: !controller.canDeleteSelectedGeometry) {
                    controller.deleteSelectedGeometry()
                }
                inspectorButton("All Geometry", destructive: true)
            }

            InspectorSection("File", isCollapsed: $fileCollapsed) {
                InspectorField("Name") {
                    TextField("", text: $geometryName)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                        .frame(width: 130)
                }
                inspectorButton("Save", disabled: controller.geometryEditorDocument == nil) {
                    controller.saveGeometryEditorDocument(named: geometryName)
                    geometryName = currentGeometryName
                }
                inspectorButton("Load", disabled: controller.selectedGeometryKey == nil) {
                    controller.reloadGeometryEditorDocumentFromDisk()
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
            applyRecommendedNames(overwrite: true)
        }
        .onChange(of: qsLayerTargetID) { _, _ in
            applyRecommendedNames(overwrite: true)
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
                mode: qsRendererMode,
                strokeWidth: 1.0,
                strokeColor: .black,
                fillColor: LoomColor(r: 220, g: 220, b: 220)
            )
            if !cfg.renderingConfig.library.rendererSets[rendererSetIndex].renderers
                .contains(where: { $0.name == rendererName }) {
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

    private var recommendedSubdivSetName: String { "\(sourceNameStem)_Subdivide" }
    private var recommendedQuickSetupSubdivSetName: String {
        sourceSupportsSubdivision ? recommendedSubdivSetName : Self.noSubdivisionName
    }
    private var recommendedShapeSetName: String { "\(sourceNameStem)_Shapes" }
    private var recommendedShapeName: String { "\(sourceNameStem)_Shape" }
    private var recommendedSpriteSetName: String { "\(sourceNameStem)_Sprites" }
    private var recommendedSpriteName: String { "\(sourceNameStem)_Sprite" }
    private var recommendedRendererSetName: String { "\(sourceNameStem)_Renderers" }
    private var recommendedRendererName: String { "\(sourceNameStem)_Renderer" }

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
