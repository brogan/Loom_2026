import SwiftUI
import LoomEngine

/// Left-panel content for the Live tab: a read-only browse of the project's
/// existing sprite sets/sprites (stage from here) plus the list of currently
/// staged instances with visibility + pose controls — `LoomLiveV1Scope.md` §2.1.
struct LiveTabView: View {

    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var liveController: LiveSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let error = liveController.loadError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                stagedSection

                Divider().padding(.horizontal, 12)

                browseSection
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Text("Live")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }

    // MARK: - Staged sprites

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Staged")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            if liveController.stagedSprites.isEmpty {
                Text("Nothing staged yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(liveController.stagedSprites) { staged in
                    stagedRow(staged)
                }
            }
        }
    }

    private func stagedRow(_ staged: LiveSessionController.StagedSprite) -> some View {
        let isSelected = liveController.selectedStagedID == staged.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { staged.isVisible },
                    set: { liveController.setVisible(staged.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Text(staged.spriteDefName)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { liveController.selectedStagedID = staged.id }

            if isSelected {
                poseControls(staged)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private func poseControls(_ staged: LiveSessionController.StagedSprite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Pos").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.position.x), width: 52)
                FloatEntryField(value: poseBinding(staged.id, \.position.y), width: 52)
            }
            HStack(spacing: 4) {
                Text("Scale").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.scale.x), width: 52)
                FloatEntryField(value: poseBinding(staged.id, \.scale.y), width: 52)
            }
            HStack(spacing: 4) {
                Text("Rot").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                FloatEntryField(value: poseBinding(staged.id, \.rotation), width: 52)
            }
        }
    }

    /// Reads/writes one scalar of a staged sprite's pose, routing every write
    /// through `LiveSessionController.updatePose` so the engine and the
    /// app-side record stay in sync on every commit.
    private func poseBinding(
        _ id: LiveSessionController.StagedSprite.ID,
        _ keyPath: WritableKeyPath<LiveSessionController.StagedSprite, Double>
    ) -> Binding<Double> {
        Binding(
            get: { liveController.stagedSprites.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard var staged = liveController.stagedSprites.first(where: { $0.id == id }) else { return }
                staged[keyPath: keyPath] = newValue
                liveController.updatePose(id, position: staged.position, scale: staged.scale, rotation: staged.rotation)
            }
        )
    }

    // MARK: - Browse sprite sets

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sprite Sets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            ForEach(controller.projectConfig?.spriteConfig.library.spriteSets ?? [], id: \.name) { set in
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)

                    ForEach(set.sprites, id: \.name) { sprite in
                        Button {
                            liveController.stage(spriteSetName: set.name, spriteName: sprite.name)
                        } label: {
                            HStack {
                                Text(sprite.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Centre-panel canvas for the Live tab — mirrors `ContentView.liveCanvas`
/// but is bound to the Live tab's own independent `Engine`
/// (`LiveSessionController.engine`), never `AppController.engine`.
struct LiveCanvasView: View {

    @EnvironmentObject private var liveController: LiveSessionController
    @State private var currentFrame: Int = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let engine = liveController.engine {
                GeometryReader { geo in
                    let size   = engine.canvasSize
                    let aspect = size.width / max(size.height, 1)
                    RenderSurfaceView(
                        engine:        engine,
                        playbackState: .playing,
                        onFrameTick:   { currentFrame = $0 }
                    )
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            liveModeBadge
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(Color.red.opacity(0.6), lineWidth: 3)
        )
    }

    private var liveModeBadge: some View {
        Label("LIVE", systemImage: "circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
            .padding(10)
    }
}
