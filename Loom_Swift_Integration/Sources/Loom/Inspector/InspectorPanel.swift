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

// MARK: - Quick Setup section

private struct QuickSetupSection: View {
    @EnvironmentObject private var controller: AppController
    let folder:  String
    let geoName: String

    @State private var qsSubdivSetName:   String      = ""
    @State private var qsSpriteSetName:   String      = ""
    @State private var qsRendererSetName: String      = ""
    @State private var qsRendererMode:    RendererMode = .filled

    @State private var showNewSpriteSetAlert   = false
    @State private var showNewRendererSetAlert = false
    @State private var newSpriteSetName:   String = ""
    @State private var newRendererSetName: String = ""

    var body: some View {
        let cfg          = controller.projectConfig
        let subdivSets   = cfg?.subdivisionConfig.paramsSets ?? []
        let spriteSets   = cfg?.spriteConfig.library.spriteSets ?? []
        let rendererSets = cfg?.renderingConfig.library.rendererSets ?? []

        InspectorSection("Quick Setup") {
            // ── Subdivision ──────────────────────────────
            InspectorField("Subdiv set") {
                Picker("", selection: $qsSubdivSetName) {
                    Text("None").tag("")
                    ForEach(subdivSets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                Button("Make") { makeSubdivSet() }
                    .font(.system(size: 11))
                    .disabled(geoName.isEmpty)
            }

            // ── Sprites ───────────────────────────────────
            InspectorField("Sprite set") {
                Picker("", selection: $qsSpriteSetName) {
                    Text("None").tag("")
                    ForEach(spriteSets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                Button("+ Set") {
                    newSpriteSetName = ""
                    showNewSpriteSetAlert = true
                }
                .font(.system(size: 11))
            }
            actionButton("Make Sprite") { makeSprite() }
                .disabled(qsSpriteSetName.isEmpty)

            // ── Rendering ─────────────────────────────────
            InspectorField("Renderer set") {
                Picker("", selection: $qsRendererSetName) {
                    Text("None").tag("")
                    ForEach(rendererSets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                Button("+ Set") {
                    newRendererSetName = ""
                    showNewRendererSetAlert = true
                }
                .font(.system(size: 11))
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
            actionButton("Make Renderer") { makeRenderer() }
                .disabled(qsRendererSetName.isEmpty)
        }
        .onChange(of: geoName) { _, _ in
            qsSubdivSetName = ""; qsSpriteSetName = ""; qsRendererSetName = ""
        }
        .alert("New Sprite Set", isPresented: $showNewSpriteSetAlert) {
            TextField("Name", text: $newSpriteSetName)
            Button("Create") { addSpriteSet() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Renderer Set", isPresented: $showNewRendererSetAlert) {
            TextField("Name", text: $newRendererSetName)
            Button("Create") { addRendererSet() }
            Button("Cancel", role: .cancel) {}
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

    private func makeSubdivSet() {
        let setName = "\(geoName)_Subdivide"
        guard controller.projectConfig?.subdivisionConfig.paramsSets
                .contains(where: { $0.name == setName }) == false
        else { return }
        let param = SubdivisionParams(name: "A", subdivisionType: .quad)
        let ps    = SubdivisionParamsSet(name: setName, params: [param])
        controller.updateProjectConfig { cfg in
            cfg.subdivisionConfig.paramsSets.append(ps)
        }
        qsSubdivSetName = setName
    }

    private func addSpriteSet() {
        let name = newSpriteSetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              controller.projectConfig?.spriteConfig.library.spriteSets
                .contains(where: { $0.name == name }) == false
        else { return }
        controller.updateProjectConfig { cfg in
            cfg.spriteConfig.library.spriteSets.append(SpriteSet(name: name))
        }
        qsSpriteSetName = name
    }

    private func makeSprite() {
        guard !qsSpriteSetName.isEmpty,
              let setIdx = controller.projectConfig?.spriteConfig.library.spriteSets
                .firstIndex(where: { $0.name == qsSpriteSetName })
        else { return }
        let count = (controller.projectConfig?.spriteConfig.library
            .spriteSets[setIdx].sprites.count ?? 0) + 1
        let spriteName = "\(qsSpriteSetName)_\(String(format: "%03d", count))"
        var sprite = SpriteDef()
        sprite.name            = spriteName
        sprite.rendererSetName = qsRendererSetName
        controller.updateProjectConfig { cfg in
            cfg.spriteConfig.library.spriteSets[setIdx].sprites.append(sprite)
        }
    }

    private func addRendererSet() {
        let name = newRendererSetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              controller.projectConfig?.renderingConfig.library.rendererSets
                .contains(where: { $0.name == name }) == false
        else { return }
        controller.updateProjectConfig { cfg in
            cfg.renderingConfig.library.rendererSets.append(RendererSet(name: name))
        }
        qsRendererSetName = name
    }

    private func makeRenderer() {
        guard !qsRendererSetName.isEmpty,
              let setIdx = controller.projectConfig?.renderingConfig.library.rendererSets
                .firstIndex(where: { $0.name == qsRendererSetName })
        else { return }
        let rendererName = "\(geoName)_renderer"
        guard controller.projectConfig?.renderingConfig.library
                .rendererSets[setIdx].renderers
                .contains(where: { $0.name == rendererName }) == false
        else { return }
        var renderer = Renderer()
        renderer.name = rendererName
        renderer.mode = qsRendererMode
        controller.updateProjectConfig { cfg in
            cfg.renderingConfig.library.rendererSets[setIdx].renderers.append(renderer)
        }
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
