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
    @AppStorage("convinsp.bendCollapsed")        private var bendCollapsed        = false
    @AppStorage("convinsp.bendCurvatureCollapsed") private var bendCurvatureCollapsed = true
    @AppStorage("convinsp.displacementCollapsed")      private var displacementCollapsed      = false
    @AppStorage("convinsp.displacementStrengthCollapsed") private var displacementStrengthCollapsed = true
    @AppStorage("convinsp.displacementScrollCollapsed")   private var displacementScrollCollapsed   = true

    var body: some View {
        generalSection
        operationSection
        switch bindConv(\.operationType).wrappedValue {
        case .torsion:
            torsionSection
            twistAmountDriverSection
        case .shear:
            shearSection
            shearAmountDriverSection
        case .bend:
            bendSection
            bendCurvatureDriverSection
        case .displacementMap:
            displacementMapSection
            displacementStrengthDriverSection
            displacementScrollRateDriverSection
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
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }
            .loomHelp("Torsion: rotate points around a centre by an angle that varies with distance from it — a spiral warp. Shear: displace points along an axis proportional to their distance from it. Bend: wrap the shape around a virtual circular arc, like a 3D bend deformer. Displacement Map: sample a greyscale image to displace points, optionally scrolling across the shape over time. Applies unconditionally to both open curves and closed polygons. Add another Convolution pass to combine operations — order follows pass-list order.")
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

    // MARK: - Bend settings

    private var bendSection: some View {
        InspectorSection("Bend", isCollapsed: $bendCollapsed) {
            InspectorField("Axis") {
                FloatEntryField(value: bindConv(\.bendAxis), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Direction of the \"along\" bend axis in degrees. 0° bends left-to-right; 90° bends bottom-to-top. Points are carried along a virtual arc in this direction; cross-sections perpendicular to it stay rigid rather than shearing.")

            InspectorField("Centre") {
                Picker("", selection: bindConv(\.bendCentre)) {
                    ForEach(ConvolutionCentre.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            .loomHelp("The reference point the bend axis passes through. Centroid: average of all points. Bounding Box Centre: geometric centre of the point list's bounding box. Custom: a fixed canvas point below.")

            if bindConv(\.bendCentre).wrappedValue == .custom {
                InspectorField("Centre X") {
                    FloatEntryField(value: bindConv(\.bendCentreCustomX), width: 60)
                }
                InspectorField("Centre Y") {
                    FloatEntryField(value: bindConv(\.bendCentreCustomY), width: 60)
                }
            }

            InspectorField("Origin") {
                FloatEntryField(value: bindConv(\.bendOrigin), width: 60)
            }
            .loomHelp("0–1 position along the shape's own extent on Axis where the bend is centred. 0.5 (default) bends symmetrically outward from the middle — the shape's centre point on the axis stays fixed. 0 or 1 pins one end instead, so the whole shape sweeps around from that end.")
        }
    }

    @ViewBuilder
    private var bendCurvatureDriverSection: some View {
        DoubleDriverEditor(
            label: "Curvature",
            driver: bindConvDriver(\.bendCurvature),
            isCollapsed: $bendCurvatureCollapsed
        )
        .loomHelp("Inverse radius of the virtual bend circle. 0 = straight, no bend. 1.0 gives a gentle, readable curve for typically-sized geometry. Wire an Oscillator for a shape that flexes back and forth, or a Keyframe ramp to bend in gradually over time.")
        .padding(.bottom, 2)
    }

    // MARK: - Displacement Map settings

    private var displacementMapSection: some View {
        InspectorSection("Displacement Map", isCollapsed: $displacementCollapsed) {
            let files = displacementMapFiles()
            InspectorField("Map") {
                Picker("", selection: bindConv(\.displacementMapName)) {
                    Text("None").tag("")
                    ForEach(files, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12))
                .frame(maxWidth: 150)
            }
            .loomHelp("Greyscale image from the project's displacementMaps/ folder. Mid-grey = no displacement; black and white push in opposite directions. Add image files to that folder (Finder, or Reveal from the Global tab) to make them available here.")

            InspectorField("Invert") {
                Toggle("", isOn: bindConv(\.displacementInvert)).labelsHidden()
            }
            .loomHelp("Flips the map's brightness (black becomes white and vice versa) before displacing — swaps which areas push the shape which way.")

            InspectorField("Wrap") {
                Toggle("", isOn: bindConv(\.displacementWrap)).labelsHidden()
            }
            .loomHelp("On (default): the map tiles seamlessly, repeating indefinitely — right for a repeating texture or a pattern that scrolls across the shape. Off: the map is placed exactly once, positioned by Centre/Offset; anywhere outside that single tile gets zero displacement instead of a repeated copy — right for one decorative feature (e.g. a single ring-and-dot motif) rather than a tiling texture.")

            InspectorField("Axis") {
                FloatEntryField(value: bindConv(\.displacementAxis), width: 60)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Direction the map's sampling frame is oriented, and the axis it scrolls along. Points displace perpendicular to this axis — 0° scrolls the map horizontally and displaces points vertically, like a wave rolling across the shape left-to-right.")

            InspectorField("Centre") {
                Picker("", selection: bindConv(\.displacementCentre)) {
                    ForEach(ConvolutionCentre.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }
            .loomHelp("Reference point the map's sampling frame is anchored to. Centroid: average of all points. Bounding Box Centre: geometric centre of the point list's bounding box. Custom: a fixed canvas point below.")

            if bindConv(\.displacementCentre).wrappedValue == .custom {
                InspectorField("Centre X") {
                    FloatEntryField(value: bindConv(\.displacementCentreCustomX), width: 60)
                }
                InspectorField("Centre Y") {
                    FloatEntryField(value: bindConv(\.displacementCentreCustomY), width: 60)
                }
            }

            InspectorField("Scale") {
                FloatEntryField(value: bindConv(\.displacementScale), width: 60)
            }
            .loomHelp("Canvas units spanned by one full tile of the map along Axis. Smaller values repeat the pattern more densely across the shape; larger values show less of the pattern's own detail per shape-width.")

            InspectorField("Offset X") {
                FloatEntryField(value: bindConv(\.displacementOffsetU), width: 60)
            }
            .loomHelp("Which part of the map lands at Centre, along Axis (0–1 fraction of one tile, wraps like Scroll rate). Default 0.5 centres the map's own middle on Centre. Adjust to reposition a specific feature of the map — e.g. a dot or ring — over the shape's centre.")

            InspectorField("Offset Y") {
                FloatEntryField(value: bindConv(\.displacementOffsetV), width: 60)
            }
            .loomHelp("Same as Offset X, perpendicular to Axis. Static only — unlike Offset X, this never scrolls automatically.")
        }
    }

    @ViewBuilder
    private var displacementStrengthDriverSection: some View {
        DoubleDriverEditor(
            label: "Strength",
            driver: bindConvDriver(\.displacementStrength),
            isCollapsed: $displacementStrengthCollapsed
        )
        .loomHelp("Depth of displacement, in canvas units, at full (white or black) brightness. Wire a Keyframe ramp from 0 to animate from the original geometry into the fully displaced version.")
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var displacementScrollRateDriverSection: some View {
        DoubleDriverEditor(
            label: "Scroll rate",
            driver: bindConvDriver(\.displacementScrollRate),
            isCollapsed: $displacementScrollCollapsed
        )
        .loomHelp("Cycles per second the map scrolls along Axis. 0 = static, no scrolling. The map tiles seamlessly, so any nonzero rate lets the pattern pass across the shape indefinitely — the same value keeps producing new deformation rather than looping back identically (unless the underlying map itself repeats).")
        .padding(.bottom, 2)
    }

    private func displacementMapFiles() -> [String] {
        guard let url = controller.projectURL else { return [] }
        let dir = url.appendingPathComponent("displacementMaps")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        let supported: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif"]
        return entries
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
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
