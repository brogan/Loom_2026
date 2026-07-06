import SwiftUI
import LoomEngine

/// Inspector for a single `DissolutionParams` pass.
/// Embedded in `SubdivisionInspector` when a dissolution param is selected.
struct DissolutionInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let disIdx: Int

    @AppStorage("disinsp.generalCollapsed")  private var generalCollapsed  = false
    @AppStorage("disinsp.entropyCollapsed")  private var entropyCollapsed  = false
    @AppStorage("disinsp.collapseCollapsed") private var collapseCollapsed = false

    var body: some View {
        generalSection
        entropySection
        collapseSection
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindDIS(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindDIS(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Entropy

    private var entropySection: some View {
        InspectorSection("Entropy", isCollapsed: $entropyCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindDIS(\.entropyEnabled)).labelsHidden()
            }
            .loomHelp("When on, polygon vertices gradually migrate toward the target shape over time. The form does not disappear — it loses complexity.")

            InspectorField("Rate") {
                FloatEntryField(value: bindDIS(\.entropyRate), width: 60)
            }
            .loomHelp("Fraction of the remaining distance to target consumed per frame, compounded exponentially. Safe range: 0.001–0.02. At 0.005 a polygon takes ~200 frames to reach half its target. Higher values accelerate decay; above 0.1 may feel sudden.")

            InspectorField("Target") {
                Picker("", selection: bindDIS(\.entropyTarget)) {
                    ForEach(EntropyTarget.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .loomHelp("Smoothed: each anchor moves toward the average of its neighbors — corners round while retaining the polygon's overall gesture. Centroid: all anchors converge to the polygon centre — the form collapses inward. Circle: anchors normalize to a best-fit circle radius — angular shapes become round.")

            InspectorField("Noise") {
                FloatEntryField(value: bindDIS(\.entropyNoise), width: 60)
            }
            .loomHelp("Per-anchor random perturbation added during erosion, in canvas units. 0 = perfectly uniform decay toward target. Values above 0 make the path toward simplicity irregular and organic. Keep below 5 for subtle texture.")

            InspectorField("Seed") {
                let b = bindDISInt(\.entropySeed)
                FloatEntryField(value: Binding(
                    get:  { Double(b.wrappedValue) },
                    set:  { b.wrappedValue = Int($0.rounded()) }
                ), width: 60, fractionDigits: 0)
            }
            .loomHelp("Deterministic seed for entropy noise. Change to get a different erosion pattern without altering any other parameters.")
        }
    }

    // MARK: - Collapse

    private var collapseSection: some View {
        let triggerType = bindDIS(\.collapseTriggerType).wrappedValue
        let collapseMode = bindDIS(\.collapseMode).wrappedValue

        return InspectorSection("Collapse", isCollapsed: $collapseCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindDIS(\.collapseEnabled)).labelsHidden()
            }
            .loomHelp("When on, the form disappears at the trigger frame. Combine with Entropy for a form that erodes then finally vanishes.")

            InspectorField("Trigger") {
                Picker("", selection: bindDIS(\.collapseTriggerType)) {
                    Text("Frame count").tag(CollapseTriggerType.frameCount)
                    Text("Probability").tag(CollapseTriggerType.probability)
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }
            .loomHelp("Frame count: collapse fires at exactly N frames. Probability: each frame independently has probability P of triggering collapse — expected lifetime = 1/P frames.")

            if triggerType == .frameCount {
                InspectorField("Frame") {
                    let b = bindDISInt(\.collapseTriggerFrameCount)
                    FloatEntryField(value: Binding(
                        get:  { Double(b.wrappedValue) },
                        set:  { b.wrappedValue = max(1, Int($0.rounded())) }
                    ), width: 60, fractionDigits: 0)
                    Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Number of frames after which the form collapses. At 24 fps, 240 frames = 10 seconds.")
            } else {
                InspectorField("Probability") {
                    FloatEntryField(value: bindDIS(\.collapseTriggerProbability), width: 60)
                }
                .loomHelp("Per-frame probability of collapse (0–1). 0.01 = average lifetime of 100 frames. 0.001 = average 1000 frames. Very small values produce long, unpredictable lifetimes.")
            }

            InspectorField("Mode") {
                Picker("", selection: bindDIS(\.collapseMode)) {
                    ForEach(CollapseMode.allCases, id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .loomHelp("Instant: the form vanishes in a single frame. Brief: the form shrinks to its centroid over the specified number of frames before disappearing.")

            if collapseMode == .brief {
                InspectorField("Duration") {
                    let b = bindDISInt(\.collapseBriefDuration)
                    FloatEntryField(value: Binding(
                        get:  { Double(b.wrappedValue) },
                        set:  { b.wrappedValue = max(1, Int($0.rounded())) }
                    ), width: 60, fractionDigits: 0)
                    Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Number of frames over which the form shrinks to zero during a Brief collapse. 6–12 frames is a fast but visible implosion; longer durations make the collapse feel deliberate.")
            }

            InspectorField("After") {
                Picker("", selection: bindDIS(\.collapseEndMode)) {
                    ForEach(CollapseEndMode.allCases, id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .loomHelp("Remove: form is gone permanently after collapse. Loop: the dissolution cycle restarts from the beginning — the form reappears at full complexity and begins eroding again. Respawn: the form is removed (Fulguration integration pending).")
        }
    }

    // MARK: - Binding helpers

    private func bindDIS<T>(_ kp: WritableKeyPath<DissolutionParams, T>) -> Binding<T> {
        let ctl      = controller
        let fallback = DissolutionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.dissolutionPasses[safe: disIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          disIdx < cfg.subdivisionConfig.paramsSets[setIdx].dissolutionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].dissolutionPasses[disIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindDISInt(_ kp: WritableKeyPath<DissolutionParams, Int>) -> Binding<Int> {
        bindDIS(kp)
    }
}
