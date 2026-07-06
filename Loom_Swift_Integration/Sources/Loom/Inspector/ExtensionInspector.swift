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
    @AppStorage("extinsp.angleCollapsed")   private var angleCollapsed    = true
    @AppStorage("extinsp.distCollapsed")    private var distCollapsed     = true

    var body: some View {
        generalSection
        operationSection
        if bindEX(\.operationType).wrappedValue == .branch {
            branchSection
            branchAngleDriverSection
        } else {
            extrudeSection
            extrudeDistanceDriverSection
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
            .loomHelp("Branch: spawn scaled copies of the open curve from its endpoints, recursively. Extrude: grow closed polygon edges outward along their normal direction.")
        }
    }

    // MARK: - Branch settings

    private var branchSection: some View {
        InspectorSection("Branch", isCollapsed: $branchCollapsed) {
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
            .loomHelp("All Edges: extrude every segment of the polygon. Longest Edge: extrude only the single longest segment — useful for directional growth.")

            InspectorField("Width") {
                FloatEntryField(value: bindEX(\.extrusionWidth), width: 60)
            }
            .loomHelp("Outer edge width relative to the inner edge, scaled around the segment midpoint. 1.0 = parallel (uniform extrusion). < 1 = taper toward a point. > 1 = flare outward.")

            InspectorField("Curvature") {
                FloatEntryField(value: bindEX(\.extrusionCurvature), width: 60)
            }
            .loomHelp("Bow applied to the outer edge as a fraction of its length. Positive values bow outward (in the extrusion direction). 0 = straight outer edge.")

            InspectorField("Generations") {
                let b = bindEXInt(\.extrusionGenerations)
                Stepper("\(b.wrappedValue)", value: b, in: 1...6)
                    .font(.system(size: 12))
                    .frame(maxWidth: 80)
            }
            .loomHelp("Number of recursive outer-face extrusion levels. 1 = single room. 2 = room with an extruded outer wall. Each additional level extrudes the outer face of the previous.")
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
