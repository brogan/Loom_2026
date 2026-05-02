import SwiftUI
import LoomEngine

struct SubdivisionInspector: View {

    @EnvironmentObject private var controller: AppController
    @State private var activePTPTab: PTPTab = .exterior
    @State private var generalCollapsed  = false
    @State private var insetCollapsed    = false
    @State private var ptwCollapsed      = false
    @State private var ptpCollapsed      = false

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
        if param.subdivisionType.usesInsetTransform {
            insetSection(setIdx: setIdx, paramIdx: paramIdx)
        }
        ptwSection(setIdx: setIdx, paramIdx: paramIdx)
        ptpSection(setIdx: setIdx, paramIdx: paramIdx)
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
            InspectorField("Algorithm") {
                Picker("", selection: bindP(setIdx, paramIdx, \.subdivisionType)) {
                    ForEach(SubdivisionType.allCases, id: \.self) { t in
                        Text(t.shortName).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            vector2DField("Line ratios", xKP: \.lineRatios.x, yKP: \.lineRatios.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            vector2DField("CP ratios", xKP: \.controlPointRatios.x, yKP: \.controlPointRatios.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("Continuous") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.continuous)).labelsHidden()
            }
            InspectorField("Visibility") {
                Picker("", selection: bindP(setIdx, paramIdx, \.visibilityRule)) {
                    ForEach(VisibilityRule.allCases, id: \.self) { r in
                        Text(r.shortName).tag(r)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            InspectorField("Ran middle") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.ranMiddle)).labelsHidden()
            }
            InspectorField("Ran divisor") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.ranDiv), width: 60, fractionDigits: 1)
            }
        }
    }

    // MARK: - Inset Transform (echo / bord types only)

    private func insetSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Inset Transform", isCollapsed: $insetCollapsed) {
            vector2DField("Scale",
                          xKP: \.insetTransform.scale.x, yKP: \.insetTransform.scale.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            vector2DField("Translate",
                          xKP: \.insetTransform.translation.x, yKP: \.insetTransform.translation.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("Rotation") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.insetTransform.rotation),
                                width: 80, fractionDigits: 4)
                Text("rad").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - PTW

    private func ptwSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("PTW", isCollapsed: $ptwCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTransform)).labelsHidden()
            }
            InspectorField("Whole") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTranformWhole)).labelsHidden()
            }
            InspectorField("Probability") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.pTW_probability), width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Common ctr") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_commonCentre)).labelsHidden()
            }
            InspectorField("Ran transl") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomTranslation)).labelsHidden()
            }
            InspectorField("Ran scale") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomScale)).labelsHidden()
            }
            InspectorField("Ran rotate") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.pTW_randomRotation)).labelsHidden()
            }
            vector2DField("Transl X",
                          xKP: \.pTW_randomTranslationRange.x.min,
                          yKP: \.pTW_randomTranslationRange.x.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            vector2DField("Transl Y",
                          xKP: \.pTW_randomTranslationRange.y.min,
                          yKP: \.pTW_randomTranslationRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            vector2DField("Scale X",
                          xKP: \.pTW_randomScaleRange.x.min,
                          yKP: \.pTW_randomScaleRange.x.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            vector2DField("Scale Y",
                          xKP: \.pTW_randomScaleRange.y.min,
                          yKP: \.pTW_randomScaleRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
            vector2DField("Rot range",
                          xKP: \.pTW_randomRotationRange.min,
                          yKP: \.pTW_randomRotationRange.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "mn", yLabel: "mx")
        }
    }

    // MARK: - PTP Section

    private func ptpSection(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("PTP", isCollapsed: $ptpCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTransformPoints)).labelsHidden()
            }
            InspectorField("Probability") {
                FloatEntryField(value: bindP(setIdx, paramIdx, \.pTP_probability), width: 50, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ptpTabBar()
            ptpEnabledSummary(setIdx: setIdx, paramIdx: paramIdx)
            ptpTabContent(setIdx: setIdx, paramIdx: paramIdx)
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
            InspectorField("Spike factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeFactor), width: 60)
            }
            InspectorField("Which spike") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.whichSpike)) {
                    Text("All").tag("ALL")
                    Text("Corners").tag("CORNERS")
                    Text("Middles").tag("MIDDLES")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            InspectorField("Spike type") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeType)) {
                    Text("Symmetrical").tag("SYMMETRICAL")
                    Text("Right").tag("RIGHT")
                    Text("Left").tag("LEFT")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            InspectorField("Spike axis") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.exteriorAnchors.spikeAxis)) {
                    Text("XY").tag("XY")
                    Text("X").tag("X")
                    Text("Y").tag("Y")
                }
                .labelsHidden().frame(maxWidth: 80)
            }
            InspectorField("Ran spike") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomSpike)).labelsHidden()
            }
            ptpFloatRangeField("Spike range", \.exteriorAnchors.randomSpikeFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsFollow)).labelsHidden()
            }
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsFollowMultiplier), width: 60)
            }
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomCpsFollow)).labelsHidden()
            }
            ptpFloatRangeField("CPs fol rng", \.exteriorAnchors.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("CPs squeeze") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsSqueeze)).labelsHidden()
            }
            InspectorField("Squeeze fact") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.exteriorAnchors.cpsSqueezeFactor), width: 60)
            }
            InspectorField("Ran squeeze") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.exteriorAnchors.randomCpsSqueeze)).labelsHidden()
            }
            ptpFloatRangeField("Squeeze rng", \.exteriorAnchors.randomCpsSqueezeRange,
                                setIdx: setIdx, paramIdx: paramIdx)
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
            InspectorField("Tear factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.centralAnchors.tearFactor), width: 60)
            }
            InspectorField("Tear axis") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.centralAnchors.tearAxis)) {
                    Text("XY").tag("XY")
                    Text("X").tag("X")
                    Text("Y").tag("Y")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 90)
            }
            InspectorField("Tear dir") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.centralAnchors.tearDirection)) {
                    Text("Diagonal").tag("DIAGONAL")
                    Text("Left").tag("LEFT")
                    Text("Right").tag("RIGHT")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 100)
            }
            InspectorField("Ran tear") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.randomTear)).labelsHidden()
            }
            ptpFloatRangeField("Tear range", \.centralAnchors.randomTearFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.cpsFollow)).labelsHidden()
            }
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.centralAnchors.cpsFollowMultiplier), width: 60)
            }
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.randomCpsFollow)).labelsHidden()
            }
            ptpFloatRangeField("CPs fol rng", \.centralAnchors.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("All pts fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.allPointsFollow)).labelsHidden()
            }
            InspectorField("Inverted fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.centralAnchors.invertedFollow)).labelsHidden()
            }
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
            InspectorField("Line ratio X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.lineRatioX), width: 60)
            }
            InspectorField("Line ratio Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.lineRatioY), width: 60)
            }
            InspectorField("Ran ratio") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomLineRatio)).labelsHidden()
            }
            ptpFloatRangeField("Inner range", \.outerControlPoints.randomLineRatioInner,
                                setIdx: setIdx, paramIdx: paramIdx)
            ptpFloatRangeField("Outer range", \.outerControlPoints.randomLineRatioOuter,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("Curve mode") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMode)) {
                    Text("Perpendicular").tag("PERPENDICULAR")
                    Text("From centre").tag("FROM_CENTRE")
                }
                .labelsHidden().frame(maxWidth: 120)
            }
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
            InspectorField("Mult min") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMultiplierMin), width: 60)
            }
            InspectorField("Mult max") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveMultiplierMax), width: 60)
            }
            InspectorField("Ran mult") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomMultiplier)).labelsHidden()
            }
            ptpFloatRangeField("Mult range", \.outerControlPoints.randomCurveMultiplier,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("From ctr X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveFromCentreRatioX), width: 60)
            }
            InspectorField("From ctr Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.outerControlPoints.curveFromCentreRatioY), width: 60)
            }
            InspectorField("Ran from ctr") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.outerControlPoints.randomFromCentre)).labelsHidden()
            }
            ptpFloatRangeField("From ctr A", \.outerControlPoints.randomFromCentreA,
                                setIdx: setIdx, paramIdx: paramIdx)
            ptpFloatRangeField("From ctr B", \.outerControlPoints.randomFromCentreB,
                                setIdx: setIdx, paramIdx: paramIdx)
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
            InspectorField("Tear factor") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.tearFactor), width: 60)
            }
            InspectorField("Tear type") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.tearType)) {
                    Text("Outside corner").tag("TOWARDS_OUTSIDE_CORNER")
                    Text("Opposite corner").tag("TOWARDS_OPPOSITE_CORNER")
                    Text("Towards centre").tag("TOWARDS_CENTRE")
                    Text("Random").tag("RANDOM")
                }
                .labelsHidden().frame(maxWidth: 130)
            }
            InspectorField("Ran tear") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.randomTear)).labelsHidden()
            }
            ptpFloatRangeField("Tear range", \.anchorsLinkedToCentre.randomTearFactor,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("CPs follow") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.cpsFollow)).labelsHidden()
            }
            InspectorField("CPs mult") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.cpsFollowMultiplier), width: 60)
            }
            InspectorField("Ran CPs fol") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.anchorsLinkedToCentre.randomCpsFollow)).labelsHidden()
            }
            ptpFloatRangeField("CPs fol rng", \.anchorsLinkedToCentre.randomCpsFollowRange,
                                setIdx: setIdx, paramIdx: paramIdx)
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
            InspectorField("Refer outer") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.innerControlPoints.referToOuter)) {
                    Text("None").tag("NONE")
                    Text("Follow").tag("FOLLOW")
                    Text("Exaggerate").tag("EXAGGERATE")
                    Text("Counter").tag("COUNTER")
                }
                .labelsHidden().frame(maxWidth: 110)
            }
            InspectorField("Inner mult X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerMultiplierX), width: 60)
            }
            InspectorField("Inner mult Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerMultiplierY), width: 60)
            }
            InspectorField("Outer mult X") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerMultiplierX), width: 60)
            }
            InspectorField("Outer mult Y") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerMultiplierY), width: 60)
            }
            InspectorField("Inner ratio") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.innerRatio), width: 60)
            }
            InspectorField("Outer ratio") {
                FloatEntryField(value: bindPTP(setIdx, paramIdx, \.innerControlPoints.outerRatio), width: 60)
            }
            InspectorField("Ran ratio") {
                Toggle("", isOn: bindPTP(setIdx, paramIdx, \.innerControlPoints.randomRatio)).labelsHidden()
            }
            ptpFloatRangeField("Inner range", \.innerControlPoints.randomInnerRatio,
                                setIdx: setIdx, paramIdx: paramIdx)
            ptpFloatRangeField("Outer range", \.innerControlPoints.randomOuterRatio,
                                setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("Common line") {
                Picker("", selection: bindPTP(setIdx, paramIdx, \.innerControlPoints.commonLine)) {
                    Text("Even").tag("EVEN")
                    Text("Odd").tag("ODD")
                    Text("Random").tag("RANDOM")
                    Text("None").tag("NONE")
                }
                .labelsHidden().frame(maxWidth: 90)
            }
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
        case .quad, .tri, .splitVert, .splitHoriz, .splitDiag, .triStar, .triStarFill:
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
