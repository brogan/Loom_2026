import Foundation

// MARK: - Light type

public enum LightType: String, Codable, CaseIterable, Equatable, Sendable {
    case omni
    case spot
    case area

    public var displayName: String {
        switch self {
        case .omni: return "Omni"
        case .spot: return "Spot"
        case .area: return "Area"
        }
    }
}

// MARK: - LoomLight

/// A single theatrical light source.
///
/// All numeric fields are driven by `DoubleDriver`s. In constant mode the driver's
/// `base` value is the resolved value each frame. In animated modes (noise, oscillator,
/// keyframe) the driver returns a time-varying value.
///
/// **Coordinate space**: positions use canvas-normalized units where (0,0) is the canvas
/// centre, (±0.5, 0) are the left/right edges, and (0, ±0.5) are the top/bottom edges.
/// Radius and area dimensions are in the same units (0.5 = half canvas width).
public struct LoomLight: Codable, Equatable, Identifiable, Sendable {

    public var id:      UUID
    public var name:    String
    public var type:    LightType
    public var isEnabled: Bool

    // MARK: Position (canvas-normalized, origin = centre)
    public var positionXDriver: DoubleDriver   // base = canvas-X (-0.5 left … 0.5 right)
    public var positionYDriver: DoubleDriver   // base = canvas-Y (-0.5 bottom … 0.5 top)

    // MARK: Common
    public var intensityDriver: DoubleDriver   // 0–1, default 1
    public var color:           LoomColor      // default white; tints the lit region
    public var falloff:         Double         // gradient shape: 1=linear, 2=quadratic (default)

    // MARK: Omni + Spot — radial reach
    public var radiusDriver:    DoubleDriver   // canvas-normalized radius (default 0.35)

    // MARK: Spot only
    public var directionDriver: DoubleDriver   // radians; 0=right, π/2=up
    public var coneAngleDriver: DoubleDriver   // half-angle of inner cone (radians, default π/6=30°)
    public var penumbraAngle:   Double         // additional half-angle for soft edge (radians, default π/12)

    // MARK: Area only
    public var widthDriver:     DoubleDriver   // canvas-normalized full width (default 0.4)
    public var heightDriver:    DoubleDriver   // canvas-normalized full height (default 0.25)
    public var rotationDriver:  DoubleDriver   // radians (default 0)
    public var edgeSoftness:    Double         // soft-edge feather in canvas-normalized units (default 0.04)

    // MARK: Layer scope
    /// Layer IDs this light is restricted to. Empty = affects every layer that has
    /// `receivesLighting = true` (the original behaviour, and the default for all
    /// existing project files).
    public var affectedLayerIDs: [UUID]

    // MARK: - Init (omni defaults)

    public init(
        id:             UUID            = UUID(),
        name:           String          = "Light",
        type:           LightType       = .omni,
        isEnabled:      Bool            = true,
        positionXDriver: DoubleDriver   = .zero,
        positionYDriver: DoubleDriver   = .zero,
        intensityDriver: DoubleDriver   = .one,
        color:           LoomColor      = .white,
        falloff:         Double         = 2.0,
        radiusDriver:    DoubleDriver   = DoubleDriver(mode: .constant, base: 0.35),
        directionDriver: DoubleDriver   = .zero,
        coneAngleDriver: DoubleDriver   = DoubleDriver(mode: .constant, base: .pi / 6),
        penumbraAngle:   Double         = .pi / 12,
        widthDriver:     DoubleDriver   = DoubleDriver(mode: .constant, base: 0.4),
        heightDriver:    DoubleDriver   = DoubleDriver(mode: .constant, base: 0.25),
        rotationDriver:  DoubleDriver   = .zero,
        edgeSoftness:    Double         = 0.04,
        affectedLayerIDs: [UUID]        = []
    ) {
        self.id               = id
        self.name             = name
        self.type             = type
        self.isEnabled        = isEnabled
        self.positionXDriver  = positionXDriver
        self.positionYDriver  = positionYDriver
        self.intensityDriver  = intensityDriver
        self.color            = color
        self.falloff          = falloff
        self.radiusDriver     = radiusDriver
        self.directionDriver  = directionDriver
        self.coneAngleDriver  = coneAngleDriver
        self.penumbraAngle    = penumbraAngle
        self.widthDriver      = widthDriver
        self.heightDriver     = heightDriver
        self.rotationDriver   = rotationDriver
        self.edgeSoftness     = edgeSoftness
        self.affectedLayerIDs = affectedLayerIDs
    }

