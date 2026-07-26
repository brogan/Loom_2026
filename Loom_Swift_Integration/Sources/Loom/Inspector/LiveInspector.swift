import SwiftUI
import LoomEngine

/// Right-panel inspector for the Live tab's currently selected staged
/// sprite: renderer-set / transform-set assignment (instant, non-driver
/// swap) plus the 9 `TransformDrivers` on/off toggles — `LoomLiveV1Scope.md` §2.1.
struct LiveInspector: View {

    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var liveController: LiveSessionController

    private var selectedStaged: LiveSessionController.StagedSprite? {
        guard let id = liveController.selectedStagedID else { return nil }
        return liveController.stagedSprites.first(where: { $0.id == id })
    }

    private var rendererSetNames: [String] {
        controller.projectConfig?.renderingConfig.library.rendererSets.map(\.name) ?? []
    }

    private var subdivisionSetNames: [String] {
        controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? []
    }

    var body: some View {
        if let staged = selectedStaged {
            VStack(alignment: .leading, spacing: 12) {
                Text(staged.spriteDefName)
                    .font(.system(size: 13, weight: .semibold))

                setsSection(staged)

                Divider()

                driversSection(staged)

                Spacer()
            }
            .padding(12)
        } else {
            Text("Stage a sprite to configure it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    // MARK: - Set assignment

    private func setsSection(_ staged: LiveSessionController.StagedSprite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Renderer").font(.system(size: 11)).frame(width: 90, alignment: .leading)
                Picker("", selection: Binding(
                    get: { staged.rendererSetName ?? "" },
                    set: { liveController.assignRendererSet(staged.id, name: $0) }
                )) {
                    Text("—").tag("")
                    ForEach(rendererSetNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            HStack {
                Text("Transform").font(.system(size: 11)).frame(width: 90, alignment: .leading)
                Picker("", selection: Binding(
                    get: { staged.subdivisionSetName ?? "" },
                    set: { liveController.assignSubdivisionSet(staged.id, name: $0) }
                )) {
                    Text("—").tag("")
                    ForEach(subdivisionSetNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Driver toggles

    private func driversSection(_ staged: LiveSessionController.StagedSprite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drivers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(LiveDriverKey.allCases, id: \.self) { key in
                Toggle(key.rawValue, isOn: Binding(
                    get: { staged.driverEnabled[key] ?? false },
                    set: { liveController.toggleDriver(staged.id, key, $0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }
        }
    }
}
