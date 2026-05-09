import SwiftUI
import LoomEngine

// MARK: - TimelineLane

enum TimelineLane: Int, CaseIterable {
    case position = 0, scale, rotation, morph, shape

    var label: String {
        switch self {
        case .position: return "Position"
        case .scale:    return "Scale"
        case .rotation: return "Rotation"
        case .morph:    return "Morph"
        case .shape:    return "Shape"
        }
    }

    var color: Color {
        switch self {
        case .position: return .blue
        case .scale:    return .green
        case .rotation: return .orange
        case .morph:    return .purple
        case .shape:    return .mint
        }
    }

    func keyframeFrames(from drivers: TransformDrivers) -> [Int] {
        switch self {
        case .position: return drivers.position.keyframes.map(\.frame)
        case .scale:    return drivers.scale.keyframes.map(\.frame)
        case .rotation: return drivers.rotation.keyframes.map(\.frame)
        case .morph:    return drivers.morph.keyframes.map(\.frame)
        case .shape:    return drivers.shape.keyframes.map(\.frame)
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

// MARK: - CameraLane

enum CameraLane: Int, CaseIterable {
    case pan = 0, zoom, rotation

    var label: String {
        switch self {
        case .pan:      return "Pan"
        case .zoom:     return "Zoom"
        case .rotation: return "Rotation"
        }
    }

    var color: Color {
        switch self {
        case .pan:      return .teal
        case .zoom:     return Color(hue: 0.48, saturation: 0.7, brightness: 0.85)
        case .rotation: return .cyan
        }
    }

    func keyframeFrames(from cam: CameraConfig) -> [Int] {
        switch self {
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
