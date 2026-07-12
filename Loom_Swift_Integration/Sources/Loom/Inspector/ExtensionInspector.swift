import SwiftUI
import LoomEngine

/// Inspector for a single `ExtensionParams` pass.
/// Embedded in `SubdivisionInspector` when an extension param is selected.
struct ExtensionInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let exIdx:  Int

    @AppStorage("extinsp.generalCollapsed") private var generalCollapsed  = false
    @AppStorage("extinsp.opCollapsed")      private var opCollapsed       = false
    @AppStorage("extinsp.branchCollapsed")  private var branchCollapsed   = false
    @AppStorage("extinsp.extrudeCollapsed") private var extrudeCollapsed  = false
    @AppStorage("extinsp.angleCollapsed")       private var angleCollapsed       = true
    @AppStorage("extinsp.lineLengthCollapsed")  private var lineLengthCollapsed  = true
    @AppStorage("extinsp.distCollapsed")        private var distCollapsed        = true
    @AppStorage("extinsp.directionalCollapsed") private var directionalCollapsed = true
    @AppStorage("extinsp.structurePhaseCollapsed") private var structurePhaseCollapsed = true

    var body: some View {
        generalSection
        operationSection
        if bindEX(\.operationType).wrappedValue == .branch {
            branchSection
            branchAngleDriverSection
            if bindEX(\.branchGeometry).wrappedValue == .line {
                branchLineLengthDriverSection
            }
            structurePhaseDriverSection
        } else {
            extrudeSection
            extrudeDistanceDriverSection
            directionalSelectorSection
            structurePhaseDriverSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindEX(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindEX(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Operation type

    private var operationSection: some View {
        InspectorSection("Operation", isCollapsed: $opCollapsed) {
            InspectorField("Type") {
                Picker("", selection: bindEX(\.operationType)) {
                    ForEach(ExtensionOperationType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .loomHelp("Branch: spawn new geometry from the open curve's anchor points, recursively — either scaled copies of the whole curve (Root Copy) or straight/bowed lines (Line), from just the endpoints or any anchor. Extrude: grow closed polygon edges outward along their normal direction — enable Open Curves below to also bridge an open curve's own edge into a new closed polygon.")
        }
    }

    // MARK: - Branch settings

    private var branchSection: some View {
        InspectorSection("Branch", isCollapsed: $branchCollapsed) {
            InspectorField("Anchors") {
                Picker("", selection: bindEX(\.branchAnchorScope)) {
                    ForEach(BranchAnchorScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Endpoints Only: branches spawn from the curve's two ends (original behavior). Any Anchor: every anchor point along the curve is an eligible branch origin, not just the ends.")

            InspectorField("Geometry") {
                Picker("", selection: bindEX(\.branchGeometry)) {
                    ForEach(BranchGeometry.allCases, id: \.self) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 140)
            }
            .loomHelp("Root Copy: each branch is a scaled/rotated copy of the entire root curve (original behavior). Line: each branch is a single straight or bowed line segment instead — set Count and Depth to 1 for a single line extension from each anchor, or leave them higher for a forking stick/twig tree.")

            InspectorField("Count") {
                let b = bindEXInt(\.branchCount)
                Stepper("\(b.wrappedValue)", value: b, in: 1...8)
                    .font(.system(size: 12))
                    .frame(maxWidth: 80)
            }
            .loomHelp("Number of sub-branches spawned at each endpoint per level. 2 = binary tree (one branch each side at ±angle). Branches are spread symmetrically around the endpoint tangent.")

            InspectorField("Depth") {
                let b = bindEXInt(\.branchDepth)
                Stepper("\(b.wrappedValue)", value: b, in: 1...8)
                    .font(.system(size: 12))
                    .frame(maxWidth: 80)
            }
            .loomHelp("Recursion depth. 1 = direct children only. 2 = children + grandchildren. Depth 5 with count 2 creates up to 62 branches per input polygon.")

            InspectorField("Scale ratio") {
                FloatEntryField(value: bindEX(\.branchScaleRatio), width: 60)
            }
            .loomHelp("Scale factor applied per depth level. 0.6 = each branch is 60% of the previous level's size. Values near 1 produce nearly equal-size branches; values near 0 create rapid diminishment.")

            InspectorField("Angle jitter") {
                FloatEntryField(value: bindEX(\.branchAngleJitter), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Maximum random perturbation added to each branch angle in degrees. 0 = perfectly symmetrical. Uses a deterministic seed per branch for stability across frames.")

            InspectorField("Probability") {
                FloatEntryField(value: bindEX(\.branchProbability), width: 60)
            }
            .loomHelp("Chance (0.0–1.0) that each individual branch actually spawns. 1.0 = all branches spawn. Lower values create sparse or stochastic tree structures.")

            InspectorField("Seed") {
                let b = bindEXInt(\.branchSeed)
                FloatEntryField(value: Binding(
                    get: { Double(b.wrappedValue) },
                    set: { b.wrappedValue = Int($0.rounded()) }
                ), width: 60, fractionDigits: 0)
            }
            .loomHelp("Deterministic seed for the jitter and probability rolls. Change to produce a different branch topology without altering other settings.")

            if bindEX(\.branchGeometry).wrappedValue == .line {
                InspectorField("Curvature min") {
                    FloatEntryField(value: bindEX(\.branchCurvatureAmountMin), width: 60)
                }
                .loomHelp("Bow applied to each line branch, as a fraction of its own length. Min == Max = a fixed bow. Min ≠ Max = randomized per branch. 0/0 (default) = straight.")

                InspectorField("Curvature max") {
                    FloatEntryField(value: bindEX(\.branchCurvatureAmountMax), width: 60)
                }
                .loomHelp("See Curvature min. Negative and positive values bow to opposite sides.")
            }
        }
    }

    @ViewBuilder
    private var branchAngleDriverSection: some View {
        DoubleDriverEditor(
            label: "Branch angle",
            driver: bindEXDriver(\.branchAngle),
            isCollapsed: $angleCollapsed
        )
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var branchLineLengthDriverSection: some View {
        DoubleDriverEditor(
            label: "Line length",
            driver: bindEXDriver(\.branchLineLength),
            isCollapsed: $lineLengthCollapsed
        )
        .padding(.bottom, 2)
    }

    // MARK: - Extrude settings

    private var extrudeSection: some View {
        InspectorSection("Extrude", isCollapsed: $extrudeCollapsed) {
            InspectorField("Target") {
                Picker("", selection: bindEX(\.extrusionTarget)) {
                    ForEach(ExtrusionTarget.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .loomHelp("All Edges: extrude every segment of the polygon. Longest Edge: extrude only the single longest segment. Combine with the Directional Selector below to further restrict candidates by which way they face — e.g. only edges pointing up.")

            InspectorField("Width") {
                FloatEntryField(value: bindEX(\.extrusionWidth), width: 60)
            }
            .loomHelp("Outer edge width relative to the inner edge, scaled around the segment midpoint. 1.0 = parallel (uniform extrusion). < 1 = taper toward a point. > 1 = flare outward.")

            InspectorField("Curvature") {
                FloatEntryField(value: bindEX(\.extrusionCurvature), width: 60)
            }
            .loomHelp("Bow applied to the outer edge as a fraction of its length. Positive values bow outward (in the extrusion direction). 0 = straight outer edge.")

            InspectorField("Generations min") {
                let b = bindEXInt(\.extrusionGenerationsMin)
                Stepper("\(b.wrappedValue)", value: b, in: 1...6)
                    .font(.system(size: 12))
                    .frame(maxWidth: 80)
            }
            .loomHelp("Minimum recursive outer-face extrusion levels, rolled independently per edge. Equal to Generations max = a fixed count on every edge (1 = single room, 2 = room with an extruded outer wall, etc). Different from Generations max = each edge gets its own random tower height.")

            InspectorField("Generations max") {
                let b = bindEXInt(\.extrusionGenerationsMax)
                Stepper("\(b.wrappedValue)", value: b, in: 1...6)
                    .font(.system(size: 12))
                    .frame(maxWidth: 80)
            }
            .loomHelp("See Generations min. Each additional level extrudes the outer face of the previous.")

            InspectorField("Open curves") {
                Toggle("", isOn: bindEX(\.extrudeOpenCurves)).labelsHidden()
            }
            .loomHelp("Off (default): Extrude only acts on closed polygons, unchanged. On: also extrude open-curve edges — the targeted edge (with whatever curvature it has) is duplicated at Distance/Width/Curvature and its endpoints wall-connected to the original's, producing a new closed polygon bridging the two. The source open curve is left untouched, exactly like Extrude never mutates its source closed polygon either.")

            InspectorField("Departure min") {
                FloatEntryField(value: bindEX(\.extrusionDepartureAngleMin), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Minimum RPSR angle (degrees, rolled independently per edge) rotating the extrusion away from the plain perpendicular outward direction. 0/0 (default) = straight outward. Most useful with Open Curves, where \"outward\" has no enclosed interior to be relative to.")

            InspectorField("Departure max") {
                FloatEntryField(value: bindEX(\.extrusionDepartureAngleMax), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("See Departure min. Equal values = a fixed offset on every edge. Different values = randomized per edge.")

            InspectorField("Seed") {
                let b = bindEXInt(\.extrusionSeed)
                FloatEntryField(value: Binding(
                    get: { Double(b.wrappedValue) },
                    set: { b.wrappedValue = Int($0.rounded()) }
                ), width: 60, fractionDigits: 0)
            }
            .loomHelp("Deterministic seed for the per-edge Generations and Departure angle rolls. Change to get a different tower-height/departure arrangement without altering other settings.")
        }
    }

    @ViewBuilder
    private var extrudeDistanceDriverSection: some View {
        DoubleDriverEditor(
            label: "Extrude distance",
            driver: bindEXDriver(\.extrusionDistance),
            isCollapsed: $distCollapsed
        )
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var directionalSelectorSection: some View {
        DirectionalSelectorEditor(
            label: "Directional Selector",
            selector: bindEX(\.directionalSelector),
            isCollapsed: $directionalCollapsed
        )
    }

    @ViewBuilder
    private var structurePhaseDriverSection: some View {
        DoubleDriverEditor(
            label: "Structure phase",
            driver: bindEXDriver(\.structurePhase),
            isCollapsed: $structurePhaseCollapsed
        )
        .loomHelp("Reveals structural complexity gradually instead of popping in fully the moment this pass is enabled. Off (default): Branch builds its full Depth immediately; Extrude builds each edge's full rolled Generations immediately. On: the driver's value is how many levels/generations have appeared so far — e.g. a ramp from 0 to Depth (Branch) or 0 to 6 (Extrude) grows the tree level-by-level or the tower floor-by-floor, with the currently-growing level/floor scaling up from its own anchor point rather than popping in at full size.")
        .padding(.bottom, 2)
    }

    // MARK: - Binding helpers

    private func bindEX<T>(_ kp: WritableKeyPath<ExtensionParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = ExtensionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.extensionPasses[safe: exIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          exIdx  < cfg.subdivisionConfig.paramsSets[setIdx].extensionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].extensionPasses[exIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindEXInt(_ kp: WritableKeyPath<ExtensionParams, Int>) -> Binding<Int> {
        bindEX(kp)
    }

    private func bindEXDriver(_ kp: WritableKeyPath<ExtensionParams, DoubleDriver>) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.extensionPasses[safe: exIdx]?[keyPath: kp] ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          exIdx  < cfg.subdivisionConfig.paramsSets[setIdx].extensionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].extensionPasses[exIdx][keyPath: kp] = v
                }
            }
        )
    }
}
