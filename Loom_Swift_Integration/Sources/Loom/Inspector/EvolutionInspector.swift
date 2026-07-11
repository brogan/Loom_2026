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
    @AppStorage("evinsp.graftOpCollapsed")     private var graftOpCollapsed    = true
    @AppStorage("evinsp.phaseDriverCollapsed") private var phaseDriverCollapsed = true
    @AppStorage("evinsp.directionalCollapsed") private var directionalCollapsed = true

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
            graftOperatorSection
            directionalSelectorSection
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
            .loomHelp("Which parameter the drift displaces. Line Ratio XY affects both line ratio axes equally. The three Curve targets (Displacement/CP Normal Offset/Pressure) drift this transform set's Curve Refinement params instead — the open-curve counterpart, since the other targets only affect closed polygons (Subdivision skips open curves entirely).")

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
                IntEntryField(value: bindEVInt(\.driftSeed), width: 60)
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
            .loomHelp("The transform set this pass converges toward. The target's line ratios, CP offsets, and inset scale/rotation are lerped for closed polygons; if this set also has Curve Refinement passes, its displacement/CP normal offset/pressure are lerped toward the same target set's curve params too, in the same pass — no separate target picker needed for curves.")

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
                IntEntryField(value: bindEVInt(\.generationSeed), width: 140)
            }
            .loomHelp("Deterministic seed. The same seed and parameters always produce the identical generation history — change it for a different evolutionary path. Paste the value from the Global tab's Evolution Seed readout here (with Vary seed per cycle off) to reproduce a generation you liked exactly — this field handles the full range of values that readout can show, unlike a typical decimal field.")

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

        InspectorField("Vary seed per cycle") {
            Toggle("", isOn: bindEV(\.varySeedPerCycle)).labelsHidden()
        }
        .loomHelp("When the Reveal driver loops (Oscillator, or Keyframe with Loop/Ping-pong), each full cycle uses a different effective seed, so it mutates a new shape each time rather than replaying the identical growth. Has no effect while Reveal is off, or with a one-shot (non-looping) Keyframe track — there's no restart point to vary between. The seed field above is unaffected; this only changes what the engine derives from it internally.")
            .padding(.bottom, 2)
    }

    // MARK: - Generational: extrude operator

    private var extrudeOperatorSection: some View {
        let includeOpenCurves = bindEV(\.extrudeIncludeOpenCurves).wrappedValue

        return InspectorSection("Extrude", isCollapsed: $extrudeOpCollapsed) {
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

            InspectorField("Asymmetric Sides") {
                Toggle("", isOn: bindEV(\.extrudeAsymmetricSides)).labelsHidden()
            }
            .loomHelp("Off (default): both corners of an extruded edge move out by the same distance — a rectangular quad. On: each corner is independently randomized (scaled from the sampled Distance), so quads taper into a wedge instead. Resampled per edge, so a multi-edge run doesn't lean uniformly one way.")

            InspectorField("Angled") {
                Toggle("", isOn: bindEV(\.extrudeAngleRandomized)).labelsHidden()
            }
            .loomHelp("Off (default): extrusion is exactly perpendicular to its edge. On: direction is randomized up to ±45° from perpendicular (45°–135° measured from the edge itself), resampled per edge.")

            InspectorField("Include Open Curves") {
                Toggle("", isOn: bindEV(\.extrudeIncludeOpenCurves)).labelsHidden()
            }
            .loomHelp("Off (default): Extrude only targets closed polygons — Generational Evolution's Split operator is unaffected either way, always closed-only. On: open curves also become eligible Extrude targets. An open curve has no interior, so there's no single principled outward direction the way a closed polygon has — each eligible edge instead independently picks one of its two sides at random.")

            if includeOpenCurves {
                InspectorField("Both Sides") {
                    Toggle("", isOn: bindEV(\.extrudeOpenCurveBothSides)).labelsHidden()
                }
                .loomHelp("Open curves only. Off (default): each edge extrudes on exactly one randomly-chosen side. On: a second, independent roll per edge decides whether that edge additionally extrudes its other side too — some edges in a run may end up with one quad, others with two.")
            }
        }
    }

    // MARK: - Generational: split operator

    private var splitOperatorSection: some View {
        InspectorSection("Split", isCollapsed: $splitOpCollapsed) {
            InspectorField("Weight") {
                FloatEntryField(value: bindEV(\.splitWeight), width: 60)
            }
            .loomHelp("Relative selection weight for the split operator each generation. Set to 0 to exclude splitting entirely (extrude-only evolution).")

            InspectorField("Position") {
                FloatEntryField(value: bindEV(\.splitPositionMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.splitPositionMax), width: 50)
            }
            .loomHelp("Where along the target edge the split lands (0 = start, 1 = end), resampled each generation (RPSR). 0.5–0.5 (default): always the exact midpoint. Widen the range so splits land at varied points rather than always the centre. Clamped to 0.05–0.95 regardless of setting, so an extreme value can't produce a degenerate sliver.")

            InspectorField("Displacement") {
                FloatEntryField(value: bindEV(\.splitDisplacementMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.splitDisplacementMax), width: 50)
            }
            .loomHelp("How far the new anchor point (from splitting a random edge) is displaced outward from the shape's centre, resampled each generation (RPSR). Only the anchor moves — its flanking control points stay put, pulling the boundary into a rounded spike rather than a sharp break.")

            InspectorField("Bulge / Pinch") {
                FloatEntryField(value: bindEV(\.splitBulgePinchMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.splitBulgePinchMax), width: 50)
            }
            .loomHelp("0–0 (default): the two control points flanking the new anchor stay exactly where the split placed them. Positive values push them further out than the anchor for a fuller, rounder bulge; negative values pull them back for a concave pinch/dimple right at the split. Independent of Displacement above, resampled each generation (RPSR).")
        }
    }

    // MARK: - Generational: graft operator (Specs/GeometricLifecycle.md §4.4.8)

    private var graftOperatorSection: some View {
        let mode = bindEV(\.graftAttachmentMode).wrappedValue

        return InspectorSection("Graft", isCollapsed: $graftOpCollapsed) {
            InspectorField("Weight") {
                FloatEntryField(value: bindEV(\.graftWeight), width: 60)
            }
            .loomHelp("Relative selection weight for the graft operator each generation, alongside Extrude/Split's own weights above. 0 (default) excludes Graft entirely.")

            InspectorField("Sides") {
                FloatEntryField(value: intAsDoubleBinding(\.graftSidesMin), width: 40, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.graftSidesMax), width: 40, fractionDigits: 0)
            }
            .loomHelp("Number of sides `n` of the primitive grafted on each generation, resampled from this range (RPSR). n≤2 degenerates to a bare line (no meaningful 2-sided polygon) — n=1 is a line by design, the most basic \"polygon.\" n≥3 is a plain regular n-gon; unlike Assembly Fulguration's fixed square/triangle/pentagon kit, any n is reachable.")

            InspectorField("Distortion") {
                FloatEntryField(value: bindEV(\.graftDistortionMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.graftDistortionMax), width: 50)
            }
            .loomHelp("Independent per-axis scale range applied to the primitive before attachment, so repeated grafts don't look identical — a square becomes a rectangle or rhomboid. 1–1 (default) = no distortion.")

            InspectorField("Edge Matching") {
                Picker("", selection: bindEV(\.graftEdgeMatching)) {
                    Text("Preserve Size").tag(AssemblyEdgeMatching.preserveSize)
                    Text("Match Length").tag(AssemblyEdgeMatching.matchLength)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .loomHelp("Preserve Size: the grafted primitive keeps its own native scale at the joint (mismatched edge lengths — rougher, found-object). Match Length: additionally rescaled so its attachment edge/span matches the parent's exactly (clean joinery). No effect for Single Point attachment (a point has no length to match).")

            InspectorField("Attachment") {
                Picker("", selection: bindEV(\.graftAttachmentMode)) {
                    Text("Whole Edge").tag(GraftAttachmentMode.wholeEdge)
                    Text("Single Point").tag(GraftAttachmentMode.singlePoint)
                    Text("Partial Edge").tag(GraftAttachmentMode.partialEdge)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
            .loomHelp("Whole Edge: the primitive's chosen edge is matched exactly onto the parent's target edge — closest to Extrude. Single Point: only one coordinate is shared, leaving departure direction free — closest to Split/Branch. Partial Edge: matches a sub-span of the parent edge rather than the whole thing. All three exclude only the specific matched site from curvature/articulation below — every other edge is free.")

            if mode == .singlePoint {
                InspectorField("Point Source") {
                    Picker("", selection: bindEV(\.graftPointSource)) {
                        Text("Existing Vertex").tag(GraftPointSource.existingVertex)
                        Text("Newly Inserted").tag(GraftPointSource.newlyInsertedPoint)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                .loomHelp("Existing Vertex (default): attaches from the target edge's own start anchor, touching nothing on the parent. Newly Inserted: splits the target edge first (reusing Split's own Position range below), undisplaced, then attaches from the new anchor — matches Split's own behavior.")

                InspectorField("Departure") {
                    FloatEntryField(value: departureAngleMinDegrees, width: 60)
                    Text("–").foregroundStyle(.secondary)
                    FloatEntryField(value: departureAngleMaxDegrees, width: 60)
                    Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Departure angle, resampled each generation (RPSR), relative to the target edge's own outward normal at the chosen point. 0°–0° (default): always departs exactly outward, matching Split's own undeviated displacement direction.")
            }

            if mode == .partialEdge {
                InspectorField("Position") {
                    FloatEntryField(value: bindEV(\.graftPartialPositionMin), width: 50)
                    Text("–").foregroundStyle(.secondary)
                    FloatEntryField(value: bindEV(\.graftPartialPositionMax), width: 50)
                }
                .loomHelp("Where along the target edge the partial span starts (0 = start, 1 = end), resampled each generation (RPSR). 0–0 (default) = always starts at the edge's own start.")

                InspectorField("Span") {
                    FloatEntryField(value: bindEV(\.graftPartialSpanMin), width: 50)
                    Text("–").foregroundStyle(.secondary)
                    FloatEntryField(value: bindEV(\.graftPartialSpanMax), width: 50)
                }
                .loomHelp("What fraction (0–1) of the edge's *remaining* length beyond Position the span covers, resampled each generation (RPSR). 1–1 (default) covers the full remainder — Position 0–0 / Span 1–1 together reproduce Whole Edge's target exactly; narrowing either is what makes it partial.")
            }

            InspectorField("Curvature") {
                FloatEntryField(value: bindEV(\.graftEdgeCurvatureProbability), width: 50)
            }
            .loomHelp("Per-free-edge chance (0–1) of becoming curved instead of staying straight, rolled independently per edge every generation. 0 (default) = never curved. \"Free\" means every edge except the one matched to the parent above.")

            InspectorField("Curve Amount") {
                FloatEntryField(value: bindEV(\.graftEdgeCurvatureAmountMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.graftEdgeCurvatureAmountMax), width: 50)
            }
            .loomHelp("Bow magnitude when an edge is curved, as a fraction of that edge's own length, resampled per curved edge (RPSR). Same units Extension's own extrusion curvature uses.")

            InspectorField("Articulation") {
                FloatEntryField(value: intAsDoubleBinding(\.graftArticulationCountMin), width: 40, fractionDigits: 0)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: intAsDoubleBinding(\.graftArticulationCountMax), width: 40, fractionDigits: 0)
            }
            .loomHelp("How many extra joints a free edge is subdivided into, resampled per free edge (RPSR). 0–0 (default) = no articulation.")

            InspectorField("Art. Pattern") {
                Picker("", selection: bindEV(\.graftArticulationPattern)) {
                    Text("Jitter").tag(GraftArticulationPattern.jitter)
                    Text("Zig Zag").tag(GraftArticulationPattern.zigzag)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Jitter: each joint's displacement direction and magnitude are independently randomized. Zig Zag: displacement alternates side deterministically joint-to-joint, magnitude still randomized — a regular zigzag rather than a scatter.")

            InspectorField("Art. Amount") {
                FloatEntryField(value: bindEV(\.graftArticulationAmountMin), width: 50)
                Text("–").foregroundStyle(.secondary)
                FloatEntryField(value: bindEV(\.graftArticulationAmountMax), width: 50)
            }
            .loomHelp("Displacement magnitude per joint, canvas-normalized units, perpendicular to the edge's own local direction, resampled per joint (RPSR).")
        }
    }

    private var departureAngleMinDegrees: Binding<Double> {
        let b = bindEV(\.graftDepartureAngleMin)
        return Binding(
            get: { b.wrappedValue * 180.0 / .pi },
            set: { b.wrappedValue = $0 * .pi / 180.0 }
        )
    }

    private var departureAngleMaxDegrees: Binding<Double> {
        let b = bindEV(\.graftDepartureAngleMax)
        return Binding(
            get: { b.wrappedValue * 180.0 / .pi },
            set: { b.wrappedValue = $0 * .pi / 180.0 }
        )
    }

    // MARK: - Generational: directional selector

    @ViewBuilder
    private var directionalSelectorSection: some View {
        DirectionalSelectorEditor(
            label: "Directional Selector",
            selector: bindEV(\.directionalSelector),
            isCollapsed: $directionalCollapsed
        )
        .loomHelp("Restricts which edges Extrude/Split may target by outward-normal direction — e.g. only edges facing up. Applies to both operators' target-edge choice. Off (default): every edge is eligible, unchanged.")
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
