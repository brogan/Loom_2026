import SwiftUI
import LoomEngine

struct SubdivisionInspector: View {

    @EnvironmentObject private var controller: AppController
    @State private var activePTPTab: PTPTab = .exterior
    @State private var showCompositor = false
    @AppStorage("subinsp.generalCollapsed")          private var generalCollapsed       = false
    @AppStorage("subinsp.insetCollapsed")            private var insetCollapsed         = false
    @AppStorage("subinsp.pressureCollapsed")         private var pressureCollapsed      = false
    @AppStorage("subinsp.subdivDriversCollapsed")    private var subdivDriversCollapsed = true
    @AppStorage("subinsp.subdivGenDriversCollapsed") private var subdivGenDriversCollapsed  = false
    @AppStorage("subinsp.subdivPTWDriversCollapsed") private var subdivPTWDriversCollapsed  = false
    @AppStorage("subinsp.lineRatioDriverCollapsed")  private var lineRatioDriverCollapsed    = true
    @AppStorage("subinsp.cpRatioDriverCollapsed")    private var cpRatioDriverCollapsed      = true
    @AppStorage("subinsp.cpNormalDriverCollapsed")   private var cpNormalDriverCollapsed     = true
    @AppStorage("subinsp.insetScaleDriverCollapsed") private var insetScaleDriverCollapsed   = true
    @AppStorage("subinsp.insetRotDriverCollapsed")   private var insetRotDriverCollapsed     = true
    @AppStorage("subinsp.ranDivDriverCollapsed")     private var ranDivDriverCollapsed       = true
    @AppStorage("subinsp.ptwTXDriverCollapsed")      private var ptwTXDriverCollapsed        = true
    @AppStorage("subinsp.ptwTYDriverCollapsed")      private var ptwTYDriverCollapsed        = true
    @AppStorage("subinsp.ptwScaleDriverCollapsed")   private var ptwScaleDriverCollapsed     = true
    @AppStorage("subinsp.ptwRotDriverCollapsed")     private var ptwRotDriverCollapsed       = true

