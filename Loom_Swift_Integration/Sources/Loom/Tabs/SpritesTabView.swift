import SwiftUI
import LoomEngine

struct SpritesTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            spriteList
            Divider()
            addButton
        }
    }

    @ViewBuilder
    private var spriteList: some View {
        let sprites = controller.projectConfig?.spriteConfig.library.allSprites ?? []
        if sprites.isEmpty {
            emptyState(controller.projectConfig == nil ? "No project open" : "No sprites")
        } else {
            // Phase 3: replace with OutlineGroup for sprite-set hierarchy + drag reorder
            List(selection: $controller.selectedSpriteID) {
                ForEach(sprites, id: \.name) { sprite in
                    SpriteDefRow(sprite: sprite)
                        .tag(sprite.name)
                }
            }
            .listStyle(.plain)
        }
    }

    private var addButton: some View {
        HStack {
            Button {
                // Phase 3: add sprite or sprite set
            } label: {
                Label("New Sprite", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(8)
            Spacer()
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SpriteDefRow: View {
    let sprite: SpriteDef

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: sprite.animation.enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(sprite.animation.enabled ? Color.primary : Color.secondary)
                .font(.system(size: 12))

            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            if sprite.animation.enabled {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
