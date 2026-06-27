import SwiftUI
import LoomEngine
import Combine

// MARK: - Main editor sheet

struct SpriteCycleEditorView: View {

    @EnvironmentObject private var controller: AppController
    @State private var selectedStateIndex: Int? = nil
    @State private var expandedStateIndices: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let idx = controller.selectedCycleIndex,
               let cycles = controller.projectConfig?.cycles,
               cycles.indices.contains(idx) {
                let cycle = cycles[idx]
                HStack(spacing: 0) {
                    // Left: cycle controls + state list
                    VStack(spacing: 0) {
                        cycleMetaSection(cycle: cycle, idx: idx)
                        Divider()
                        ScrollView {
                            stateListSection(cycle: cycle, cycleIdx: idx)
                        }
                    }
                    .frame(width: 360)

                    Divider()

                    // Right: preview with onion skinning
                    CyclePreviewPanel(cycle: cycle, selectedStateIndex: $selectedStateIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyCycleMessage
            }
        }
        .frame(width: 680, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Cycle Editor")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Done") {
                controller.showingCycleEditor = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Cycle metadata

    private func cycleMetaSection(cycle: SpriteCycle, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Name")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextField("", text: bindName(idx))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 160)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Text("Loop")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: bindLoopMode(idx)) {
                    ForEach(SpriteCycleLoopMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Text("\(cycle.totalCycleFrames) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: State list

    private func stateListSection(cycle: SpriteCycle, cycleIdx: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("States")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                Spacer()
                Button {
                    addState(toCycle: cycleIdx)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Add state")

                Button {
                    if let s = selectedStateIndex {
                        removeState(at: s, fromCycle: cycleIdx)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(selectedStateIndex == nil)
                .help("Remove selected state")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if cycle.states.isEmpty {
                Text("No states. Press + to add.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(cycle.states.indices, id: \.self) { si in
                    stateRow(cycle: cycle, cycleIdx: cycleIdx, stateIdx: si)
                    Divider()
                }
            }
        }
    }

    // MARK: State row

    private func stateRow(cycle: SpriteCycle, cycleIdx: Int, stateIdx: Int) -> some View {
        let state = cycle.states[stateIdx]
        let isSelected = selectedStateIndex == stateIdx
        let isExpanded = expandedStateIndices.contains(stateIdx)

        return VStack(alignment: .leading, spacing: 0) {
            // Summary row
            HStack(spacing: 8) {
                Text("\(stateIdx + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.shapeName.isEmpty ? "—" : state.shapeName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(state.shapeSetName.isEmpty ? "no set" : state.shapeSetName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text("hold \(state.holdFrames)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if state.transitionFrames > 0 {
                    Text("→ \(state.transitionFrames)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    if isExpanded {
                        expandedStateIndices.remove(stateIdx)
                    } else {
                        expandedStateIndices.insert(stateIdx)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selectedStateIndex = stateIdx }

            // Expanded detail
            if isExpanded {
                stateDetail(cycleIdx: cycleIdx, stateIdx: stateIdx)
                    .padding(.bottom, 6)
                    .background(Color.primary.opacity(0.03))
            }
        }
    }

    // MARK: State detail

    private func stateDetail(cycleIdx: Int, stateIdx: Int) -> some View {
        let allShapeSets = controller.projectConfig?.shapeConfig.library.shapeSets ?? []
        let shapeSetName = controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.shapeSetName ?? ""
        let shapesInSet  = allShapeSets.first(where: { $0.name == shapeSetName })?.shapes.map { $0.name } ?? []
        let allRendererSets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []

        return VStack(alignment: .leading, spacing: 4) {
            // Shape set
            stateDetailRow("Shape Set") {
                Picker("", selection: bindStateStr(cycleIdx, stateIdx, \.shapeSetName)) {
                    Text("—").tag("")
                    ForEach(allShapeSets, id: \.name) { set in
                        Text(set.name).tag(set.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            // Shape name
            stateDetailRow("Shape") {
                if shapesInSet.isEmpty {
                    TextField("", text: bindStateStr(cycleIdx, stateIdx, \.shapeName))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 180)
                } else {
                    Picker("", selection: bindStateStr(cycleIdx, stateIdx, \.shapeName)) {
                        Text("—").tag("")
                        ForEach(shapesInSet, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }

            // Renderer override
            stateDetailRow("Renderer") {
                Picker("", selection: bindStateOptStr(cycleIdx, stateIdx, \.rendererSetName)) {
                    Text("Inherit").tag(String?.none)
                    ForEach(allRendererSets, id: \.name) { set in
                        Text(set.name).tag(String?.some(set.name))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            Divider().padding(.horizontal, 12)

            // Hold frames
            stateDetailRow("Hold frames") {
                IntStepperField(value: bindStateInt(cycleIdx, stateIdx, \.holdFrames), min: 1, max: 999)
            }

            // Transition frames
            stateDetailRow("Trans frames") {
                IntStepperField(value: bindStateInt(cycleIdx, stateIdx, \.transitionFrames), min: 0, max: 999)
            }

            // Easing (only shown when transitionFrames > 0)
            let hasTrans = (controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.transitionFrames ?? 0) > 0
            if hasTrans {
                stateDetailRow("Easing") {
                    Picker("", selection: bindStateEasing(cycleIdx, stateIdx)) {
                        ForEach(EasingType.allCases, id: \.self) { e in
                            Text(e.rawValue.capitalized.replacingOccurrences(of: "_", with: " "))
                                .tag(e)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                stateDetailRow("Style tween") {
                    Toggle("", isOn: bindStateBool(cycleIdx, stateIdx, \.styleTween))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
            }
        }
        .padding(.top, 4)
    }

    private func stateDetailRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
                .padding(.leading, 28)
            content()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: Empty state

    private var emptyCycleMessage: some View {
        VStack(spacing: 8) {
            Text("No cycle selected.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func addState(toCycle cycleIdx: Int) {
        guard let cfg = controller.projectConfig,
              cfg.cycles.indices.contains(cycleIdx)
        else { return }
        let firstShapeSet = cfg.shapeConfig.library.shapeSets.first
        let newState = SpriteCycleState(
            shapeSetName: firstShapeSet?.name ?? "",
            shapeName: firstShapeSet?.shapes.first?.name ?? ""
        )
        controller.updateProjectConfig { cfg in
            cfg.cycles[cycleIdx].states.append(newState)
        }
        let newIdx = (controller.projectConfig?.cycles[cycleIdx].states.count ?? 1) - 1
        selectedStateIndex = newIdx
        expandedStateIndices.insert(newIdx)
    }

    private func removeState(at stateIdx: Int, fromCycle cycleIdx: Int) {
        guard let cfg = controller.projectConfig,
              cfg.cycles.indices.contains(cycleIdx),
              cfg.cycles[cycleIdx].states.indices.contains(stateIdx)
        else { return }
        controller.updateProjectConfig { cfg in
            cfg.cycles[cycleIdx].states.remove(at: stateIdx)
        }
        expandedStateIndices.remove(stateIdx)
        let remaining = controller.projectConfig?.cycles[safe: cycleIdx]?.states.count ?? 0
        selectedStateIndex = remaining == 0 ? nil : min(stateIdx, remaining - 1)
    }

    // MARK: Bindings

    private func bindName(_ cycleIdx: Int) -> Binding<String> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.name ?? "" },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx) else { return }
                cfg.cycles[cycleIdx].name = v
            }}
        )
    }

    private func bindLoopMode(_ cycleIdx: Int) -> Binding<SpriteCycleLoopMode> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.loopMode ?? .loop },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx) else { return }
                cfg.cycles[cycleIdx].loopMode = v
            }}
        )
    }

    private func bindStateStr(_ cycleIdx: Int, _ stateIdx: Int,
                               _ kp: WritableKeyPath<SpriteCycleState, String>) -> Binding<String> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? "" },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateOptStr(_ cycleIdx: Int, _ stateIdx: Int,
                                  _ kp: WritableKeyPath<SpriteCycleState, String?>) -> Binding<String?> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? nil },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateInt(_ cycleIdx: Int, _ stateIdx: Int,
                               _ kp: WritableKeyPath<SpriteCycleState, Int>) -> Binding<Int> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? 1 },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateBool(_ cycleIdx: Int, _ stateIdx: Int,
                                _ kp: WritableKeyPath<SpriteCycleState, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? false },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateEasing(_ cycleIdx: Int, _ stateIdx: Int) -> Binding<EasingType> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.easing ?? .easeInOutCubic },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx].easing = v
            }}
        )
    }
}

// MARK: - Cycle Preview Panel

private struct CyclePreviewPanel: View {
    @EnvironmentObject private var controller: AppController
    let cycle: SpriteCycle
    @Binding var selectedStateIndex: Int?

    @State private var allPolygons: [Int: [Polygon2D]] = [:]
    @State private var isPlaying = false
    @State private var playFrame = 0

    private let previewFPS = 12.0

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                legend
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Canvas
            Canvas { ctx, size in
                drawBackground(ctx: ctx, size: size)
                if allPolygons.isEmpty {
                    // empty — geometry loads asynchronously
                } else {
                    drawShapes(ctx: ctx, size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.07, green: 0.075, blue: 0.10))
            .overlay(
                Group {
                    if cycle.states.isEmpty {
                        Text("Add states to preview")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if allPolygons.isEmpty {
                        Text("No geometry")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            )

            Divider()

            // Playback controls
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Frame \(playFrame + 1) / \(max(1, cycle.totalCycleFrames))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let si = currentStateIndex {
                        Text("State \(si + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: stepBack) {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Previous frame (stops playback)")

                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15))
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Pause" : "Play cycle")

                    Button(action: stepForward) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Next frame (stops playback)")

                    Spacer()

                    Button(action: rewind) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to frame 1")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadAllPolygons()
            syncFrameToSelection()
        }
        .onChange(of: cycle) { _, _ in loadAllPolygons() }
        .onChange(of: selectedStateIndex) { _, _ in
            guard !isPlaying else { return }
            syncFrameToSelection()
        }
        .onReceive(
            Timer.publish(every: 1.0 / previewFPS, on: .main, in: .common).autoconnect()
        ) { _ in
            guard isPlaying else { return }
            let total = max(1, cycle.totalCycleFrames)
            playFrame = (playFrame + 1) % total
            // Keep state list selection in sync while playing
            if let si = currentStateIndex, selectedStateIndex != si {
                selectedStateIndex = si
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("prev")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 0.36, green: 0.82, blue: 0.50))
                .frame(width: 5, height: 5)
            Text("cur")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("next")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Drawing

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.07, green: 0.075, blue: 0.10)))
        // Subtle crosshair at origin
        let cx = size.width / 2, cy = size.height / 2
        var cross = Path()
        cross.move(to: CGPoint(x: cx - 10, y: cy)); cross.addLine(to: CGPoint(x: cx + 10, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - 10)); cross.addLine(to: CGPoint(x: cx, y: cy + 10))
        ctx.stroke(cross, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
    }

    private func drawShapes(ctx: GraphicsContext, size: CGSize) {
        guard !cycle.states.isEmpty else { return }
        let count = cycle.states.count
        let currentIdx = currentStateIndex ?? 0

        // Onion skin: previous state (blue)
        if count > 1 {
            let prevIdx = (currentIdx - 1 + count) % count
            if let polys = allPolygons[prevIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.28),
                     lineWidth: 1.0)
            }
        }

        // Onion skin: next state (orange)
        if count > 2 {
            let nextIdx = (currentIdx + 1) % count
            if let polys = allPolygons[nextIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.28),
                     lineWidth: 1.0)
            }
        } else if count == 2 {
            // With only 2 states, prev and next are the same — skip the orange ghost
            // to avoid redundancy; the blue ghost already shows the other state.
        }

