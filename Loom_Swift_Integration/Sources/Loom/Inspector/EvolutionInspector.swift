import SwiftUI
import LoomEngine

/// Inspector for a single `EvolutionParams` pass.
/// Embedded in `SubdivisionInspector` when an evolution param is selected.
struct EvolutionInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let evIdx:  Int

    @AppStorage("evinsp.generalCollapsed")     private var generalCollapsed   = false
    @AppStorage("evinsp.opCollapsed")          private var opCollapsed        = false
    @AppStorage("evinsp.driftCollapsed")       private var driftCollapsed     = false
    @AppStorage("evinsp.convergeCollapsed")    private var convergenceCollapsed = false
    @AppStorage("evinsp.pressureCollapsed")    private var pressureDriverCollapsed = true
    @AppStorage("evinsp.generationsCollapsed") private var generationsCollapsed = false
    @AppStorage("evinsp.extrudeOpCollapsed")   private var extrudeOpCollapsed  = false
    @AppStorage("evinsp.splitOpCollapsed")     private var splitOpCollapsed    = false
    @AppStorage("evinsp.phaseDriverCollapsed") private var phaseDriverCollapsed = true

    var body: some View {
        generalSection
        operationSection
        switch bindEV(\.operationType).wrappedValue {
        case .momentumDrift:
            driftSection
        case .convergencePressure:
            convergenceSection
            convergencePressureDriverSection
        case .generational:
            generationsSection
            generationPhaseDriverSection
            extrudeOperatorSection
            splitOperatorSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindEV(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindEV(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Operation type

    private var operationSection: some View {
        InspectorSection("Operation", isCollapsed: $opCollapsed) {
            InspectorField("Type") {
                Picker("", selection: bindEV(\.operationType)) {
                    ForEach(EvolutionOperationType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
            .loomHelp("Momentum Drift: applies closed-form noise-driven drift to a chosen subdivision parameter. Convergence Pressure: gradually lerps subdivision params toward a target set. Generational: iteratively mutates the actual polygon geometry across generations (extrude/split), an artificial-life system distinct from the other two — see Specs/GeometricLifecycle.md §4.4.")
        }
    }

    // MARK: - Momentum drift

    private var driftSection: some View {
        InspectorSection("Drift", isCollapsed: $driftCollapsed) {
            InspectorField("Target") {
                Picker("", selection: bindEV(\.driftTarget)) {
                    ForEach(DriftTarget.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }
            .loomHelp("Which subdivision parameter the drift displaces. Line Ratio XY affects both line ratio axes equally.")

            InspectorField("Momentum") {
                FloatEntryField(value: bindEV(\.driftMomentum), width: 60)
            }
            .loomHelp("How much past noise influences the current drift. 0 = pure frame-to-frame noise. 0.9 = very smooth, slow-changing drift. Values close to 1.0 produce long sustained sweeps.")

            InspectorField("Strength") {
                FloatEntryField(value: bindEV(\.driftNoiseStrength), width: 60)
            }
            .loomHelp("Peak displacement amplitude added to the target parameter. A value of 0.1 shifts line ratios by up to ±0.1 around their base value.")

            InspectorField("Frequency") {
                FloatEntryField(value: bindEV(\.driftNoiseFrequency), width: 60)
            }
            .loomHelp("Temporal noise rate in cycles per frame. 0.02 = one full noise cycle every 50 frames. Lower values = slower, broader drift; higher values = rapid, jittery changes.")

            InspectorField("Seed") {
                let b = bindEVInt(\.driftSeed)
                FloatEntryField(value: Binding(
                    get: { Double(b.wrappedValue) },
                    set: { b.wrappedValue = Int($0.rounded()) }
                ), width: 60, fractionDigits: 0)
            }
            .loomHelp("Deterministic seed for the drift noise. Change to produce a different drift trajectory without altering the shape of the motion.")
        }
    }

    // MARK: - Convergence pressure

    private var convergenceSection: some View {
        InspectorSection("Convergence", isCollapsed: $convergenceCollapsed) {
            InspectorField("Target set") {
                let names = (controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? [])
                    .filter { !$0.isEmpty }
                Picker("", selection: bindEV(\.convergenceTargetSetName)) {
                    Text("(none)").tag("")
                    ForEach(names, id: \.self) { n in Text(n).tag(n) }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }
            .loomHelp("The transform set whose subdivision params this pass converges toward. The target's line ratios, CP offsets, and inset scale/rotation are lerped.")

            InspectorField("Mode") {
                Picker("", selection: bindEV(\.convergenceMode)) {
                    ForEach(ConvergenceMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Hold: pressure applies directly from the driver. Oscillate: multiplies pressure by a sin wave over the duration (0→1→0). Loop: cycles pressure 0→1→0→1 repeatedly.")

            InspectorField("Duration") {
                FloatEntryField(value: bindEV(\.convergenceDuration), width: 60)
                Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Frame duration of one Oscillate or Loop cycle. Has no effect in Hold mode.")
        }
    }

    @ViewBuilder
    private var convergencePressureDriverSection: some View {
        DoubleDriverEditor(
            label: "Pressure",
            driver: bindEVDriver(\.convergencePressure),
            isCollapsed: $pressureDriverCollapsed
        )
        .padding(.bottom, 2)
    }

    // MARK: - Generational: generations & budget

    private var generationsSection: some View {
        InspectorSection("Generations", isCollapsed: $generationsCollapsed) {
            InspectorField("Count") {
                FloatEntryField(value: intAsDoubleBinding(\.generationCount), width: 50, fractionDigits: 0)
            }
            .loomHelp("How many generations to run. Each generation applies exactly one mutation operator (extrude or split, chosen by weight) to one eligible closed polygon in the set.")

            InspectorField("Seed") {
                FloatEntryField(value: intAsDoubleBinding(\.generationSeed), width: 60, fractionDigits: 0)
            }
            .loomHelp("Deterministic seed. The same seed and parameters always produce the identical generation history — change it for a different evolutionary path.")

            InspectorField("Vertex budget") {
                FloatEntryField(value: intAsDoubleBinding(\.maxVertexBudget), width: 70, fractionDigits: 0)
            }
            .loomHelp("Hard cap on total vertex count across all polygons in the set. Required, not optional — extrusion and splitting both grow vertex count every generation; without a cap, high generation counts risk runaway complexity. A generation that would exceed this budget is rejected and the chain stops there.")
        }
    }

    /// Maps playback time to a position in [0, generationCount]. Disabled by
    /// default — the full generationCount is applied statically every frame,
    /// unchanged from before this existed. Enable to animate the reveal: the
    /// integer part is how many generations are fully applied; the fractional
    /// part tweens the in-progress generation's extrude/split magnitude in from 0.
    @ViewBuilder
    private var generationPhaseDriverSection: some View {
        DoubleDriverEditor(
            label: "Reveal",
            driver: bindEVDriver(\.generationPhase),
            isCollapsed: $phaseDriverCollapsed
        )
        .loomHelp("Animates the generation reveal over playback time. Off (default): the full generation count above is always shown. On: this driver's value is the current position in [0, generationCount] — e.g. a keyframe track from 0 at frame 0 to generationCount at some later frame reveals one generation at a time as it grows, tweening each extrude/split into view rather than popping it in.")
        .padding(.bottom, 2)
    }

    // MARK: - Generational: extrude operator

    private var extrudeOperatorSection: some View {
        InspectorSection("Extrude", isCollapsed: $extrudeOpCollapsed) {
            InspectorField("Weight") {
                FloatEntryField(value: bindEV(\.extrudeWeight), width: 60)
            }
            .loomHelp("Relative selection weight for the extrude operator each generation. Set to 0 to exclude extrusion entirely (split-only evolution).")

            InspectorField("Run length") {
                FloatEntryField(value: intAsDoubleBinding(\.extrudeRunLengthMin), width: 40, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.extrudeRunLengthMax), width: 40, fractionDigits: 0)
            }
            .loomHelp("Range of contiguous edges extruded together as one generation's mutation, resampled each generation. A run of neighboring quads sharing endpoints — same compound-growth model as Extension's edge extrusion.")

            InspectorField("Distance") {
                FloatEntryField(value: bindEV(\.extrudeDistanceMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.extrudeDistanceMax), width: 50)
            }
            .loomHelp("Outward extrusion distance, resampled from this range each generation (RPSR).")
        }
    }

    // MARK: - Generational: split operator

    private var splitOperatorSection: some View {
        InspectorSection("Split", isCollapsed: $splitOpCollapsed) {
            InspectorField("Weight") {
                FloatEntryField(value: bindEV(\.splitWeight), width: 60)
            }
            .loomHelp("Relative selection weight for the split operator each generation. Set to 0 to exclude splitting entirely (extrude-only evolution).")

            InspectorField("Displacement") {
                FloatEntryField(value: bindEV(\.splitDisplacementMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.splitDisplacementMax), width: 50)
            }
            .loomHelp("How far the new anchor point (from splitting a random edge) is displaced outward from the shape's centre, resampled each generation (RPSR). Only the anchor moves — its flanking control points stay put, pulling the boundary into a rounded spike rather than a sharp break.")
        }
    }

    // MARK: - Binding helpers

    private func bindEV<T>(_ kp: WritableKeyPath<EvolutionParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = EvolutionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.evolutionPasses[safe: evIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          evIdx  < cfg.subdivisionConfig.paramsSets[setIdx].evolutionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].evolutionPasses[evIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindEVInt(_ kp: WritableKeyPath<EvolutionParams, Int>) -> Binding<Int> {
        bindEV(kp)
    }

    /// `FloatEntryField` only takes `Binding<Double>`; this adapts an `Int` field
    /// the same way the existing `driftSeed` field below does.
    private func intAsDoubleBinding(_ kp: WritableKeyPath<EvolutionParams, Int>) -> Binding<Double> {
        let b = bindEVInt(kp)
        return Binding(
            get: { Double(b.wrappedValue) },
            set: { b.wrappedValue = Int($0.rounded()) }
        )
    }

    private func bindEVDriver(_ kp: WritableKeyPath<EvolutionParams, DoubleDriver>) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.evolutionPasses[safe: evIdx]?[keyPath: kp] ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          evIdx  < cfg.subdivisionConfig.paramsSets[setIdx].evolutionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].evolutionPasses[evIdx][keyPath: kp] = v
                }
            }
        )
    }
}
