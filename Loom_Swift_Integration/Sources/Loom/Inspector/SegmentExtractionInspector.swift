import SwiftUI
import LoomEngine

/// Inspector for a single `SegmentExtractionParams` pass.
/// Embedded in `SubdivisionInspector` when a segment extraction param is selected.
struct SegmentExtractionInspector: View {

    @EnvironmentObject private var controller: AppController

    let setIdx: Int
    let seIdx:  Int

    @AppStorage("seinsp.generalCollapsed") private var generalCollapsed  = false
    @AppStorage("seinsp.modeCollapsed")    private var modeCollapsed     = false
    @AppStorage("seinsp.driverCollapsed")  private var driverCollapsed   = true

    var body: some View {
        generalSection
        modeSection
        driversSection
    }

    // MARK: - General

    private var generalSection: some View {
        InspectorSection("General", isCollapsed: $generalCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindSE(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Enabled") {
                Toggle("", isOn: bindSE(\.enabled)).labelsHidden()
            }
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        InspectorSection("Extraction", isCollapsed: $modeCollapsed) {
            InspectorField("Mode") {
                Picker("", selection: bindSE(\.mode)) {
                    ForEach(SegmentExtractionMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .loomHelp("All: every segment becomes a separate open curve. Alternate: every other segment extracted (others dropped). Driven: a DoubleDriver controls what fraction of segments are extracted from the start of the curve — at 0 the curve is intact, at 1 all segments are extracted.")

            if bindSE(\.mode).wrappedValue == .alternate {
                InspectorField("Offset") {
                    Toggle("Skip first", isOn: bindSE(\.alternateOffset)).labelsHidden()
                    Text("Skip first")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .loomHelp("When on, extraction starts at segment index 1 instead of 0 — shifts which segments are selected.")
            }
        }
    }

    // MARK: - Driver (Driven mode only)

    @ViewBuilder
    private var driversSection: some View {
        if bindSE(\.mode).wrappedValue == .driven {
            DoubleDriverEditor(
                label: "Extraction fraction",
                driver: bindSEDriver(),
                isCollapsed: $driverCollapsed
            )
        }
    }

    // MARK: - Binding helpers

    private func bindSE<T>(_ kp: WritableKeyPath<SegmentExtractionParams, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SegmentExtractionParams()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.segmentExtraction[safe: seIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          seIdx  < cfg.subdivisionConfig.paramsSets[setIdx].segmentExtraction.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].segmentExtraction[seIdx][keyPath: kp] = v
                }
            }
        )
    }

    private func bindSEDriver() -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.subdivisionConfig
                    .paramsSets[safe: setIdx]?.segmentExtraction[safe: seIdx]?.driver ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.subdivisionConfig.paramsSets.count,
                          seIdx  < cfg.subdivisionConfig.paramsSets[setIdx].segmentExtraction.count
                    else { return }
                    cfg.subdivisionConfig.paramsSets[setIdx].segmentExtraction[seIdx].driver = v
                }
            }
        )
    }
}