        // Current state(s) — renderLayers handles cross-fade transitions
        for layer in cycle.renderLayers(atFrame: playFrame) {
            if let polys = allPolygons[layer.stateIndex] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.36, green: 0.82, blue: 0.50).opacity(layer.alpha * 0.92),
                     lineWidth: 1.3)
            }
        }
    }

    private func draw(_ polygons: [Polygon2D], in ctx: GraphicsContext, size: CGSize,
                      color: Color, lineWidth: CGFloat) {
        let scale = min(size.width, size.height) * 0.80
        let cx = size.width / 2
        let cy = size.height / 2

        for polygon in polygons where polygon.visible {
            guard !polygon.points.isEmpty else { continue }
            let pts = polygon.points.map { p in
                CGPoint(x: cx + p.x * scale, y: cy - p.y * scale)  // Y-up
            }
            ctx.stroke(buildPath(pts, type: polygon.type), with: .color(color), lineWidth: lineWidth)
        }
    }

    private func buildPath(_ pts: [CGPoint], type: PolygonType) -> Path {
        guard !pts.isEmpty else { return Path() }
        var p = Path()
        switch type {
        case .spline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
            p.closeSubpath()
        case .openSpline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
        case .point:
            for pt in pts {
                p.addEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
            }
        case .oval:
            if pts.count >= 2 {
                let ox = pts[0].x, oy = pts[0].y
                let rx = abs(pts[1].x - ox), ry = abs(pts[1].y - oy)
                p.addEllipse(in: CGRect(x: ox - rx, y: oy - ry, width: rx * 2, height: ry * 2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    // MARK: State tracking

    private var currentStateIndex: Int? {
        cycle.renderLayers(atFrame: playFrame).first?.stateIndex
    }

    private func firstFrame(ofState stateIdx: Int) -> Int {
        var f = 0
        for i in 0..<stateIdx where i < cycle.states.count {
            f += max(1, cycle.states[i].holdFrames) + max(0, cycle.states[i].transitionFrames)
        }
        return f
    }

    private func syncFrameToSelection() {
        if let si = selectedStateIndex {
            playFrame = firstFrame(ofState: si)
        }
    }

    // MARK: Playback controls

    private func togglePlay() { isPlaying.toggle() }

    private func stepBack() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame - 1 + total) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func stepForward() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame + 1) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func rewind() {
        isPlaying = false
        playFrame = 0
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    // MARK: Geometry loading

    private func loadAllPolygons() {
        guard let cfg = controller.projectConfig,
              let projectURL = controller.projectURL
        else { return }
        var result: [Int: [Polygon2D]] = [:]
        for (i, state) in cycle.states.enumerated() {
            let polys = loadPolygons(for: state, config: cfg, projectURL: projectURL)
            if !polys.isEmpty { result[i] = polys }
        }
        allPolygons = result
    }

    private func loadPolygons(for state: SpriteCycleState,
                              config: ProjectConfig,
                              projectURL: URL) -> [Polygon2D] {
        guard !state.shapeSetName.isEmpty else { return [] }
        guard let shapeDef = config.shapeConfig.library.shapeSets
            .first(where: { $0.name == state.shapeSetName })?
            .shapes.first(where: { $0.name == state.shapeName })
        else { return [] }

        switch shapeDef.sourceType {

        case .regularPolygon:
            let sides = shapeDef.regularPolygonSides
            guard sides >= 3 else { return [] }
            let angInc = 2.0 * .pi / Double(sides)
            var pts = [Vector2D]()
            for i in 0..<sides {
                let angle = Double(i) * angInc - .pi / 2
                pts.append(Vector2D(x: 0.5 * cos(angle), y: 0.5 * sin(angle)))
            }
            return [Polygon2D(points: pts, type: .line)]

        case .polygonSet:
            guard !shapeDef.polygonSetName.isEmpty,
                  let polyDef = config.polygonConfig.library.polygonSets
                      .first(where: { $0.name == shapeDef.polygonSetName })
            else { return [] }

            if let rp = polyDef.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }

            let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                ? "polygonSets" : polyDef.folder
            let url = projectURL
                .appendingPathComponent(folder)
                .appendingPathComponent(polyDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }

            if polyDef.filename.lowercased().hasSuffix(".json") {
                return (try? EditableGeometryJSONLoader.load(url: url).runtimePolygons(
                    targetLayerID: polyDef.editableLayerID,
                    targetLayerName: polyDef.editableLayerName
                )) ?? []
            }
            return (try? XMLPolygonLoader.load(url: url)) ?? []

        default:
            return []
        }
    }
}

// MARK: - IntStepperField

private struct IntStepperField: View {
    @Binding var value: Int
    let min: Int
    let max: Int

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $value, formatter: {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.minimum = NSNumber(value: min)
                f.maximum = NSNumber(value: max)
                return f
            }())
            .textFieldStyle(.squareBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 48)
            Stepper("", value: $value, in: min...max)
                .labelsHidden()
                .scaleEffect(0.85)
        }
    }
}
