import SwiftUI
import LoomEngine

/// Inspector for a single `ConvolutionParams` pass.
/// Embedded in `SubdivisionInspector` when a convolution param is selected.
struct ConvolutionInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let convIdx: Int

    @AppStorage("convinsp.generalCollapsed") private var generalCollapsed = false
    @AppStorage("convinsp.opCollapsed")      private var opCollapsed      = false
    @AppStorage("convinsp.torsionCollapsed") private var torsionCollapsed = false
    @AppStorage("convinsp.shearCollapsed")   private var shearCollapsed   = false
    @AppStorage("convinsp.twistAmountCollapsed") private var twistAmountCollapsed = true
    @AppStorage("convinsp.shearAmountCollapsed") private var shearAmountCollapsed = true

    var body: some View {
        generalSection
        operationSection
        if bindConv(\.operationType).wrappedValue == .torsion {
            torsionSection
            twistAmountDriverSection
        } else {
            shearSection
            shearAmountDriverSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindConv(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindConv(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Operation type

    private var operationSection: some View {
        InspectorSection("Operation", isCollapsed: $opCollapsed) {
            InspectorField("Type") {
                Picker("", selection: bindConv(\.operationType)) {
                    ForEach(ConvolutionOperationType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .loomHelp("Torsion: rotate points around a centre by an angle that varies with distance from it — a spiral warp. Shear: displace points along an axis proportional to their distance from it. Applies unconditionally to both open curves and closed polygons. Add another Convolution pass to combine Torsion and Shear — order follows pass-list order.")
        }
    }

    // MARK: - Torsion settings

    private var torsionSection: some View {
        InspectorSection("Torsion", isCollapsed: $torsionCollapsed) {
            InspectorField("Centre") {
                Picker("", selection: bindConv(\.twistCentre)) {
                    ForEach(ConvolutionCentre.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            .loomHelp("Centroid: average of all points (works for both open curves and closed polygons). Bounding Box Centre: geometric centre of the point list's bounding box — differs from Centroid when points are unevenly distributed. Custom: a fixed canvas point below.")

            if bindConv(\.twistCentre).wrappedValue == .custom {
                InspectorField("Centre X") {
                    FloatEntryField(value: bindConv(\.twistCentreCustomX), width: 60)
                }
                InspectorField("Centre Y") {
                    FloatEntryField(value: bindConv(\.twistCentreCustomY), width: 60)
                }
            }

            InspectorField("Falloff") {
                Picker("", selection: bindConv(\.twistFalloff)) {
                    ForEach(ConvolutionTwistFalloff.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            .loomHelp("Linear: angle grows with distance from centre, unbounded — the classic spiral/pinwheel twist. Inverse: angle is strongest near the centre and fades outward, never exceeding the driven amount — a gentler, localized torsion. Constant: every point rotates by the same angle regardless of distance — a plain rigid rotation of the whole shape (already available at the sprite level), kept here as a labelled corner case.")

            InspectorField("Reference radius") {
                FloatEntryField(value: bindConv(\.twistReferenceRadius), width: 60)
            }
            .loomHelp("Canvas-unit distance from centre at which the driven twist amount applies at full strength. Normalizes Linear/Inverse falloff so the same amount value behaves consistently regardless of the shape's absolute size.")
        }
    }

    @ViewBuilder
    private var twistAmountDriverSection: some View {
        DoubleDriverEditor(
            label: "Twist amount",
            driver: bindConvDriver(\.twistAmount),
            isCollapsed: $twistAmountCollapsed
        )
        .loomHelp("Rotation in degrees at Reference radius. Wire an Oscillator for a shape that twists back and forth, a slow Noise driver for organic torsional drift, or a Keyframe ramp to untwist over time.")
        .padding(.bottom, 2)
    }

    // MARK: - Shear settings

    private var shearSection: some View {
        InspectorSection("Shear", isCollapsed: $shearCollapsed) {
            InspectorField("Axis") {
                FloatEntryField(value: bindConv(\.shearAxis), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Direction of the shear axis in degrees. 0° = classic horizontal shear (points displace sideways based on their vertical distance from Origin). 90° = vertical shear.")

            InspectorField("Origin") {
                Picker("", selection: bindConv(\.shearOrigin)) {
                    ForEach(ConvolutionCentre.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            .loomHelp("The axis passes through this point. Centroid: average of all points. Bounding Box Centre: geometric centre of the point list's bounding box. Custom: a fixed canvas point below.")

            if bindConv(\.shearOrigin).wrappedValue == .custom {
                InspectorField("Origin X") {
                    FloatEntryField(value: bindConv(\.shearOriginCustomX), width: 60)
                }
                InspectorField("Origin Y") {
                    FloatEntryField(value: bindConv(\.shearOriginCustomY), width: 60)
                }
            }
        }
    }

    @ViewBuilder
    private var shearAmountDriverSection: some View {
        DoubleDriverEditor(
            label: "Shear amount",
            driver: bindConvDriver(\.shearAmount),
            isCollapsed: $shearAmountCollapsed
        )
        .loomHelp("Displacement per unit distance from Origin along the perpendicular of Axis. 0 = no shear. Positive and negative values shear in opposite directions. Shear is an affine transform, so this is geometrically exact — not an approximation, unlike Torsion.")
        .padding(.bottom, 2)
    }

    // MARK: - Binding helpers

    private func bindConv<T>(_ kp: WritableKeyPath<ConvolutionParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = ConvolutionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.convolutionPasses[safe: convIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx  < cfg.subdivisionConfig.paramsSets.count,
                          convIdx < cfg.subdivisionConfig.paramsSets[setIdx].convolutionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].convolutionPasses[convIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindConvDriver(_ kp: WritableKeyPath<ConvolutionParams, DoubleDriver>) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.convolutionPasses[safe: convIdx]?[keyPath: kp] ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx  < cfg.subdivisionConfig.paramsSets.count,
                          convIdx < cfg.subdivisionConfig.paramsSets[setIdx].convolutionPasses.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].convolutionPasses[convIdx][keyPath: kp] = v
                }
            }
        )
    }
}
