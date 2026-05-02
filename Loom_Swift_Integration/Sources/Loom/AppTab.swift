import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case global      = "Global"
    case assets      = "Assets"
    case geometry    = "Geometry"
    case subdivision = "Subdivision"
    case sprites     = "Sprites"
    case rendering   = "Rendering"

    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .global:      return "globe"
        case .assets:      return "folder"
        case .geometry:    return "pentagon"
        case .subdivision: return "square.grid.3x3.fill"
        case .sprites:     return "square.stack.3d.up"
        case .rendering:   return "paintbrush"
        }
    }

    var hasListPanel: Bool { self != .global }
}
