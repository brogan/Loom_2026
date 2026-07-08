import SwiftUI
import LoomEngine

/// Inspector for a single `FulgurationParams` pass (V1 — frame-cycle trigger,
/// transform variation, brief development; see Specs/GeometricLifecycle.md §5.3–§5.5).
/// Embedded in `SubdivisionInspector` when a fulguration param is selected.
struct FulgurationInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let fulIdx: Int

    @AppStorage("fulinsp.generalCollapsed")     private var generalCollapsed     = false
    @AppStorage("fulinsp.cycleCollapsed")       private var cycleCollapsed       = false
    @AppStorage("fulinsp.transformCollapsed")   private var transformCollapsed   = false
    @AppStorage("fulinsp.developmentCollapsed") private var developmentCollapsed = false

    var body: some View {
        generalSection
        cycleSection
        transformSection
        developmentSection
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindFUL(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindFUL(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Frame-cycle trigger

    private var cycleSection: some View {
        InspectorSection("Frame Cycle", isCollapsed: $cycleCollapsed) {
            InspectorField("Interval") {
                FloatEntryField(value: intAsDoubleBinding(\.intervalMin), width: 50, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.intervalMax), width: 50, fractionDigits: 0)
                Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Range of frames the form stays hidden before its next appearance, resampled each cycle (RPSR). At 24fps, 30–90 gives roughly one flash every 1.25–3.75 seconds.")

            InspectorField("Hold") {
                FloatEntryField(value: intAsDoubleBinding(\.holdMin), width: 50, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.holdMax), width: 50, fractionDigits: 0)
                Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Range of frames the form stays visible once triggered, resampled each cycle (RPSR). Combine with Development below for a brief grow/shrink rather than a hard on/off.")

            InspectorField("Seed") {
                IntEntryField(value: bindFULInt(\.cycleSeed), width: 140)
            }
            .loomHelp("Deterministic seed for the interval/hold sampling and the transform variation below. Change for a different flash rhythm and placement pattern without altering anything else.")
        }
    }

    // MARK: - Transform variation

    private var transformSection: some View {
        InspectorSection("Transform Variation", isCollapsed: $transformCollapsed) {
            InspectorField("Translation") {
                FloatEntryField(value: bindFUL(\.translationRange), width: 60)
            }
            .loomHelp("Maximum per-cycle offset from the sprite's normal placement, canvas-normalized units. Direction is resampled each cycle. 0 = no translation.")

            InspectorField("Scale") {
                FloatEntryField(value: bindFUL(\.scaleMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindFUL(\.scaleMax), width: 50)
            }
            .loomHelp("Per-cycle scale range around 1.0, resampled each cycle. 1–1 = no scale variation; 0.5–1.5 gives noticeably different-sized flashes each time.")

            InspectorField("Rotation") {
                FloatEntryField(value: bindFUL(\.rotationRange), width: 60)
                Text("rad").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Maximum per-cycle rotation, radians, resampled each cycle. 0 = no rotation variation.")
        }
    }

    // MARK: - Development

    private var developmentSection: some View {
        let mode = bindFUL(\.developmentMode).wrappedValue

        return InspectorSection("Development", isCollapsed: $developmentCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindFUL(\.developmentMode)) {
                    Text("Instant").tag(FulgurationDevelopmentMode.instant)
                    Text("Grow / Shrink").tag(FulgurationDevelopmentMode.growShrink)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Instant: the form is fully present for the whole Hold window, then gone. Grow / Shrink: scale ramps in at the start of the hold window and out at the end, so the flash briefly develops rather than popping — the same scale-around-centroid math Dissolution's Brief collapse uses.")

            if mode == .growShrink {
                InspectorField("Grow-in") {
                    FloatEntryField(value: intAsDoubleBinding(\.growInDuration), width: 50, fractionDigits: 0)
                    Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Frames at the start of the hold window spent scaling in from zero.")

                InspectorField("Shrink-out") {
                    FloatEntryField(value: intAsDoubleBinding(\.shrinkOutDuration), width: 50, fractionDigits: 0)
                    Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Frames at the end of the hold window spent scaling back out to zero. Grow-in and shrink-out are automatically clamped so together they never exceed the actual hold duration for that cycle.")
            }
        }
    }

    // MARK: - Binding helpers

    private func bindFUL<T>(_ kp: WritableKeyPath<FulgurationParams, T>) -> Binding<T> {
        let ctl      = controller
        let fallback = FulgurationParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.fulgurationPasses[safe: fulIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          fulIdx < cfg.subdivisionConfig.paramsSets[setIdx].fulgurationPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].fulgurationPasses[fulIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindFULInt(_ kp: WritableKeyPath<FulgurationParams, Int>) -> Binding<Int> {
        bindFUL(kp)
    }

    /// `FloatEntryField` only takes `Binding<Double>`; small user-chosen Int ranges
    /// (frame counts) stay on this bridge — same as EvolutionInspector's non-seed
    /// Int fields — since they're well within Double's exact-integer range.
    private func intAsDoubleBinding(_ kp: WritableKeyPath<FulgurationParams, Int>) -> Binding<Double> {
        let b = bindFULInt(kp)
        return Binding(
            get: { Double(b.wrappedValue) },
            set: { b.wrappedValue = Int($0.rounded()) }
        )
    }
}
