import SwiftUI
import LoomEngine

// MARK: - TimelineLane

enum TimelineLane: Int, CaseIterable, Hashable {
    case position = 0, scale, rotation, morph, opacity, shape
    case subdivisionSet = 6
    case rendererSet    = 7
    case cycleName      = 8

    var label: String {
        switch self {
        case .position:      return "Position"
        case .scale:         return "Scale"
        case .rotation:      return "Rotation"
        case .morph:         return "Morph"
        case .opacity:       return "Opacity"
        case .shape:         return "Shape"
        case .subdivisionSet: return "Subdiv"
        case .rendererSet:   return "Rend.Set"
        case .cycleName:     return "Cycle"
        }
    }

    var color: Color {
        switch self {
        case .position:      return .blue
        case .scale:         return .green
        case .rotation:      return .orange
        case .morph:         return .purple
        case .opacity:       return .pink
        case .shape:         return .mint
        case .subdivisionSet: return Color(hue: 0.56, saturation: 0.65, brightness: 0.80)
        case .rendererSet:   return Color(hue: 0.08, saturation: 0.65, brightness: 0.85)
        case .cycleName:     return Color(hue: 0.52, saturation: 0.70, brightness: 0.82)
        }
    }

    func keyframeFrames(from drivers: TransformDrivers) -> [Int] {
        switch self {
        case .position:      return drivers.position.keyframes.map(\.frame)
        case .scale:         return drivers.scale.keyframes.map(\.frame)
        case .rotation:      return drivers.rotation.keyframes.map(\.frame)
        case .morph:         return drivers.morph.keyframes.map(\.frame)
        case .opacity:       return drivers.opacity.keyframes.map(\.frame)
        case .shape:         return drivers.shape.keyframes.map(\.frame)
        case .subdivisionSet: return drivers.subdivisionSet.keyframes.map(\.frame)
        case .rendererSet:   return drivers.rendererSet.keyframes.map(\.frame)
        case .cycleName:     return drivers.cycleName.keyframes.map(\.frame)
        }
    }
}

// MARK: - RendererTimelineLane

enum RendererTimelineLane: Int, CaseIterable, Hashable {
    case fillColor = 0, strokeColor, strokeWidth, opacity, blur

    var label: String {
        switch self {
        case .fillColor:   return "Fill"
        case .strokeColor: return "Stroke"
        case .strokeWidth: return "Width"
        case .opacity:     return "Opacity"
        case .blur:        return "Blur"
        }
    }

    var color: Color {
        switch self {
        case .fillColor:   return .yellow
        case .strokeColor: return .red
        case .strokeWidth: return .indigo
        case .opacity:     return .pink
        case .blur:        return .mint
        }
    }

    func keyframeFrames(from drivers: RendererDrivers?) -> [Int] {
        guard let drivers else { return [] }
        switch self {
        case .fillColor:   return drivers.fillColor?.keyframes.map(\.frame) ?? []
        case .strokeColor: return drivers.strokeColor?.keyframes.map(\.frame) ?? []
        case .strokeWidth: return drivers.strokeWidth.keyframes.map(\.frame)
        case .opacity:     return drivers.opacity.keyframes.map(\.frame)
        case .blur:        return drivers.blur.keyframes.map(\.frame)
        }
    }
}

// MARK: - TimelineKFSelection

struct TimelineKFSelection: Equatable {
    var setIdx:      Int
    var spriteIdx:   Int
    var lane:        TimelineLane
    var keyframeIdx: Int
}

// MARK: - RendererTimelineKFSelection

struct RendererTimelineKFSelection: Equatable {
    var rendererSetIdx:  Int
    var rendererItemIdx: Int
    var lane:            RendererTimelineLane
    var keyframeIdx:     Int
}

// MARK: - CameraLane

enum CameraLane: Int, CaseIterable, Hashable {
    case tracking = 0, pan, zoom, rotation

    var label: String {
        switch self {
        case .tracking: return "Tracking"
        case .pan:      return "Pan"
        case .zoom:     return "Zoom"
        case .rotation: return "Rotation"
        }
    }

    var color: Color {
        switch self {
        case .tracking: return .blue
        case .pan:      return .teal
        case .zoom:     return Color(hue: 0.48, saturation: 0.7, brightness: 0.85)
        case .rotation: return .cyan
        }
    }

    func keyframeFrames(from cam: CameraConfig) -> [Int] {
        switch self {
        case .tracking: return cam.tracking.keyframes.map(\.frame)
        case .pan:      return cam.pan.keyframes.map(\.frame)
        case .zoom:     return cam.zoom.keyframes.map(\.frame)
        case .rotation: return cam.rotation.keyframes.map(\.frame)
        }
    }
}

// MARK: - CameraKFSelection

struct CameraKFSelection: Equatable, Hashable {
    var lane:        CameraLane
    var keyframeIdx: Int
}

// MARK: - Shared mutation helper

/// Extracts the TransformDrivers for a specific sprite, runs `perform`, writes back.
/// Safe no-op if indices are out of bounds or drivers are nil.
func withDrivers(in cfg: inout ProjectConfig,
                 si: Int, pi: Int,
                 perform: (inout TransformDrivers) -> Void) {
    guard si < cfg.spriteConfig.library.spriteSets.count,
          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count,
          var drivers = cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation.drivers
    else { return }
    perform(&drivers)
    cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation.drivers = drivers
}

func withRendererDrivers(in cfg: inout ProjectConfig,
                         setIdx: Int, itemIdx: Int,
                         perform: (inout RendererDrivers, Renderer) -> Void) {
    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
    else { return }
    let renderer = cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
    var drivers = renderer.drivers ?? RendererDrivers(
        fillColor: ColorDriver.constant(renderer.fillColor),
        strokeColor: ColorDriver.constant(renderer.strokeColor),
        strokeWidth: DoubleDriver.constant(renderer.strokeWidth),
        opacity: .one
    )
    perform(&drivers, renderer)
    cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].drivers = drivers
}