    var body: some View {
        let setIdx = controller.selectedSubdivisionIndex ?? 0
        guard let set = controller.projectConfig?.subdivisionConfig.paramsSets[safe: setIdx] else {
            return AnyView(EmptyView())
        }
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            setHeader(set: set, setIdx: setIdx)
            paramsList(set: set, setIdx: setIdx)
            if let paramIdx = controller.selectedSubdivisionParamIndex,
               let param = set.params[safe: paramIdx] {
                paramEditor(param: param, setIdx: setIdx, paramIdx: paramIdx)
            }
        })
    }

    // MARK: - Set header

    private func setHeader(set: SubdivisionParamsSet, setIdx: Int) -> some View {
        InspectorSection("Set") {
            InspectorField("Name") {
                TextField("", text: bindSet(setIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 120)
            }
            InspectorRow(label: "Params", value: "\(set.params.count)")
        }
    }

    // MARK: - Params mini-list

    private func paramsList(set: SubdivisionParamsSet, setIdx: Int) -> some View {
        InspectorSection("Params") {
            InspectorPickList(
                items: set.params,
                labelFor: { $0.name.isEmpty ? "(unnamed)" : $0.name },
                selection: Binding(
                    get: { controller.selectedSubdivisionParamIndex },
                    set: { controller.selectedSubdivisionParamIndex = $0 }
                )
            )
        }
        .onChange(of: controller.selectedSubdivisionIndex) { _, _ in
            controller.selectedSubdivisionParamIndex = nil
        }
    }

    // MARK: - Param editor

    @ViewBuilder
    private func paramEditor(param: SubdivisionParams, setIdx: Int, paramIdx: Int) -> some View {
        generalSection(setIdx: setIdx, paramIdx: paramIdx)
        if param.subdivisionType == .custom {
            compositorButton(setIdx: setIdx, paramIdx: paramIdx)
        }
        if param.subdivisionType.usesInsetTransform {
            insetSection(setIdx: setIdx, paramIdx: paramIdx)
        }
        pressureSection(setIdx: setIdx, paramIdx: paramIdx)
        polygonTransformEnabledSection(setIdx: setIdx, paramIdx: paramIdx)
        ptwSection(setIdx: setIdx, paramIdx: paramIdx)
        ptpSection(setIdx: setIdx, paramIdx: paramIdx)
        subdivisionDriversSection(param: param, setIdx: setIdx, paramIdx: paramIdx)
    }

    // MARK: - Custom compositor

    private func compositorButton(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Custom Algorithm") {
            InspectorRow(
                label: controller.projectConfig?
                    .subdivisionConfig.paramsSets[safe: setIdx]?
                    .params[safe: paramIdx]?
                    .customAlgorithm?.name ?? "Untitled",
                value: ""
            )
            Button("Configure…") { showCompositor = true }
                .font(.system(size: 12))
                .padding(.vertical, 4)
        }
        .sheet(isPresented: $showCompositor) {
            if let setIdx = controller.selectedSubdivisionIndex,
               let paramIdx = controller.selectedSubdivisionParamIndex {
                CompositorView(
                    algorithm: controller.projectConfig?
                        .subdivisionConfig.paramsSets[safe: setIdx]?
                        .params[safe: paramIdx]?
                        .customAlgorithm ?? CustomSubdivisionAlgorithm.starter,
                    onSave: { updated in
                        controller.updateCustomAlgorithm(updated, setIdx: setIdx, paramIdx: paramIdx)
                    }
                )
                .frame(minWidth: 860, minHeight: 560)
            }
        }
    }

    // MARK: - General

    private func generalSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindP(setIdx, paramIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            .loomHelp("Label for this subdivision step — appears in the params list.")
            InspectorField("Algorithm") {
                Picker("", selection: bindP(setIdx, paramIdx, \.subdivisionType)) {
                    ForEach(SubdivisionType.allCases, id: \.self) { t in
                        Text(t.shortName).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Subdivision algorithm applied to each input polygon at this step. Quad/Tri split into child shapes; Echo/Bord add inset copies; Split cuts along one axis.")
            vector2DField("Line ratios", xKP: \.lineRatios.x, yKP: \.lineRatios.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Horizontal (X) and vertical (Y) split positions within the polygon, in the range 0–1. Controls exactly where the subdivision lines land.")
            vector2DField("CP ratios", xKP: \.controlPointRatios.x, yKP: \.controlPointRatios.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Parametric position of each control point along the internal connector edge (0 = start anchor, 1 = end anchor). Affects the spacing distribution of subdivision vertices but not the geometric curvature of the edge.")
            vector2DField("CP normals", xKP: \.cpNormalOffsets.x, yKP: \.cpNormalOffsets.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Perpendicular offset for each control point, expressed as a fraction of the segment length. Non-zero values produce genuine Bézier curvature on internal edges. X offsets CP1; Y offsets CP2. Positive/negative flip the bow direction.")
            InspectorField("Normalise") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.cpNormalizeTowardsCentre)).labelsHidden()
            }
            .loomHelp("When on, positive CP normals offset away from the polygon centroid (outward bow); when off, positive is the fixed left-perpendicular of each edge direction.")
            InspectorField("Continuous") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.continuous)).labelsHidden()
            }
            .loomHelp("When on, all child polygons from this step use this same parameter rather than advancing to the next one in the set.")
            InspectorField("Curve split") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.curveAwareSplit)).labelsHidden()
            }
            .loomHelp("Quad only. When off (default), new split-point anchors land at the straight-line midpoint between the two existing anchors — matching the original Scala behaviour and avoiding drift at higher subdivision levels. When on, split points land on the actual Bézier curve (de Casteljau), so curved outer edges like circles or ovals are respected. The two modes produce visibly different results: off keeps straight edges straight; on keeps curved edges curved.")
            InspectorField("Mirror curve") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.mirrorOuterCurvature)).labelsHidden()
            }
            .loomHelp("Quad only. When on, the internal edges (split-point → centre) are given an initial bow that mirrors the curvature of their adjacent outer edge, rather than being drawn straight. The bow is scaled proportionally to the internal edge length.")
            InspectorField("Invert curve") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.invertCurvature)).labelsHidden()
            }
            .loomHelp("Reverses the direction of the mirrored curvature on internal edges. Only active when Mirror curve is on.")
            InspectorField("Curve sync") {
                Picker("", selection: bindP(setIdx, paramIdx, \.curvatureSync)) {
                    Text("All").tag("ALL")
                    Text("Even").tag("EVEN")
                    Text("Odd").tag("ODD")
                    Text("Alternate").tag("ALTERNATE")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            .loomHelp("Controls which internal edges receive the mirrored bow. All: every edge. Even/Odd: every other edge, straight on the remaining ones. Alternate: even edges bow forward, odd edges bow in reverse — produces a pinwheel or turbine pattern.")
            InspectorField("Visibility") {
                Picker("", selection: bindP(setIdx, paramIdx, \.visibilityRule)) {
                    ForEach(VisibilityRule.allCases, id: \.self) { r in
                        Text(r.shortName).tag(r)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Filters which output polygons are rendered — all, alternating, random fractions, every nth, and so on.")
            InspectorField("Ran middle") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.ranMiddle)).labelsHidden()
            }
            .loomHelp("Jitters the subdivision midpoint position randomly each draw cycle, breaking the regularity of the split.")
            InspectorField("Ran divisor") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.ranDiv), width: 60, fractionDigits: 1)
            }
            .loomHelp("Scales the midpoint jitter amount — higher values produce smaller offsets. Default 100.")
        }
    }

    // MARK: - Inset Transform (echo / bord types only)

    private func insetSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Inset Transform", isCollapsed: $insetCollapsed) {
            vector2DField("Scale",
                          xKP: \.insetTransform.scale.x, yKP: \.insetTransform.scale.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Scale of the echo or border inset polygon relative to its parent. 1.0 = same size; values below 1 shrink it.")
            vector2DField("Translate",
                          xKP: \.insetTransform.translation.x, yKP: \.insetTransform.translation.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Positional offset applied to the inset polygon along X and Y.")
            InspectorField("Rotation") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.insetTransform.rotation),
                                width: 80, fractionDigits: 4)
                Text("rad").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Rotation of the inset polygon in radians, relative to the source polygon.")
        }
    }

    // MARK: - Pressure Sensitivity

    private func pressureSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Pressure Sensitivity", isCollapsed: $pressureCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindP(setIdx, paramIdx, \.pressureSubdivisionMode)) {
                    ForEach(PressureSubdivisionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("How pressure values from the source polygon are distributed to child polygons created by this subdivision step.")
            if controller.projectConfig?.subdivisionConfig
                .paramsSets[safe: setIdx]?.params[safe: paramIdx]?.pressureSubdivisionMode == .random {
                InspectorField("Groups") {
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { idx in
                            Toggle("\(idx + 1)", isOn: bindPressureRandomGroup(setIdx, paramIdx, idx))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 10))
                        }
                    }
                }
                .loomHelp("Which pressure groups (1–5) participate in random pressure assignment. At least one should be enabled.")
            }
        }
    }

    // MARK: - Polygon Transforms

    private func polygonTransformEnabledSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Polygon Transforms") {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTransform)).labelsHidden()
            }
            .loomHelp("Master switch enabling the PTW (whole-polygon) and PTP (point-level) transform sections for this subdivision step.")
        }
    }

    // MARK: - Transform Whole Polygons

    private func ptwSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Transform Whole Polygons", isCollapsed: $controller.subdivPtwCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTranformWhole)).labelsHidden()
            }
            .loomHelp("Activate random per-polygon translation, scale, and rotation transforms. Geometry stays at 100% scale until ranges are adjusted.")
            InspectorField("Probability") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.pTW_probability), width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) that any individual output polygon receives a transform each frame. At 50%, roughly half the polygons are affected.")
            InspectorField("Common ctr") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_commonCentre)).labelsHidden()
            }
            .loomHelp("When on, all polygons transform around one shared centre point rather than each polygon's own centroid — useful for radial scatter effects.")
            InspectorField("Ran transl") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomTranslation)).labelsHidden()
            }
            .loomHelp("Enable random positional displacement. Must be on for Transl X/Y ranges to have any effect.")
            InspectorField("Ran scale") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomScale)).labelsHidden()
            }
            .loomHelp("Enable random scale variation per polygon. Must be on for Scale X/Y ranges to have any effect.")
            InspectorField("Ran rotate") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomRotation)).labelsHidden()
            }
            .loomHelp("Enable random rotation per polygon. Must be on for Rot range to have any effect.")
            vector2DField("Transl X",
                          xKP: \.pTW_randomTranslationRange.x.min,
                          yKP: \.pTW_randomTranslationRange.x.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            .loomHelp("Min/max range for random X-axis displacement applied per polygon.")
            vector2DField("Transl Y",
                          xKP: \.pTW_randomTranslationRange.y.min,
                          yKP: \.pTW_randomTranslationRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            .loomHelp("Min/max range for random Y-axis displacement applied per polygon.")
            vector2DField("Scale X",
                          xKP: \.pTW_randomScaleRange.x.min,
                          yKP: \.pTW_randomScaleRange.x.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            .loomHelp("Min/max range for random X-axis scale factor. 1.0 = no change; values above enlarge, below shrink.")
            vector2DField("Scale Y",
                          xKP: \.pTW_randomScaleRange.y.min,
                          yKP: \.pTW_randomScaleRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            .loomHelp("Min/max range for random Y-axis scale factor. 1.0 = no change.")
            vector2DField("Rot range",
                          xKP: \.pTW_randomRotationRange.min,
                          yKP: \.pTW_randomRotationRange.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            .loomHelp("Min/max range for random rotation angle in degrees applied per polygon.")
        }
    }

    // MARK: - Transform Polygon Points

    private func ptpSection(setIdx: Int, paramIdx: Int) -> some View {
        let isEnabled = controller.projectConfig?.subdivisionConfig
            .paramsSets[safe: setIdx]?.params[safe: paramIdx]?.polysTransformPoints ?? false
        return InspectorSection("Transform Polygon Points", isCollapsed: $controller.subdivPtpCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTransformPoints)).labelsHidden()
            }
            .loomHelp("Activate point-level deformation (PTP) for this subdivision step. Individual anchor and control-point groups are configured in the tabs below.")
            Group {
                InspectorField("Probability") {
                    FloatEntryField(value: bindP(setIdx, paramIdx, \.pTP_probability), width: 50, fractionDigits: 1)
                    Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Chance (0–100%) that PTP fires for each individual output polygon. All enabled groups apply to the polygons that pass this roll.")
                ptpTabBar()
                ptpEnabledSummary(setIdx: setIdx, paramIdx: paramIdx)
                ptpTabContent(setIdx: setIdx, paramIdx: paramIdx)
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
        }
    }

    private func ptpTabBar() -> some View {
        HStack(spacing: 2) {
            ForEach(PTPTab.allCases, id: \.self) { tab in
                Button(tab.rawValue) { activePTPTab = tab }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: activePTPTab == tab ? .semibold : .regular))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        activePTPTab == tab
                            ? Color.accentColor.opacity(0.2)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func ptpEnabledSummary(setIdx: Int, paramIdx: Int) -> some View {
        HStack(spacing: 0) {
            ptpCheckbox(.exterior,      \.exteriorAnchors.enabled,       setIdx: setIdx, paramIdx: paramIdx)
            ptpCheckbox(.central,       \.centralAnchors.enabled,        setIdx: setIdx, paramIdx: paramIdx)
            ptpCheckbox(.outerCP,       \.outerControlPoints.enabled,    setIdx: setIdx, paramIdx: paramIdx)
            ptpCheckbox(.anchorsLinked, \.anchorsLinkedToCentre.enabled, setIdx: setIdx, paramIdx: paramIdx)
            ptpCheckbox(.innerCP,       \.innerControlPoints.enabled,    setIdx: setIdx, paramIdx: paramIdx)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func ptpCheckbox(_ tab: PTPTab, _ kp: WritableKeyPath<PTPTransformSet, Bool>,
                               setIdx: Int, paramIdx: Int) -> some View {
        HStack(spacing: 3) {
            Toggle("", isOn: bindPTP(setIdx, paramIdx, kp))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(tab.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(activePTPTab == tab ? Color.accentColor : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func ptpTabContent(setIdx: Int, paramIdx: Int) -> some View {
        switch activePTPTab {
        case .exterior:      extContent(setIdx: setIdx, paramIdx: paramIdx)
        case .central:       cenContent(setIdx: setIdx, paramIdx: paramIdx)
        case .outerCP:       ocpContent(setIdx: setIdx, paramIdx: paramIdx)
        case .anchorsLinked: alcContent(setIdx: setIdx, paramIdx: paramIdx)
        case .innerCP:       icpContent(setIdx: setIdx, paramIdx: paramIdx)
        }
    }

    // MARK: - Ext (Exterior Anchors)

    private func extContent(setIdx: Int, paramIdx: Int) -> some View {
        VStack(spacing: 0) {
            InspectorField("Probability") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.probability),
                                width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) this Ext group fires per polygon, in addition to the top-level PTP probability.")
            InspectorField("Spike factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeFactor), width: 60)
            }
            .loomHelp("Displacement magnitude for exterior anchors. Positive values push outward (spike); negative pull inward (dent).")
            InspectorField("Which spike") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.whichSpike)) {
                    Text("All").tag("ALL")
                    Text("Corners").tag("CORNERS")
                    Text("Middles").tag("MIDDLES")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            .loomHelp("Which anchor subset is displaced — All anchors, Corner anchors only, or Midpoint anchors only.")
            InspectorField("Spike type") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeType)) {
                    Text("Symmetrical").tag("SYMMETRICAL")
                    Text("Right").tag("RIGHT")
                    Text("Left").tag("LEFT")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            .loomHelp("Direction of the spike — Symmetrical (balanced), Right-biased, Left-biased, or Random per anchor.")
            InspectorField("Spike axis") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeAxis)) {
                    Text("XY").tag("XY")
                    Text("X").tag("X")
                    Text("Y").tag("Y")
                }
                .labelsHidden().frame(maxWidth: 80)
            }
            .loomHelp("Constrain the displacement to both axes (XY), X only, or Y only.")
            InspectorField("Ran spike") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomSpike)).labelsHidden()
            }
            .loomHelp("Randomise spike magnitude per anchor within the Spike range below, instead of using the fixed Spike factor.")
            ptpFloatRangeField("Spike range", \.exteriorAnchors.randomSpikeFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max spike factor sampled per anchor when Ran spike is on.")
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsFollow)).labelsHidden()
            }
            .loomHelp("When on, control-point handles move with their displaced anchor, preserving the local curve shape at the spike.")
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsFollowMultiplier), width: 60)
            }
            .loomHelp("Multiplier controlling how closely handles track the anchor. 1.0 = full follow; values below reduce the effect.")
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomCpsFollow)).labelsHidden()
            }
            .loomHelp("Randomise the CP follow multiplier per anchor within the CPs fol rng below.")
            ptpFloatRangeField("CPs fol rng", \.exteriorAnchors.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for the random CP follow multiplier.")
            InspectorField("CPs squeeze") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsSqueeze)).labelsHidden()
            }
            .loomHelp("Pull control handles toward the edge midpoint, sharpening the base of the spike.")
            InspectorField("Squeeze fact") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsSqueezeFactor), width: 60)
            }
            .loomHelp("Factor controlling how strongly handles are pulled toward the edge midpoint.")
            InspectorField("Ran squeeze") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomCpsSqueeze)).labelsHidden()
            }
            .loomHelp("Randomise the squeeze factor per anchor within the Squeeze rng below.")
            ptpFloatRangeField("Squeeze rng", \.exteriorAnchors.randomCpsSqueezeRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for the random squeeze factor.")
        }
    }

    // MARK: - Cen (Central Anchors)

    private func cenContent(setIdx: Int, paramIdx: Int) -> some View {
        VStack(spacing: 0) {
            InspectorField("Probability") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.centralAnchors.probability),
                                width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) this Cen group fires per polygon, in addition to the top-level PTP probability.")
            InspectorField("Tear factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.centralAnchors.tearFactor), width: 60)
            }
            .loomHelp("Displacement magnitude for central anchor points. Larger values produce more dramatic tears.")
            InspectorField("Tear axis") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.centralAnchors.tearAxis)) {
                    Text("XY").tag("XY")
                    Text("X").tag("X")
                    Text("Y").tag("Y")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 90)
            }
            .loomHelp("Axis constraint for the tear — XY (both), X only, Y only, or Random per polygon.")
            InspectorField("Tear dir") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.centralAnchors.tearDirection)) {
                    Text("Diagonal").tag("DIAGONAL")
                    Text("Left").tag("LEFT")
                    Text("Right").tag("RIGHT")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 100)
            }
            .loomHelp("Directional bias for the tear — Diagonal, Left, Right, or Random per polygon.")
            InspectorField("Ran tear") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.randomTear)).labelsHidden()
            }
            .loomHelp("Randomise tear magnitude within the Tear range below, instead of using the fixed Tear factor.")
            ptpFloatRangeField("Tear range", \.centralAnchors.randomTearFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max tear factor sampled per polygon when Ran tear is on.")
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.cpsFollow)).labelsHidden()
            }
            .loomHelp("When on, control-point handles move with the torn anchor, preserving local curve shape.")
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.centralAnchors.cpsFollowMultiplier), width: 60)
            }
            .loomHelp("Multiplier for how closely handles track the torn anchor. 1.0 = full follow.")
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.randomCpsFollow)).labelsHidden()
            }
            .loomHelp("Randomise the CP follow multiplier per polygon within the CPs fol rng below.")
            ptpFloatRangeField("CPs fol rng", \.centralAnchors.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for the random CP follow multiplier.")
            InspectorField("All pts fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.allPointsFollow)).labelsHidden()
            }
            .loomHelp("When on, all other polygon points also displace in the same tear direction, shearing the whole shape.")
            InspectorField("Inverted fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.invertedFollow)).labelsHidden()
            }
            .loomHelp("Reverse the direction of the all-points-follow displacement — points move opposite to the central anchor tear.")
        }
    }

    // MARK: - OCP (Outer Control Points)

    private func ocpContent(setIdx: Int, paramIdx: Int) -> some View {
        VStack(spacing: 0) {
            InspectorField("Probability") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.probability),
                                width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) this OCP group fires per polygon, in addition to the top-level PTP probability.")
            InspectorField("Line ratio X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.lineRatioX), width: 60)
            }
            .loomHelp("Base position of the outer handle along the edge on X (0 = start anchor, 1 = end anchor).")
            InspectorField("Line ratio Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.lineRatioY), width: 60)
            }
            .loomHelp("Base position of the outer handle along the edge on Y.")
            InspectorField("Ran ratio") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomLineRatio)).labelsHidden()
            }
            .loomHelp("Randomise handle positions using the Inner/Outer range below instead of the fixed Line ratios.")
            ptpFloatRangeField("Inner range", \.outerControlPoints.randomLineRatioInner,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max for random variation of the inner-side line ratio when Ran ratio is on.")
            ptpFloatRangeField("Outer range", \.outerControlPoints.randomLineRatioOuter,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max for random variation of the outer-side line ratio when Ran ratio is on.")
            InspectorField("Curve mode") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMode)) {
                    Text("Perpendicular").tag("PERPENDICULAR")
                    Text("From centre").tag("FROM_CENTRE")
                }
                .labelsHidden().frame(maxWidth: 120)
            }
            .loomHelp("Perpendicular — handles project at 90° to the edge; From centre — handles point away from the polygon centroid.")
            InspectorField("Curve type") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveType)) {
                    Text("Puff").tag("PUFF")
                    Text("Pinch").tag("PINCH")
                    Text("Puff-Pinch-Puff-Pinch").tag("PUFF_PINCH_PUFF_PINCH")
                    Text("Puff-Pinch-Pinch-Puff").tag("PUFF_PINCH_PINCH_PUFF")
                    Text("Pinch-Puff-Puff-Pinch").tag("PINCH_PUFF_PUFF_PINCH")
                    Text("Pinch-Puff-Pinch-Puff").tag("PINCH_PUFF_PINCH_PUFF")
                }
                .labelsHidden().frame(maxWidth: 130)
            }
            .loomHelp("Puff = edges bow outward; Pinch = inward. Alternating patterns (Puff-Pinch-…) create star or flower-like shapes.")
            InspectorField("Mult min") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMultiplierMin), width: 60)
            }
            .loomHelp("Minimum curvature multiplier — the lower bound when Ran mult is off. Higher values = more extreme bowing.")
            InspectorField("Mult max") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMultiplierMax), width: 60)
            }
            .loomHelp("Maximum curvature multiplier — used as the upper bound when Ran mult is on.")
            InspectorField("Ran mult") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomMultiplier)).labelsHidden()
            }
            .loomHelp("Randomise the curvature multiplier per edge within the Mult range below.")
            ptpFloatRangeField("Mult range", \.outerControlPoints.randomCurveMultiplier,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for the random curvature multiplier when Ran mult is on.")
            InspectorField("From ctr X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveFromCentreRatioX), width: 60)
            }
            .loomHelp("For From centre mode: X offset ratio placing the handle relative to the polygon centroid.")
            InspectorField("From ctr Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveFromCentreRatioY), width: 60)
            }
            .loomHelp("For From centre mode: Y offset ratio placing the handle relative to the polygon centroid.")
            InspectorField("Ran from ctr") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomFromCentre)).labelsHidden()
            }
            .loomHelp("Randomise the from-centre position using the A and B ranges below.")
            ptpFloatRangeField("From ctr A", \.outerControlPoints.randomFromCentreA,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("First random range for the from-centre handle position (typically X-side variation).")
            ptpFloatRangeField("From ctr B", \.outerControlPoints.randomFromCentreB,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Second random range for the from-centre handle position (typically Y-side variation).")
        }
    }

    // MARK: - ALC (Anchors Linked to Centre)

    private func alcContent(setIdx: Int, paramIdx: Int) -> some View {
        VStack(spacing: 0) {
            InspectorField("Probability") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.probability),
                                width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) this ALC group fires per polygon, in addition to the top-level PTP probability.")
            InspectorField("Tear factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.tearFactor), width: 60)
            }
            .loomHelp("Displacement magnitude for anchors geometrically linked to the polygon centre.")
            InspectorField("Tear type") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.tearType)) {
                    Text("Outside corner").tag("TOWARDS_OUTSIDE_CORNER")
                    Text("Opposite corner").tag("TOWARDS_OPPOSITE_CORNER")
                    Text("Towards centre").tag("TOWARDS_CENTRE")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 130)
            }
            .loomHelp("Target direction — Outside corner (nearest), Opposite corner (far), Towards centre (inward), or Random per anchor.")
            InspectorField("Ran tear") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.randomTear)).labelsHidden()
            }
            .loomHelp("Randomise tear magnitude within the Tear range below instead of using the fixed Tear factor.")
            ptpFloatRangeField("Tear range", \.anchorsLinkedToCentre.randomTearFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max tear factor sampled per polygon when Ran tear is on.")
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.cpsFollow)).labelsHidden()
            }
            .loomHelp("When on, control-point handles move with the torn anchor, preserving local curve shape.")
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.cpsFollowMultiplier), width: 60)
            }
            .loomHelp("Multiplier for how closely handles track the torn anchor. 1.0 = full follow.")
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.randomCpsFollow)).labelsHidden()
            }
            .loomHelp("Randomise the CP follow multiplier per polygon within the CPs fol rng below.")
            ptpFloatRangeField("CPs fol rng", \.anchorsLinkedToCentre.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for the random CP follow multiplier.")
        }
    }

    // MARK: - ICP (Inner Control Points)

    private func icpContent(setIdx: Int, paramIdx: Int) -> some View {
        VStack(spacing: 0) {
            InspectorField("Probability") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.probability),
                                width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Chance (0–100%) this ICP group fires per polygon, in addition to the top-level PTP probability.")
            InspectorField("Refer outer") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.innerControlPoints.referToOuter)) {
                    Text("None").tag("NONE")
                    Text("Follow").tag("FOLLOW")
                    Text("Exaggerate").tag("EXAGGERATE")
                    Text("Counter").tag("COUNTER")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            .loomHelp("How inner handles relate to OCP — None (independent), Follow (mirrors OCP offset), Exaggerate (amplifies it), Counter (opposes it).")
            InspectorField("Inner mult X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerMultiplierX), width: 60)
            }
            .loomHelp("Multiplier applied to the inward handle position on the X axis.")
            InspectorField("Inner mult Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerMultiplierY), width: 60)
            }
            .loomHelp("Multiplier applied to the inward handle position on the Y axis.")
            InspectorField("Outer mult X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerMultiplierX), width: 60)
            }
            .loomHelp("Multiplier applied to the outward handle position on the X axis.")
            InspectorField("Outer mult Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerMultiplierY), width: 60)
            }
            .loomHelp("Multiplier applied to the outward handle position on the Y axis.")
            InspectorField("Inner ratio") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerRatio), width: 60)
            }
            .loomHelp("Base ratio position for inner handles along the edge (0 = start anchor, 1 = end anchor).")
            InspectorField("Outer ratio") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerRatio), width: 60)
            }
            .loomHelp("Base ratio position for outer handles along the edge.")
            InspectorField("Ran ratio") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.innerControlPoints.randomRatio)).labelsHidden()
            }
            .loomHelp("Randomise inner and outer handle ratios using the Inner/Outer range below.")
            ptpFloatRangeField("Inner range", \.innerControlPoints.randomInnerRatio,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for random inner handle ratio when Ran ratio is on.")
            ptpFloatRangeField("Outer range", \.innerControlPoints.randomOuterRatio,
                                setIdx: setIdx, paramIdx: paramIdx)
            .loomHelp("Min/max range for random outer handle ratio when Ran ratio is on.")
            InspectorField("Common line") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.innerControlPoints.commonLine)) {
                    Text("Even").tag("EVEN")
                    Text("Odd").tag("ODD")
                    Text("Random").tag("RANDOM")
                    Text("None").tag("NONE")
                }
                .labelsHidden().frame(maxWidth: 90)
            }
            .loomHelp("Align handles on even, odd, or randomly chosen edges for a consistent curvature pattern; None disables alignment.")
        }
    }

    // MARK: - Shared field helpers

    private func vector2DField(
        _ label: String,
        xKP: WritableKeyPath<SubdivisionParams, Double>,
        yKP: WritableKeyPath<SubdivisionParams, Double>,
        setIdx: Int, paramIdx: Int,
        xLabel: String = "X", yLabel: String = "Y"
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text(xLabel).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                FloatEntryField(value: bindP(setIdx, paramIdx, xKP), width: 52, fontSize: 11)
                Text(yLabel).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                FloatEntryField(value: bindP(setIdx, paramIdx, yKP), width: 52, fontSize: 11)
            }
        }
    }

    private func ptpFloatRangeField(
        _ label: String,
        _ kp: WritableKeyPath<PTPTransformSet, FloatRange>,
        setIdx: Int, paramIdx: Int
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text("mn").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                FloatEntryField(value: bindPTP(setIdx, paramIdx, kp.appending(path: \.min)),
                                width: 46, fontSize: 11)
                Text("mx").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                FloatEntryField(value: bindPTP(setIdx, paramIdx, kp.appending(path: \.max)),
                                width: 46, fontSize: 11)
            }
        }
    }

    // MARK: - Binding helpers

    private func bindSet<T>(_ setIdx: Int, _ kp: WritableKeyPath<SubdivisionParamsSet, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SubdivisionParamsSet(name: "")[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig.paramsSets[safe: setIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindP<T>(_ setIdx: Int, _ paramIdx: Int,
                           _ kp: WritableKeyPath<SubdivisionParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SubdivisionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.params[safe: paramIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindPressureRandomGroup(_ setIdx: Int, _ paramIdx: Int, _ groupIndex: Int) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: {
                guard groupIndex >= 0, groupIndex < 5 else { return false }
                let groups = ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.params[safe: paramIdx]?.pressureRandomGroups ?? SubdivisionParams().pressureRandomGroups
                return SubdivisionParams.normalizedPressureRandomGroups(groups)[groupIndex]
            },
            set: { value in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count,
                          groupIndex >= 0, groupIndex < 5 else { return }
                    var groups = SubdivisionParams.normalizedPressureRandomGroups(
                        cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].pressureRandomGroups
                    )
                    groups[groupIndex] = value
                    cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].pressureRandomGroups =
                        SubdivisionParams.normalizedPressureRandomGroups(groups)
                }
            }
        )
    }

    // MARK: - Subdivision Drivers Section

    @ViewBuilder
    private func subdivisionDriversSection(param: SubdivisionParams,
                                            setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Subdivision Drivers", isCollapsed: $subdivDriversCollapsed) {
            Text("Generation drivers override static subdivision params each frame (split ratios, curves, inset scale/rotation). Per-polygon PTW drivers give each output polygon its own smooth, phase-staggered trajectory independent of the static PTW ranges.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)

            // MARK: Generation-level sub-section
            InspectorSection("Generation", isCollapsed: $subdivGenDriversCollapsed) {
                DoubleDriverEditor(
                    label: "Line Ratio",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.lineRatio),
                    isCollapsed: $lineRatioDriverCollapsed)
                .loomHelp("Overrides the edge split position (0–1). 0.5 = midpoint; lower values shift splits toward the start vertex. Drives both lineRatios.x and .y identically.")
                DoubleDriverEditor(
                    label: "CP Ratio",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.cpRatio),
                    isCollapsed: $cpRatioDriverCollapsed)
                .loomHelp("Overrides the Bézier control-point parametric position symmetrically: x = v, y = 1−v. At 0.5 both CPs land at the midpoint; values diverge from there.")
                DoubleDriverEditor(
                    label: "CP Normal",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.cpNormalOffset),
                    isCollapsed: $cpNormalDriverCollapsed)
                .loomHelp("Overrides the perpendicular bow offset on internal connector edges, driving CP1 and CP2 to the same value symmetrically. Positive/negative flips the bow direction. Has no effect unless a Quad-type algorithm is selected.")
                if param.subdivisionType.usesInsetTransform {
                    DoubleDriverEditor(
                        label: "Inset Scale",
                        driver: bindSubdivDriver(setIdx, paramIdx, \.insetScale),
                        isCollapsed: $insetScaleDriverCollapsed)
                    .loomHelp("Overrides the inset polygon scale uniformly (both axes). 1.0 = same size as parent; values below 1 shrink. Echo and Bord variants only.")
                    DoubleDriverEditor(
                        label: "Inset Rotation",
                        driver: bindSubdivDriver(setIdx, paramIdx, \.insetRotation),
                        isCollapsed: $insetRotDriverCollapsed)
                    .loomHelp("Overrides the inset polygon rotation in radians. Produces a spinning or counter-rotating inset effect. Echo and Bord variants only.")
                }
                DoubleDriverEditor(
                    label: "Ran Divisor",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.ranDiv),
                    isCollapsed: $ranDivDriverCollapsed)
                .loomHelp("Overrides the random centre-jitter divisor. Higher values = smaller jitter; lower values = more chaotic midpoint movement. Has effect only when Ran Middle is on.")
            }

            // MARK: Per-polygon PTW sub-section
            InspectorSection("Per-Polygon PTW", isCollapsed: $subdivPTWDriversCollapsed) {
                Text("Per-polygon motion. In oscillator mode, the Phase 0–1 field doubles as a spread range: small values (0.05–0.15) create a tight queue where all polygons move the same direction; larger values spread phases further apart.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
                DoubleDriverEditor(
                    label: "Translate X",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.ptwTranslateX),
                    isCollapsed: $ptwTXDriverCollapsed,
                    phaseModeBinding: bindSubdivPTWPhase(setIdx, paramIdx, \.ptwTranslateXPhase))
                .loomHelp("Per-polygon X displacement as a fraction of that polygon's bounding-box width. 0.5 = half a polygon-width right.")
                DoubleDriverEditor(
                    label: "Translate Y",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.ptwTranslateY),
                    isCollapsed: $ptwTYDriverCollapsed,
                    phaseModeBinding: bindSubdivPTWPhase(setIdx, paramIdx, \.ptwTranslateYPhase))
                .loomHelp("Per-polygon Y displacement as a fraction of that polygon's bounding-box height. 0.5 = half a polygon-height down.")
                DoubleDriverEditor(
                    label: "Scale",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.ptwScale),
                    isCollapsed: $ptwScaleDriverCollapsed,
                    phaseModeBinding: bindSubdivPTWPhase(setIdx, paramIdx, \.ptwScalePhase))
                .loomHelp("Per-polygon uniform scale multiplier around the polygon centroid. 1.0 = no change.")
                DoubleDriverEditor(
                    label: "Rotation",
                    driver: bindSubdivDriver(setIdx, paramIdx, \.ptwRotation),
                    isCollapsed: $ptwRotDriverCollapsed,
                    phaseModeBinding: bindSubdivPTWPhase(setIdx, paramIdx, \.ptwRotationPhase))
                .loomHelp("Per-polygon rotation in radians around the centroid.")
            }
        }
    }

    // MARK: - Binding helper: SubdivisionDrivers

    private func bindSubdivDriver(_ setIdx: Int, _ paramIdx: Int,
                                   _ kp: WritableKeyPath<SubdivisionDrivers, DoubleDriver>
    ) -> Binding<DoubleDriver> {
        let ctl = controller
        let fallback = SubdivisionDrivers()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.params[safe: paramIdx]?
                    .drivers?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count
                    else { return }
                    if cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].drivers == nil {
                        cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].drivers =
                            SubdivisionDrivers()
                    }
                    cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx]
                        .drivers![keyPath: kp] = v
                }
            }
        )
    }

    private func bindSubdivPTWPhase(_ setIdx: Int, _ paramIdx: Int,
                                     _ kp: WritableKeyPath<SubdivisionDrivers, PTWPhaseMode>
    ) -> Binding<PTWPhaseMode> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.params[safe: paramIdx]?
                    .drivers?[keyPath: kp] ?? .sequential
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count
                    else { return }
                    if cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].drivers == nil {
                        cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].drivers =
                            SubdivisionDrivers()
                    }
                    cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].drivers![keyPath: kp] = v
                }
            }
        )
    }

    private func bindPTP<T>(_ setIdx: Int, _ paramIdx: Int,
                              _ kp: WritableKeyPath<PTPTransformSet, T>) -> Binding<T> {
        let ctl = controller
        let fallback = PTPTransformSet()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.params[safe: paramIdx]?
                    .ptpTransformSet?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count else { return }
                    if cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].ptpTransformSet == nil {
                        cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].ptpTransformSet = PTPTransformSet()
                    }
                    cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx].ptpTransformSet![keyPath: kp] = v
                }
            }
        )
    }
}

