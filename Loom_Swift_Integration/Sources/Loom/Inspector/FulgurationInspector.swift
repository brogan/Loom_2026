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
    @AppStorage("fulinsp.assemblyCollapsed")    private var assemblyCollapsed    = false
    @AppStorage("fulinsp.exitCollapsed")        private var exitCollapsed        = false

    var body: some View {
        generalSection
        cycleSection
        if bindFUL(\.contentMode).wrappedValue == .transform {
            transformSection
            developmentSection
        } else {
            assemblySection
            exitSection
        }
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
            InspectorField("Content") {
                Picker("", selection: bindFUL(\.contentMode)) {
                    Text("Transform").tag(FulgurationContentMode.transform)
                    Text("Assembly").tag(FulgurationContentMode.assembly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Transform: the sprite's own resolved geometry flashes with a rigid transform (V1). Assembly: the flash's content is instead built by combining primitive pieces (square/triangle/pentagon/line) end-to-end, replacing the sprite's geometry for the hold window rather than transforming it (V3, §5.12).")
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

    // MARK: - Assembly (V3, §5.12)

    private var assemblySection: some View {
        InspectorSection("Assembly", isCollapsed: $assemblyCollapsed) {
            InspectorField("Piece Count") {
                FloatEntryField(value: intAsDoubleBinding(\.assemblyPieceCountMin), width: 50, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.assemblyPieceCountMax), width: 50, fractionDigits: 0)
            }
            .loomHelp("How many primitive pieces (square/triangle/pentagon/line) are combined into this flash's composite, resampled each cycle (RPSR). Pieces are drawn with repetition from a small built-in kit, then attached edge-to-edge.")

            InspectorField("Size") {
                FloatEntryField(value: bindFUL(\.assemblySizeMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindFUL(\.assemblySizeMax), width: 50)
            }
            .loomHelp("Uniform size range for each piece before attachment, resampled per piece (RPSR) — independent of Deform below. The built-in kit's base shapes are canvas-scale on their own (roughly a 0.5-radius circle), so this is what keeps pieces from starting large: 0.15–0.35 (the default) gives noticeably smaller pieces than 1–1 would.")

            InspectorField("Deform") {
                FloatEntryField(value: bindFUL(\.assemblyDeformMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindFUL(\.assemblyDeformMax), width: 50)
            }
            .loomHelp("Independent per-axis scale range applied to each piece before attachment, so repeated draws of the same primitive don't look identical — a square becomes a rectangle or rhomboid, a triangle becomes scalene. 1–1 = no deform.")

            InspectorField("Edge Matching") {
                Picker("", selection: bindFUL(\.assemblyEdgeMatching)) {
                    Text("Preserve Size").tag(AssemblyEdgeMatching.preserveSize)
                    Text("Match Length").tag(AssemblyEdgeMatching.matchLength)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .loomHelp("Preserve Size: an incoming piece keeps its own native scale at the joint (mismatched edge lengths — rougher, more found-object). Match Length: the incoming piece is additionally rescaled so its attachment edge matches the target's length exactly (clean joinery). No effect where either site is a curve endpoint (a line's ends have no length).")
        }
    }

    // MARK: - Exit (V3, §5.12.6)

    private var exitSection: some View {
        let mode = bindFUL(\.exitMode).wrappedValue

        return InspectorSection("Exit", isCollapsed: $exitCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindFUL(\.exitMode)) {
                    Text("Instant").tag(FulgurationExitMode.instant)
                    Text("Shrink").tag(FulgurationExitMode.shrink)
                    Text("Offscreen").tag(FulgurationExitMode.offscreen)
                    Text("Shatter").tag(FulgurationExitMode.shatter)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            .loomHelp("How the assembled composite disappears at the end of its hold window. Instant: pops off. Shrink: scales to nothing around its own centroid. Offscreen: translates past the canvas edge. Shatter: each piece drifts away independently — fade was considered and dropped, per-shape alpha isn't reliable in the current render pipeline.")

            if mode != .instant {
                InspectorField("Duration") {
                    FloatEntryField(value: intAsDoubleBinding(\.exitDuration), width: 50, fractionDigits: 0)
                    Text("fr").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Frames at the end of the hold window spent exiting (shrinking, translating offscreen, or scattering). Clamped to the hold duration.")
            }

            if mode == .shatter {
                InspectorField("Drift") {
                    FloatEntryField(value: bindFUL(\.shatterDistance), width: 60)
                }
                .loomHelp("Maximum per-piece drift distance, canvas-normalized units, reached at full exit progress. Each piece's direction is chosen independently (seeded) — same math as Dissolution's own Drift, applied to the assembly's pieces instead of a sprite's resolved polygons.")

                InspectorField("Spin") {
                    FloatEntryField(value: bindFUL(\.shatterRotation), width: 60)
                    Text("rad").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Maximum per-piece rotation, radians, reached at full exit progress.")
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
