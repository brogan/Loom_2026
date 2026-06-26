import CoreGraphics

public enum LayerBlendMode: String, Codable, CaseIterable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case add

    public var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .screen:     return .screen
        case .overlay:    return .overlay
        case .darken:     return .darken
        case .lighten:    return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn:  return .colorBurn
        case .softLight:  return .softLight
        case .hardLight:  return .hardLight
        case .difference: return .difference
        case .exclusion:  return .exclusion
        case .add:        return .plusLighter
        }
    }

    public var displayName: String {
        switch self {
        case .normal:     return "Normal"
        case .multiply:   return "Multiply"
        case .screen:     return "Screen"
        case .overlay:    return "Overlay"
        case .darken:     return "Darken"
        case .lighten:    return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn:  return "Color Burn"
        case .softLight:  return "Soft Light"
        case .hardLight:  return "Hard Light"
        case .difference: return "Difference"
        case .exclusion:  return "Exclusion"
        case .add:        return "Add"
        }
    }
}