    // MARK: - Codable (safe defaults for missing fields)

    private enum CodingKeys: String, CodingKey {
        case id, name, type, isEnabled
        case positionXDriver, positionYDriver
        case intensityDriver, color, falloff
        case radiusDriver
        case directionDriver, coneAngleDriver, penumbraAngle
        case widthDriver, heightDriver, rotationDriver, edgeSoftness
        case affectedLayerIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decodeIfPresent(UUID.self,          forKey: .id)              ?? UUID()
        name             = try c.decodeIfPresent(String.self,        forKey: .name)            ?? "Light"
        type             = try c.decodeIfPresent(LightType.self,     forKey: .type)            ?? .omni
        isEnabled        = try c.decodeIfPresent(Bool.self,          forKey: .isEnabled)       ?? true
        positionXDriver  = try c.decodeIfPresent(DoubleDriver.self,  forKey: .positionXDriver) ?? .zero
        positionYDriver  = try c.decodeIfPresent(DoubleDriver.self,  forKey: .positionYDriver) ?? .zero
        intensityDriver  = try c.decodeIfPresent(DoubleDriver.self,  forKey: .intensityDriver) ?? .one
        color            = try c.decodeIfPresent(LoomColor.self,     forKey: .color)           ?? .white
        falloff          = try c.decodeIfPresent(Double.self,        forKey: .falloff)         ?? 2.0
        radiusDriver     = try c.decodeIfPresent(DoubleDriver.self,  forKey: .radiusDriver)    ?? DoubleDriver(mode: .constant, base: 0.35)
        directionDriver  = try c.decodeIfPresent(DoubleDriver.self,  forKey: .directionDriver) ?? .zero
        coneAngleDriver  = try c.decodeIfPresent(DoubleDriver.self,  forKey: .coneAngleDriver) ?? DoubleDriver(mode: .constant, base: .pi / 6)
        penumbraAngle    = try c.decodeIfPresent(Double.self,        forKey: .penumbraAngle)   ?? .pi / 12
        widthDriver      = try c.decodeIfPresent(DoubleDriver.self,  forKey: .widthDriver)     ?? DoubleDriver(mode: .constant, base: 0.4)
        heightDriver     = try c.decodeIfPresent(DoubleDriver.self,  forKey: .heightDriver)    ?? DoubleDriver(mode: .constant, base: 0.25)
        rotationDriver   = try c.decodeIfPresent(DoubleDriver.self,  forKey: .rotationDriver)  ?? .zero
        edgeSoftness     = try c.decodeIfPresent(Double.self,        forKey: .edgeSoftness)    ?? 0.04
        affectedLayerIDs = try c.decodeIfPresent([UUID].self,        forKey: .affectedLayerIDs) ?? []
    }
}

// MARK: - LightingConfig

public struct LightingConfig: Codable, Equatable, Sendable {
    /// Master switch. When `false`, all lighting passes are skipped — zero render overhead.
    public var isEnabled: Bool
    public var lights:    [LoomLight]

    public init(isEnabled: Bool = false, lights: [LoomLight] = []) {
        self.isEnabled = isEnabled
        self.lights    = lights
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, lights }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self,       forKey: .isEnabled) ?? false
        lights    = try c.decodeIfPresent([LoomLight].self, forKey: .lights)   ?? []
    }
}
