import SwiftUI
import LoomEngine

/// Inspector for a single `CurveRefinementParams` pass.
/// Embedded in `SubdivisionInspector` when a curve refinement param is selected.
struct CurveRefinementInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let crIdx:  Int

    @AppStorage("crinsp.generalCollapsed")      private var generalCollapsed     = false
    @AppStorage("crinsp.insertionCollapsed")    private var insertionCollapsed   = false
    @AppStorage("crinsp.displacedCollapsed")    private var displaceCollapsed    = false
    @AppStorage("crinsp.cpCollapsed")           private var cpCollapsed          = false
    @AppStorage("crinsp.pressureCollapsed")     private var pressureCollapsed    = true
    @AppStorage("crinsp.dispDriverCollapsed")   private var dispDriverCollapsed  = true
    @AppStorage("crinsp.cpDriverCollapsed")     private var cpDriverCollapsed    = true

    var body: some View {
        generalSection
        insertionSection
        displacementSection
        cpSection
        pressureSection
        driversSection
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindCR(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindCR(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Insertion

    private var insertionSection: some View {
        InspectorSection("Insertion", isCollapsed: $insertionCollapsed) {
            InspectorField("Count") {
                let b = bindCR(\.insertionCount)
                FloatEntryField(
                    value: Binding(
                        get: { Double(b.wrappedValue) },
                        set: { b.wrappedValue = max(1, Int($0.rounded())) }
                    ),
                    width: 60, fractionDigits: 0
                )
            }
            .loomHelp("Number of new anchor points inserted into each Bézier segment.")
            InspectorField("Distribution") {
                Picker("", selection: bindCR(\.distributionMode)) {
                    ForEach(CurveDistributionMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Linear: evenly spaced. Exponential: denser at start, thinning out toward end. Random: deterministic random positions.")
            if bindCR(\.distributionMode).wrappedValue == .exponential {
                InspectorField("Exponent") {
                    FloatEntryField(value: bindCR(\.distributionExponent), width: 60)
                }
                .loomHelp("Power applied to the linear positions. Values > 1 cluster toward the start; values < 1 cluster toward the end.")
                InspectorField("Reverse") {
                    Toggle("", isOn: bindCR(\.distributionReverse)).labelsHidden()
                }
                .loomHelp("Flip the exponential distribution so density is at the end instead of the start.")
            }
            InspectorField("Seed") {
                let b = bindCR(\.distributionSeed)
                FloatEntryField(
                    value: Binding(
                        get: { Double(b.wrappedValue) },
                        set: { b.wrappedValue = Int($0.rounded()) }
                    ),
                    width: 60, fractionDigits: 0
                )
            }
            .loomHelp("Deterministic seed for random distribution. Change to rearrange insertion positions without changing other settings.")
        }
    }

    // MARK: - Displacement

    private var displacementSection: some View {
        InspectorSection("Displacement", isCollapsed: $displaceCollapsed) {
            InspectorField("Amount") {
                FloatEntryField(value: bindCR(\.displacement), width: 60)
            }
            .loomHelp("Perpendicular displacement amplitude applied to inserted anchor points. Positive values push outward (left of the curve direction); negative values push inward.")
            InspectorField("Mode") {
                Picker("", selection: bindCR(\.displacementMode)) {
                    Text("Jitter").tag(CurveDisplacementMode.jitter)
                    Text("Lazy").tag(CurveDisplacementMode.lazy)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 130)
            }
            .loomHelp("Jitter: a new random displacement each frame. Lazy: smooth tweening between periodic targets — produces slow organic drift like the subdivision centre jitter.")
            if bindCR(\.displacementMode).wrappedValue == .lazy {
                InspectorField("Period") {
                    let b = bindCR(\.lazyPeriod)
                    FloatEntryField(
                        value: Binding(
                            get: { Double(b.wrappedValue) },
                            set: { b.wrappedValue = max(1, Int($0.rounded())) }
                        ),
                        width: 60, fractionDigits: 0
                    )
                }
                .loomHelp("Frames between new target displacement samples. Set to your project FPS for one new target per second.")
            }
            InspectorField("Seed") {
                let b = bindCR(\.lazySeed)
                FloatEntryField(
                    value: Binding(
                        get: { Double(b.wrappedValue) },
                        set: { b.wrappedValue = Int($0.rounded()) }
                    ),
                    width: 60, fractionDigits: 0
                )
            }
            .loomHelp("Seed for displacement trajectories. Each inserted point uses this seed XOR its index, giving every point a unique but deterministic path.")
        }
    }

    // MARK: - Control points

    private var cpSection: some View {
        InspectorSection("Control Points", isCollapsed: $cpCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindCR(\.cpMode)) {
                    ForEach(CurveRefinementCPMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Smooth: Catmull-Rom tangents through all anchors — C1 continuous curves. Straight: degenerate Bézier producing straight segments between anchors. Bowed: uniform perpendicular bow applied to each segment via CP Normal Offset.")
            if bindCR(\.cpMode).wrappedValue == .bowed {
                InspectorField("CP Normal") {
                    FloatEntryField(value: bindCR(\.cpNormalOffset), width: 60)
                }
                .loomHelp("Perpendicular bow magnitude as a fraction of each segment length. Positive bows left relative to the curve direction; negative bows right.")
            }
        }
    }

    // MARK: - Pressure

    private var pressureSection: some View {
        InspectorSection("Pressure", isCollapsed: $pressureCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindCR(\.pressureMode)) {
                    ForEach(CurvePressureMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("How pressure varies along the refined curve. Constant: uniform value. Increasing/Decreasing: linear ramp. Wave: sinusoidal cycle.")
            InspectorField("Value") {
                FloatEntryField(value: bindCR(\.pressureValue), width: 60)
            }
            .loomHelp("Base pressure value (0–1). Used as the peak or constant level depending on mode.")
        }
    }

    // MARK: - Drivers

    @ViewBuilder
    private var driversSection: some View {
        DoubleDriverEditor(
            label: "Displacement driver",
            driver: bindCRDriver(\.displacement),
            isCollapsed: $dispDriverCollapsed
        )
        DoubleDriverEditor(
            label: "CP Normal driver",
            driver: bindCRDriver(\.cpNormalOffset),
            isCollapsed: $cpDriverCollapsed
        )
    }

    // MARK: - Binding helpers

    private func bindCR<T>(_ kp: WritableKeyPath<CurveRefinementParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = CurveRefinementParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.curveRefinement[safe: crIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          crIdx  < cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement[crIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindCRDriver(_ kp: WritableKeyPath<CurveRefinementDrivers, DoubleDriver>) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.curveRefinement[safe: crIdx]?
                    .drivers?[keyPath: kp] ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          crIdx  < cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement.count
                    else { return }
                    if cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement[crIdx].drivers == nil {
                        cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement[crIdx].drivers =
                            CurveRefinementDrivers()
                    }
                    cfg.subdivisionConfig.paramsSets[setIdx].curveRefinement[crIdx].drivers![keyPath: kp] = v
                }
            }
        )
    }
}