// MARK: - PTP Tab enum

private enum PTPTab: String, CaseIterable {
    case exterior      = "Ext"
    case central       = "Cen"
    case outerCP       = "OCP"
    case anchorsLinked = "ALC"
    case innerCP       = "ICP"
}

// MARK: - SubdivisionType helpers

private extension SubdivisionType {
    var usesInsetTransform: Bool {
        switch self {
        case .echo, .echoAbsCenter,
             .quadBord, .quadBordEcho, .quadBordDouble, .quadBordDoubleEcho,
             .triBordA, .triBordAEcho, .triBordB, .triBordBEcho, .triBordC, .triBordCEcho:
            return true
        case .quad, .tri, .splitVert, .splitHoriz, .splitDiag, .triStar, .triStarFill, .custom:
            return false
        }
    }

    var shortName: String {
        switch self {
        case .quad:               return "Quad"
        case .quadBord:           return "QuadBord"
        case .quadBordEcho:       return "QuadBordEcho"
        case .quadBordDouble:     return "QuadBordDbl"
        case .quadBordDoubleEcho: return "QuadBordDblEcho"
        case .tri:                return "Tri"
        case .triBordA:           return "TriBordA"
        case .triBordAEcho:       return "TriBordAEcho"
        case .triBordB:           return "TriBordB"
        case .triBordBEcho:       return "TriBordBEcho"
        case .triBordC:           return "TriBordC"
        case .triBordCEcho:       return "TriBordCEcho"
        case .triStar:            return "TriStar"
        case .triStarFill:        return "TriStarFill"
        case .splitVert:          return "SplitVert"
        case .splitHoriz:         return "SplitHoriz"
        case .splitDiag:          return "SplitDiag"
        case .echo:               return "Echo"
        case .echoAbsCenter:      return "EchoAbsCenter"
        case .custom:             return "Custom…"
        }
    }
}

private extension VisibilityRule {
    var shortName: String {
        switch self {
        case .all:           return "All"
        case .quads:         return "Quads"
        case .tris:          return "Tris"
        case .allButLast:    return "AllButLast"
        case .alternateOdd:  return "AltOdd"
        case .alternateEven: return "AltEven"
        case .firstHalf:     return "FirstHalf"
        case .secondHalf:    return "SecondHalf"
        case .everyThird:    return "Every3rd"
        case .everyFourth:   return "Every4th"
        case .everyFifth:    return "Every5th"
        case .random1in2:    return "Ran1in2"
        case .random1in3:    return "Ran1in3"
        case .random1in5:    return "Ran1in5"
        case .random1in7:    return "Ran1in7"
        case .random1in10:   return "Ran1in10"
        }
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
