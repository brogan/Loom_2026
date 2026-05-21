import SwiftUI
import LoomEngine

struct CameraKeyframeInspector: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        if let sel = controller.selectedCameraKF {
            InspectorSection("Keyframe — Camera \(sel.lane.label)") {
                kfFields(sel)
            }
            .id(sel)
        }
    }

    @ViewBuilder
    private func kfFields(_ sel: CameraKFSelection) -> some View {
        InspectorField("Frame") {
            TextField("", value: frameBinding(sel), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60)
        }

        switch sel.lane {
        case .tracking:
            InspectorField("Track X") {
                FloatEntryField(value: trackingXBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
            InspectorField("Track Y") {
                FloatEntryField(value: trackingYBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
        case .pan:
            InspectorField("X pan") {
                FloatEntryField(value: panXBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
            InspectorField("Y pan") {
                FloatEntryField(value: panYBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
            }
        case .zoom:
            InspectorField("Zoom") {
                FloatEntryField(value: doubleBinding(sel), width: 65, fractionDigits: 3, fontSize: 12)
            }
        case .rotation:
            InspectorField("Degrees") {
                FloatEntryField(value: doubleBinding(sel), width: 65, fractionDigits: 2, fontSize: 12)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }

        InspectorField("Easing") {
            Picker("", selection: easingBinding(sel)) {
                ForEach(EasingType.allCases, id: \.self) { e in
                    Text(e.camLabel).tag(e)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }

        InspectorField("Loop") {
            Picker("", selection: loopModeBinding(sel)) {
                Text("Loop").tag(LoopMode.loop)
                Text("Ping-pong").tag(LoopMode.pingPong)
                Text("Once").tag(LoopMode.once)
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }
    }

    // MARK: - Frame binding

    private func frameBinding(_ sel: CameraKFSelection) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: {
                let cam = ctl.projectConfig?.globalConfig.camera ?? .disabled
                return sel.lane.keyframeFrames(from: cam)[safe: sel.keyframeIdx] ?? 0
            },
            set: { newFrame in
                ctl.updateProjectConfig { cfg in
                    switch sel.lane {
                    case .tracking:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                        cfg.globalConfig.camera.tracking.keyframes[sel.keyframeIdx].frame = newFrame
                        cfg.globalConfig.camera.tracking.keyframes.sort { $0.frame < $1.frame }
                    case .pan:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                        cfg.globalConfig.camera.pan.keyframes[sel.keyframeIdx].frame = newFrame
                        cfg.globalConfig.camera.pan.keyframes.sort { $0.frame < $1.frame }
                    case .zoom:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.zoom.keyframes.count else { return }
                        cfg.globalConfig.camera.zoom.keyframes[sel.keyframeIdx].frame = newFrame
                        cfg.globalConfig.camera.zoom.keyframes.sort { $0.frame < $1.frame }
                    case .rotation:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.rotation.keyframes.count else { return }
                        cfg.globalConfig.camera.rotation.keyframes[sel.keyframeIdx].frame = newFrame
                        cfg.globalConfig.camera.rotation.keyframes.sort { $0.frame < $1.frame }
                    }
                }
                let cam = ctl.projectConfig?.globalConfig.camera ?? .disabled
                if let idx = sel.lane.keyframeFrames(from: cam).firstIndex(of: newFrame) {
                    ctl.selectedCameraKF = CameraKFSelection(lane: sel.lane, keyframeIdx: idx)
                }
            }
        )
    }

    // MARK: - Value bindings

    private func trackingXBinding(_ sel: CameraKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.tracking.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard sel.keyframeIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                    cfg.globalConfig.camera.tracking.keyframes[sel.keyframeIdx].value.x = v
                }
            }
        )
    }

    private func trackingYBinding(_ sel: CameraKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.tracking.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard sel.keyframeIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                    cfg.globalConfig.camera.tracking.keyframes[sel.keyframeIdx].value.y = v
                }
            }
        )
    }

    private func panXBinding(_ sel: CameraKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard sel.keyframeIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                    cfg.globalConfig.camera.pan.keyframes[sel.keyframeIdx].value.x = v
                }
            }
        )
    }

    private func panYBinding(_ sel: CameraKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard sel.keyframeIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                    cfg.globalConfig.camera.pan.keyframes[sel.keyframeIdx].value.y = v
                }
            }
        )
    }

    private func doubleBinding(_ sel: CameraKFSelection) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                let cam = ctl.projectConfig?.globalConfig.camera ?? .disabled
                switch sel.lane {
                case .zoom:     return cam.zoom.keyframes[safe: sel.keyframeIdx]?.value ?? 1
                case .rotation: return cam.rotation.keyframes[safe: sel.keyframeIdx]?.value ?? 0
                case .tracking,
                     .pan:      return 0
                }
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    switch sel.lane {
                    case .zoom:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.zoom.keyframes.count else { return }
                        cfg.globalConfig.camera.zoom.keyframes[sel.keyframeIdx].value = v
                    case .rotation:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.rotation.keyframes.count else { return }
                        cfg.globalConfig.camera.rotation.keyframes[sel.keyframeIdx].value = v
                    default: break
                    }
                }
            }
        )
    }

    private func loopModeBinding(_ sel: CameraKFSelection) -> Binding<LoopMode> {
        let ctl = controller
        return Binding(
            get: {
                let cam = ctl.projectConfig?.globalConfig.camera ?? .disabled
                switch sel.lane {
                case .tracking: return cam.tracking.loopMode
                case .pan:      return cam.pan.loopMode
                case .zoom:     return cam.zoom.loopMode
                case .rotation: return cam.rotation.loopMode
                }
            },
            set: { m in
                ctl.updateProjectConfig { cfg in
                    switch sel.lane {
                    case .tracking: cfg.globalConfig.camera.tracking.loopMode = m
                    case .pan:      cfg.globalConfig.camera.pan.loopMode      = m
                    case .zoom:     cfg.globalConfig.camera.zoom.loopMode     = m
                    case .rotation: cfg.globalConfig.camera.rotation.loopMode = m
                    }
                }
            }
        )
    }

    private func easingBinding(_ sel: CameraKFSelection) -> Binding<EasingType> {
        let ctl = controller
        return Binding(
            get: {
                let cam = ctl.projectConfig?.globalConfig.camera ?? .disabled
                switch sel.lane {
                case .tracking: return cam.tracking.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .pan:      return cam.pan.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .zoom:     return cam.zoom.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                case .rotation: return cam.rotation.keyframes[safe: sel.keyframeIdx]?.easing ?? .linear
                }
            },
            set: { e in
                ctl.updateProjectConfig { cfg in
                    switch sel.lane {
                    case .tracking:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                        cfg.globalConfig.camera.tracking.keyframes[sel.keyframeIdx].easing = e
                    case .pan:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                        cfg.globalConfig.camera.pan.keyframes[sel.keyframeIdx].easing = e
                    case .zoom:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.zoom.keyframes.count else { return }
                        cfg.globalConfig.camera.zoom.keyframes[sel.keyframeIdx].easing = e
                    case .rotation:
                        guard sel.keyframeIdx < cfg.globalConfig.camera.rotation.keyframes.count else { return }
                        cfg.globalConfig.camera.rotation.keyframes[sel.keyframeIdx].easing = e
                    }
                }
            }
        )
    }
}

private extension EasingType {
    var camLabel: String {
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
