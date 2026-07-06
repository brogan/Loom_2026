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

    var body: some View {
        generalSection
        operationSection
        if bindEV(\.operationType).wrappedValue == .momentumDrift {
            driftSection
        } else {
            convergenceSection
            convergencePressureDriverSection
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
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .loomHelp("Momentum Drift: applies closed-form noise-driven drift to a chosen subdivision parameter. Convergence Pressure: gradually lerps subdivision params toward a target set.")
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
