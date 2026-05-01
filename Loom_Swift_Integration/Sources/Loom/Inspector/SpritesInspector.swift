import SwiftUI
import LoomEngine

struct SpritesInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        guard let spriteName = controller.selectedSpriteID,
              let (setIdx, spriteIdx) = spriteLocation(named: spriteName),
              let sprite = controller.projectConfig?.spriteConfig.library
                  .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            generalSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            transformSection(setIdx: setIdx, spriteIdx: spriteIdx)
            animationSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
        })
    }

    // MARK: - General

    private func generalSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        InspectorSection("Sprite") {
            InspectorField("Name") {
                TextField("", text: bindS(setIdx, spriteIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Shape set") {
                TextField("", text: bindS(setIdx, spriteIdx, \.shapeSetName))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Shape") {
                TextField("", text: bindS(setIdx, spriteIdx, \.shapeName))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Renderer") {
                TextField("", text: bindS(setIdx, spriteIdx, \.rendererSetName))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
        }
    }

    // MARK: - Transform

    private func transformSection(setIdx: Int, spriteIdx: Int) -> some View {
        InspectorSection("Transform") {
            vec2Field("Position",
                      xKP: \.position.x, yKP: \.position.y,
                      setIdx: setIdx, spriteIdx: spriteIdx)
            vec2Field("Scale",
                      xKP: \.scale.x, yKP: \.scale.y,
                      setIdx: setIdx, spriteIdx: spriteIdx)
            InspectorField("Rotation") {
                TextField("", value: bindS(setIdx, spriteIdx, \.rotation),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 65)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Animation

    @ViewBuilder
    private func animationSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        let anim = sprite.animation
        InspectorSection("Animation") {
            InspectorField("Enabled") {
                Toggle("", isOn: bindA(setIdx, spriteIdx, \.enabled)).labelsHidden()
            }
            if anim.enabled {
                InspectorField("Type") {
                    Picker("", selection: bindA(setIdx, spriteIdx, \.type)) {
                        ForEach(AnimationType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
                InspectorField("Loop") {
                    Picker("", selection: bindA(setIdx, spriteIdx, \.loopMode)) {
                        ForEach(LoopMode.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 100)
                }
                InspectorField("Total draws") {
                    TextField("", value: bindA(setIdx, spriteIdx, \.totalDraws), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 55)
                    Text("0=∞").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                rangeField("Transl X",
                           minKP: \.translationRange.x.min, maxKP: \.translationRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Transl Y",
                           minKP: \.translationRange.y.min, maxKP: \.translationRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Scale X",
                           minKP: \.scaleRange.x.min, maxKP: \.scaleRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Scale Y",
                           minKP: \.scaleRange.y.min, maxKP: \.scaleRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Rotation",
                           minKP: \.rotationRange.min, maxKP: \.rotationRange.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
            }
        }
    }

    // MARK: - Field helpers

    private func vec2Field(
        _ label: String,
        xKP: WritableKeyPath<SpriteDef, Double>,
        yKP: WritableKeyPath<SpriteDef, Double>,
        setIdx: Int, spriteIdx: Int
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text("X").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                TextField("", value: bindS(setIdx, spriteIdx, xKP),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
                Text("Y").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                TextField("", value: bindS(setIdx, spriteIdx, yKP),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
            }
        }
    }

    private func rangeField(
        _ label: String,
        minKP: WritableKeyPath<SpriteAnimation, Double>,
        maxKP: WritableKeyPath<SpriteAnimation, Double>,
        setIdx: Int, spriteIdx: Int
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                TextField("", value: bindA(setIdx, spriteIdx, minKP),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
                Text("–").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("", value: bindA(setIdx, spriteIdx, maxKP),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
            }
        }
    }

    // MARK: - Binding helpers

    private func spriteLocation(named name: String) -> (Int, Int)? {
        guard let lib = controller.projectConfig?.spriteConfig.library else { return nil }
        for (si, set) in lib.spriteSets.enumerated() {
            if let pi = set.sprites.firstIndex(where: { $0.name == name }) {
                return (si, pi)
            }
        }
        return nil
    }

    private func bindS<T>(_ si: Int, _ pi: Int,
                           _ kp: WritableKeyPath<SpriteDef, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SpriteDef()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi][keyPath: kp] = v
                }
            }
        )
    }

    private func bindA<T>(_ si: Int, _ pi: Int,
                           _ kp: WritableKeyPath<SpriteAnimation, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SpriteAnimation()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?.animation[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation[keyPath: kp] = v
                }
            }
        )
    }
}

// MARK: - Display names

private extension AnimationType {
    var displayName: String {
        switch self {
        case .keyframe:      return "Keyframe"
        case .random:        return "Random"
        case .keyframeMorph: return "Keyframe Morph"
        case .jitterMorph:   return "Jitter Morph"
        }
    }
}

private extension LoopMode {
    var displayName: String {
        switch self {
        case .loop:     return "Loop"
        case .pingPong: return "Ping-Pong"
        case .once:     return "Once"
        }
    }
}
