import AppKit
import SwiftUI
import LoomEngine

struct KeyframeInspector: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        if let sel = controller.selectedTimelineKF {
            InspectorSection("Keyframe — \(sel.lane.label)") {
                kfFields(sel)
            }
        }
        if let sel = controller.selectedRendererTimelineKF {
            InspectorSection("Renderer Keyframe — \(sel.lane.label)") {
                rendererKFFields(sel)
            }
        }
    }

    @ViewBuilder
    private func kfFields(_ sel: TimelineKFSelection) -> some View {
        InspectorField("Frame") {
            TextField("", value: frameBinding(sel), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60)
        }

        switch sel.lane {
        case .position:
            InspectorField("X offset") {
                FloatEntryField(value: vectorXBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
            InspectorField("Y offset") {
                FloatEntryField(value: vectorYBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
        case .scale:
            InspectorField("X scale") {
                FloatEntryField(value: vectorXBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
            InspectorField("Y scale") {
                FloatEntryField(value: vectorYBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
        case .rotation:
            InspectorField("Degrees") {
                FloatEntryField(value: doubleValueBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .morph:
            InspectorField("Amount") {
                FloatEntryField(value: doubleValueBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
        case .opacity:
            InspectorField("Alpha") {
                FloatEntryField(value: doubleValueBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
        case .shape:
            InspectorField("Index") {
                TextField("", value: shapeIndexBinding(sel), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
                Text("(0 = self)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }

        InspectorField("Easing") {
            Picker("", selection: easingBinding(sel)) {
                ForEach(EasingType.allCases, id: \.self) { e in
                    Text(e.kfLabel).tag(e)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }
    }

    @ViewBuilder
    private func rendererKFFields(_ sel: RendererTimelineKFSelection) -> some View {
        InspectorField("Frame") {
            TextField("", value: rendererFrameBinding(sel), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60)
        }

        switch sel.lane {
        case .fillColor, .strokeColor:
            InspectorField("Color") {
                ColorPicker("", selection: rendererColorBinding(sel), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 60)
            }
        case .strokeWidth, .opacity, .blur:
            InspectorField(sel.lane == .opacity ? "Alpha" : sel.lane == .blur ? "Radius" : "Width") {
                FloatEntryField(value: rendererDoubleBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
        }

        InspectorField("Easing") {
            Picker("", selection: rendererEasingBinding(sel)) {
                ForEach(EasingType.allCases, id: \.self) { e in
                    Text(e.kfLabel).tag(e)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }
    }

    // MARK: - Frame binding

    private func frameBinding(_ sel: TimelineKFSelection) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: {
                guard let drivers = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?.animation.drivers
                else { return 0 }
                return sel.lane.keyframeFrames(from: drivers)[safe: sel.keyframeIdx] ?? 0
            },
            set: { newFrame in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        switch sel.lane {
                        case .position:
                            guard sel.keyframeIdx < drivers.position.keyframes.count else { return }
                            drivers.position.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.position.keyframes.sort { $0.frame < $1.frame }
                        case .scale:
                            guard sel.keyframeIdx < drivers.scale.keyframes.count else { return }
                            drivers.scale.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.scale.keyframes.sort { $0.frame < $1.frame }
                        case .rotation:
                            guard sel.keyframeIdx < drivers.rotation.keyframes.count else { return }
                            drivers.rotation.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.rotation.keyframes.sort { $0.frame < $1.frame }
                        case .morph:
                            guard sel.keyframeIdx < drivers.morph.keyframes.count else { return }
                            drivers.morph.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.morph.keyframes.sort { $0.frame < $1.frame }
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                        case .shape:
                            guard sel.keyframeIdx < drivers.shape.keyframes.count else { return }
                            drivers.shape.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.shape.keyframes.sort { $0.frame < $1.frame }
                        }
                    }
                }
                // Follow the moved keyframe to its new sorted index
                if let newIdx = sel.lane.keyframeFrames(
                    from: ctl.projectConfig?.spriteConfig.library
                        .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?
                        .animation.drivers ?? .identity
                ).firstIndex(of: newFrame) {
                    ctl.selectedTimelineKF = TimelineKFSelection(
                        setIdx: sel.setIdx, spriteIdx: sel.spriteIdx,
                        lane: sel.lane, keyframeIdx: newIdx
                    )
                }
            }
        )
    }

    // MARK: - Value bindings

    private func doubleValueBinding(_ sel: TimelineKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                guard let drivers = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?.animation.drivers
                else { return 0 }
                switch sel.lane {
                case .rotation: return drivers.rotation.keyframes[safe: sel.keyframeIdx]?.value ?? 0
                case .morph:    return drivers.morph.keyframes[safe: sel.keyframeIdx]?.value ?? 0
                case .opacity:  return drivers.opacity.keyframes[safe: sel.keyframeIdx]?.value ?? 1
                default:        return 0
                }
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        switch sel.lane {
                        case .rotation:
                            guard sel.keyframeIdx < drivers.rotation.keyframes.count else { return }
                            drivers.rotation.keyframes[sel.keyframeIdx].value = v
                        case .morph:
                            guard sel.keyframeIdx < drivers.morph.keyframes.count else { return }
                            drivers.morph.keyframes[sel.keyframeIdx].value = v
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].value = v
                        default: break
                        }
                    }
                }
            }
        )
    }

    private func shapeIndexBinding(_ sel: TimelineKFSelection) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: {
                let v = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?
                    .animation.drivers?.shape.keyframes[safe: sel.keyframeIdx]?.value ?? 0
                return max(0, Int(v))
            },
            set: { idx in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        guard sel.keyframeIdx < drivers.shape.keyframes.count else { return }
                        drivers.shape.keyframes[sel.keyframeIdx].value = Double(max(0, idx))
                    }
                }
            }
        )
    }

    private func vectorXBinding(_ sel: TimelineKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                guard let drivers = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?.animation.drivers
                else { return 0 }
                switch sel.lane {
                case .position: return drivers.position.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0
                case .scale:    return drivers.scale.keyframes[safe: sel.keyframeIdx]?.value.x ?? 1
                default:        return 0
                }
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        switch sel.lane {
                        case .position:
                            guard sel.keyframeIdx < drivers.position.keyframes.count else { return }
                            drivers.position.keyframes[sel.keyframeIdx].value.x = v
                        case .scale:
                            guard sel.keyframeIdx < drivers.scale.keyframes.count else { return }
                            drivers.scale.keyframes[sel.keyframeIdx].value.x = v
                        default: break
                        }
                    }
                }
            }
        )
    }

    private func vectorYBinding(_ sel: TimelineKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                guard let drivers = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?.animation.drivers
                else { return 0 }
                switch sel.lane {
                case .position: return drivers.position.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0
                case .scale:    return drivers.scale.keyframes[safe: sel.keyframeIdx]?.value.y ?? 1
                default:        return 0
                }
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        switch sel.lane {
                        case .position:
                            guard sel.keyframeIdx < drivers.position.keyframes.count else { return }
                            drivers.position.keyframes[sel.keyframeIdx].value.y = v
                        case .scale:
                            guard sel.keyframeIdx < drivers.scale.keyframes.count else { return }
                            drivers.scale.keyframes[sel.keyframeIdx].value.y = v
                        default: break
                        }
                    }
                }
            }
        )
    }

    // MARK: - Easing binding

    private func easingBinding(_ sel: TimelineKFSelection) -> Binding<EasingType> {
        let ctl = controller
        return Binding(
            get: {
                guard let drivers = ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: sel.setIdx]?.sprites[safe: sel.spriteIdx]?.animation.drivers
                else { return .linear }
                switch sel.lane {
                case .position: return drivers.position.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .scale:    return drivers.scale.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .rotation: return drivers.rotation.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .morph:    return drivers.morph.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .opacity:  return drivers.opacity.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .shape:    return drivers.shape.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                }
            },
            set: { e in
                ctl.updateProjectConfig { cfg in
                    withDrivers(in: &cfg, si: sel.setIdx, pi: sel.spriteIdx) { drivers in
                        switch sel.lane {
                        case .position:
                            guard sel.keyframeIdx < drivers.position.keyframes.count else { return }
                            drivers.position.keyframes[sel.keyframeIdx].easing = e
                        case .scale:
                            guard sel.keyframeIdx < drivers.scale.keyframes.count else { return }
                            drivers.scale.keyframes[sel.keyframeIdx].easing = e
                        case .rotation:
                            guard sel.keyframeIdx < drivers.rotation.keyframes.count else { return }
                            drivers.rotation.keyframes[sel.keyframeIdx].easing = e
                        case .morph:
                            guard sel.keyframeIdx < drivers.morph.keyframes.count else { return }
                            drivers.morph.keyframes[sel.keyframeIdx].easing = e
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].easing = e
                        case .shape:
                            guard sel.keyframeIdx < drivers.shape.keyframes.count else { return }
                            drivers.shape.keyframes[sel.keyframeIdx].easing = e
                        }
                    }
                }
            }
        )
    }

    // MARK: - Renderer keyframe bindings

    private func rendererFrameBinding(_ sel: RendererTimelineKFSelection) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: {
                let drivers = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: sel.rendererSetIdx]?.renderers[safe: sel.rendererItemIdx]?.drivers
                return sel.lane.keyframeFrames(from: drivers)[safe: sel.keyframeIdx] ?? 0
            },
            set: { newFrame in
                ctl.updateProjectConfig { cfg in
                    withRendererDrivers(in: &cfg, setIdx: sel.rendererSetIdx, itemIdx: sel.rendererItemIdx) { drivers, _ in
                        switch sel.lane {
                        case .fillColor:
                            guard sel.keyframeIdx < (drivers.fillColor?.keyframes.count ?? 0) else { return }
                            drivers.fillColor!.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.fillColor!.keyframes.sort { $0.frame < $1.frame }
                        case .strokeColor:
                            guard sel.keyframeIdx < (drivers.strokeColor?.keyframes.count ?? 0) else { return }
                            drivers.strokeColor!.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.strokeColor!.keyframes.sort { $0.frame < $1.frame }
                        case .strokeWidth:
                            guard sel.keyframeIdx < drivers.strokeWidth.keyframes.count else { return }
                            drivers.strokeWidth.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.strokeWidth.keyframes.sort { $0.frame < $1.frame }
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                        case .blur:
                            guard sel.keyframeIdx < drivers.blur.keyframes.count else { return }
                            drivers.blur.keyframes[sel.keyframeIdx].frame = newFrame
                            drivers.blur.keyframes.sort { $0.frame < $1.frame }
                        }
                    }
                }
                let drivers = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: sel.rendererSetIdx]?.renderers[safe: sel.rendererItemIdx]?.drivers
                if let newIdx = sel.lane.keyframeFrames(from: drivers).firstIndex(of: newFrame) {
                    ctl.selectedRendererTimelineKF = RendererTimelineKFSelection(
                        rendererSetIdx: sel.rendererSetIdx,
                        rendererItemIdx: sel.rendererItemIdx,
                        lane: sel.lane,
                        keyframeIdx: newIdx
                    )
                }
            }
        )
    }

    private func rendererDoubleBinding(_ sel: RendererTimelineKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                let drivers = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: sel.rendererSetIdx]?.renderers[safe: sel.rendererItemIdx]?
                    .drivers
                switch sel.lane {
                case .strokeWidth:
                    return drivers?.strokeWidth.keyframes[safe: sel.keyframeIdx]?.value ?? 1
                case .opacity:
                    return drivers?.opacity.keyframes[safe: sel.keyframeIdx]?.value ?? 1
                case .blur:
                    return drivers?.blur.keyframes[safe: sel.keyframeIdx]?.value ?? 0
                case .fillColor, .strokeColor:
                    return 1
                }
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    withRendererDrivers(in: &cfg, setIdx: sel.rendererSetIdx, itemIdx: sel.rendererItemIdx) { drivers, _ in
                        switch sel.lane {
                        case .strokeWidth:
                            guard sel.keyframeIdx < drivers.strokeWidth.keyframes.count else { return }
                            drivers.strokeWidth.keyframes[sel.keyframeIdx].value = v
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].value = v
                        case .blur:
                            guard sel.keyframeIdx < drivers.blur.keyframes.count else { return }
                            drivers.blur.keyframes[sel.keyframeIdx].value = v
                        case .fillColor, .strokeColor:
                            break
                        }
                    }
                }
            }
        )
    }

    private func rendererColorBinding(_ sel: RendererTimelineKFSelection) -> Binding<Color> {
        let ctl = controller
        return Binding(
            get: {
                let c: LoomColor
                let renderer = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: sel.rendererSetIdx]?.renderers[safe: sel.rendererItemIdx]
                switch sel.lane {
                case .fillColor:
                    c = renderer?.drivers?.fillColor?.keyframes[safe: sel.keyframeIdx]?.value
                        ?? renderer?.fillColor ?? .black
                case .strokeColor:
                    c = renderer?.drivers?.strokeColor?.keyframes[safe: sel.keyframeIdx]?.value
                        ?? renderer?.strokeColor ?? .black
                case .strokeWidth, .opacity, .blur:
                    c = .black
                }
                return Color(red: c.rF, green: c.gF, blue: c.bF, opacity: c.aF)
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor.black
                let value = LoomColor(
                    r: clamp255(ns.redComponent),
                    g: clamp255(ns.greenComponent),
                    b: clamp255(ns.blueComponent),
                    a: clamp255(ns.alphaComponent)
                )
                ctl.updateProjectConfig { cfg in
                    withRendererDrivers(in: &cfg, setIdx: sel.rendererSetIdx, itemIdx: sel.rendererItemIdx) { drivers, renderer in
                        switch sel.lane {
                        case .fillColor:
                            if drivers.fillColor == nil { drivers.fillColor = ColorDriver.constant(renderer.fillColor) }
                            guard sel.keyframeIdx < drivers.fillColor!.keyframes.count else { return }
                            drivers.fillColor!.keyframes[sel.keyframeIdx].value = value
                        case .strokeColor:
                            if drivers.strokeColor == nil { drivers.strokeColor = ColorDriver.constant(renderer.strokeColor) }
                            guard sel.keyframeIdx < drivers.strokeColor!.keyframes.count else { return }
                            drivers.strokeColor!.keyframes[sel.keyframeIdx].value = value
                        case .strokeWidth, .opacity, .blur:
                            break
                        }
                    }
                }
            }
        )
    }

    private func rendererEasingBinding(_ sel: RendererTimelineKFSelection) -> Binding<EasingType> {
        let ctl = controller
        return Binding(
            get: {
                let drivers = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: sel.rendererSetIdx]?.renderers[safe: sel.rendererItemIdx]?.drivers
                switch sel.lane {
                case .fillColor:   return drivers?.fillColor?.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .strokeColor: return drivers?.strokeColor?.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .strokeWidth: return drivers?.strokeWidth.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .opacity:     return drivers?.opacity.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .blur:        return drivers?.blur.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                }
            },
            set: { e in
                ctl.updateProjectConfig { cfg in
                    withRendererDrivers(in: &cfg, setIdx: sel.rendererSetIdx, itemIdx: sel.rendererItemIdx) { drivers, _ in
                        switch sel.lane {
                        case .fillColor:
                            guard sel.keyframeIdx < (drivers.fillColor?.keyframes.count ?? 0) else { return }
                            drivers.fillColor!.keyframes[sel.keyframeIdx].easing = e
                        case .strokeColor:
                            guard sel.keyframeIdx < (drivers.strokeColor?.keyframes.count ?? 0) else { return }
                            drivers.strokeColor!.keyframes[sel.keyframeIdx].easing = e
                        case .strokeWidth:
                            guard sel.keyframeIdx < drivers.strokeWidth.keyframes.count else { return }
                            drivers.strokeWidth.keyframes[sel.keyframeIdx].easing = e
                        case .opacity:
                            guard sel.keyframeIdx < drivers.opacity.keyframes.count else { return }
                            drivers.opacity.keyframes[sel.keyframeIdx].easing = e
                        case .blur:
                            guard sel.keyframeIdx < drivers.blur.keyframes.count else { return }
                            drivers.blur.keyframes[sel.keyframeIdx].easing = e
                        }
                    }
                }
            }
        )
    }

    private func clamp255(_ v: CGFloat) -> Int {
        Int(max(0, min(255, (v * 255 + 0.5).rounded(.down))))
    }
}

// MARK: - EasingType label (local to avoid conflict with AnimationDriverInspector)

private extension EasingType {
    var kfLabel: String {
        switch self {
        case .linear:          return "Linear"
        case .easeInQuad:      return "In ²"
        case .easeOutQuad:     return "Out ²"
        case .easeInOutQuad:   return "In-Out ²"
        case .easeInCubic:     return "In ³"
        case .easeOutCubic:    return "Out ³"
        case .easeInOutCubic:  return "In-Out ³"
        case .easeInSine:      return "In sin"
        case .easeOutSine:     return "Out sin"
        case .easeInOutSine:   return "In-Out sin"
        case .easeInExpo:      return "In exp"
        case .easeOutExpo:     return "Out exp"
        case .easeInOutExpo:   return "In-Out exp"
        case .easeInBack:      return "In back"
        case .easeOutBack:     return "Out back"
        case .easeInOutBack:   return "In-Out back"
        }
    }
}
