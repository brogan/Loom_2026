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
        case .assets:
            placeholderText("Select an asset to preview it.")
        case .geometry:
            if controller.selectedGeometryKey != nil {
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

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content
            Divider().padding(.top, 4)
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
                        // TODO: open Bezier editor window (Phase 4)
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
            quickSetupSection(folder: folder, name: name)
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

    @ViewBuilder
    private func quickSetupSection(folder: String, name: String) -> some View {
        let subSets = controller.projectConfig?.subdivisionConfig.paramsSets ?? []
        if !subSets.isEmpty {
            InspectorSection("Quick Setup") {
                InspectorField("Subdiv set") {
                    Picker("", selection: subdivBinding(folder: folder, name: name)) {
                        Text("None").tag("")
                        ForEach(subSets, id: \.name) { set in
                            Text(set.name).tag(set.name)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 12))
                    .frame(maxWidth: 120)
                }
            }
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

    private func subdivBinding(folder: String, name: String) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: {
                guard let cfg = ctl.projectConfig else { return "" }
                return cfg.shapeConfig.library.shapeSets.flatMap { $0.shapes }.first { shape in
                    switch folder {
                    case "polygonSets", "regularPolygons": return shape.polygonSetName == name
                    case "curveSets":   return shape.openCurveSetName == name
                    case "pointSets":   return shape.pointSetName == name
                    default:            return false
                    }
                }?.subdivisionParamsSetName ?? ""
            },
            set: { newValue in
                ctl.updateProjectConfig { cfg in
                    for ssIdx in cfg.shapeConfig.library.shapeSets.indices {
                        for sIdx in cfg.shapeConfig.library.shapeSets[ssIdx].shapes.indices {
                            let shape = cfg.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx]
                            let matches: Bool
                            switch folder {
                            case "polygonSets", "regularPolygons": matches = shape.polygonSetName == name
                            case "curveSets":   matches = shape.openCurveSetName == name
                            case "pointSets":   matches = shape.pointSetName == name
                            default:            matches = false
                            }
                            if matches {
                                cfg.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].subdivisionParamsSetName = newValue
                            }
                        }
                    }
                }
            }
        )
    }
}
