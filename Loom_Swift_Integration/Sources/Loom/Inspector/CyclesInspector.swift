import SwiftUI
import LoomEngine

struct CyclesInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        guard let idx = controller.selectedCycleIndex,
              let cycles = controller.projectConfig?.cycles,
              cycles.indices.contains(idx)
        else {
            return AnyView(
                Text("Select a cycle to inspect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        let cycle = cycles[idx]

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            InspectorSection("Cycle") {
                InspectorField("Name") {
                    Text(cycle.name.isEmpty ? "—" : cycle.name)
                        .font(.system(size: 12))
                }
                InspectorField("Loop mode") {
                    Text(cycle.loopMode.displayName)
                        .font(.system(size: 12))
                }
                InspectorField("States") {
                    Text("\(cycle.states.count)")
                        .font(.system(size: 12, design: .monospaced))
                }
                InspectorField("Total frames") {
                    Text("\(cycle.totalCycleFrames)")
                        .font(.system(size: 12, design: .monospaced))
                }
                HStack {
                    Spacer()
                    Button("Edit Cycle…") {
                        controller.showingCycleEditor = true
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            InspectorSection("Assigned to") {
                let sprites = spritesUsing(cycleName: cycle.name)
                if sprites.isEmpty {
                    Text("No sprites are using this cycle.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sprites, id: \.0) { setName, spriteName in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(spriteName)
                                    .font(.system(size: 12))
                                Text(setName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
        })
    }

    private func spritesUsing(cycleName: String) -> [(String, String)] {
        guard let cfg = controller.projectConfig else { return [] }
        var result: [(String, String)] = []
        for spriteSet in cfg.spriteConfig.library.spriteSets {
            for sprite in spriteSet.sprites {
                if sprite.cycleName == cycleName {
                    result.append((spriteSet.name, sprite.name))
                }
            }
        }
        return result
    }
}
