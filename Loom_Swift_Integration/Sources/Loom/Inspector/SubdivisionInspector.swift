import SwiftUI
import LoomEngine

struct SubdivisionInspector: View {

    @EnvironmentObject private var controller: AppController

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
    private func paramEditor(param: SubdivisionParams,
                              setIdx: Int, paramIdx: Int) -> some View {
        generalTab(setIdx: setIdx, paramIdx: paramIdx)
        insetTab(setIdx: setIdx, paramIdx: paramIdx)
        ptwTab(setIdx: setIdx, paramIdx: paramIdx)
    }

    // MARK: - General

    private func generalTab(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("General") {
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
            vector2DField("Line ratios",   xKP: \.lineRatios.x, yKP: \.lineRatios.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            vector2DField("CP ratios",     xKP: \.controlPointRatios.x, yKP: \.controlPointRatios.y,
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
                TextField("", value: bindP(setIdx, paramIdx, \.ranDiv),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
            }
        }
    }

    // MARK: - Inset transform

    private func insetTab(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("Inset Transform") {
            vector2DField("Scale",  xKP: \.insetTransform.scale.x,       yKP: \.insetTransform.scale.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            vector2DField("Translate", xKP: \.insetTransform.translation.x, yKP: \.insetTransform.translation.y,
                          setIdx: setIdx, paramIdx: paramIdx)
            InspectorField("Rotation") {
                TextField("", value: bindP(setIdx, paramIdx, \.insetTransform.rotation),
                          format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 80)
                Text("rad").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - PTW (poly transform whole)

    private func ptwTab(setIdx: Int, paramIdx: Int) -> some View {
        InspectorSection("PTW") {
            InspectorField("Enabled") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTransform)).labelsHidden()
            }
            InspectorField("Whole") {
                Toggle("", isOn: bindP(setIdx, paramIdx, \.polysTranformWhole)).labelsHidden()
            }
            InspectorField("Probability") {
                TextField("", value: bindP(setIdx, paramIdx, \.pTW_probability),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
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
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "min", yLabel: "max")
            vector2DField("Transl Y",
                          xKP: \.pTW_randomTranslationRange.y.min,
                          yKP: \.pTW_randomTranslationRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "min", yLabel: "max")
            vector2DField("Scale X",
                          xKP: \.pTW_randomScaleRange.x.min,
                          yKP: \.pTW_randomScaleRange.x.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "min", yLabel: "max")
            vector2DField("Scale Y",
                          xKP: \.pTW_randomScaleRange.y.min,
                          yKP: \.pTW_randomScaleRange.y.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "min", yLabel: "max")
            vector2DField("Rot range",
                          xKP: \.pTW_randomRotationRange.min,
                          yKP: \.pTW_randomRotationRange.max,
                          setIdx: setIdx, paramIdx: paramIdx, xLabel: "min", yLabel: "max")
        }
    }

    // MARK: - Shared vector field helper

    private func vector2DField(
        _ label: String,
        xKP: WritableKeyPath<SubdivisionParams, Double>,
        yKP: WritableKeyPath<SubdivisionParams, Double>,
        setIdx: Int, paramIdx: Int,
        xLabel: String = "X", yLabel: String = "Y"
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text(xLabel).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 12)
                TextField("", value: bindP(setIdx, paramIdx, xKP),
                          format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 52)
                Text(yLabel).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 12)
                TextField("", value: bindP(setIdx, paramIdx, yKP),
                          format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 52)
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
}

// MARK: - Display names

private extension SubdivisionType {
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
