// MARK: - Render-change enumerations

/// Whether a render parameter steps through its palette sequentially or randomly.
public enum ChangeKind: String, Codable, Sendable, CaseIterable {
    case sequential = "SEQ"
    case random     = "RAN"
}

/// Direction the palette index moves each step.
public enum ChangeMotion: String, Codable, Sendable, CaseIterable {
    case up       = "UP"
    case down     = "DOWN"
    case pingPong = "PING_PONG"
}

/// Whether the index advances every frame or pauses for a random number of frames.
public enum ChangeCycle: String, Codable, Sendable, CaseIterable {
    case constant = "CONSTANT"
    case pausing  = "PAUSING"
}

/// Scale at which the change is applied — determines which polygon the palette
/// index is shared across.
public enum ChangeScale: String, Codable, Sendable, CaseIterable {
    case poly   = "POLY"
    case sprite = "SPRITE"
    case point  = "POINT"
    /// Legacy/back-compat value from early Swift configs. Treat like sprite-level.
    case global = "GLOBAL"
}

// MARK: - Individual change types

/// Animated fill-colour change: steps through a `LoomColor` palette.
public struct FillColorChange: Equatable, Codable, Sendable {
    public var enabled:  Bool
    public var kind:     ChangeKind
    public var motion:   ChangeMotion
    public var cycle:    ChangeCycle
    public var scale:    ChangeScale
    public var palette:  [LoomColor]
    public var pauseMax: Int

    public init(
        enabled:  Bool         = false,
        kind:     ChangeKind   = .random,
        motion:   ChangeMotion = .pingPong,
        cycle:    ChangeCycle  = .constant,
        scale:    ChangeScale  = .poly,
        palette:  [LoomColor]  = [],
        pauseMax: Int          = 0
    ) {
        self.enabled  = enabled; self.kind    = kind
        self.motion   = motion;  self.cycle   = cycle
        self.scale    = scale;   self.palette = palette
        self.pauseMax = pauseMax
    }
}

/// Animated stroke-colour change: steps through a `LoomColor` palette.
public struct StrokeColorChange: Equatable, Codable, Sendable {
    public var enabled:  Bool
    public var kind:     ChangeKind
    public var motion:   ChangeMotion
    public var cycle:    ChangeCycle
    public var scale:    ChangeScale
    public var palette:  [LoomColor]
    public var pauseMax: Int

    public init(
        enabled:  Bool         = false,
        kind:     ChangeKind   = .sequential,
        motion:   ChangeMotion = .up,
        cycle:    ChangeCycle  = .constant,
        scale:    ChangeScale  = .poly,
        palette:  [LoomColor]  = [],
        pauseMax: Int          = 0
    ) {
        self.enabled  = enabled; self.kind    = kind
        self.motion   = motion;  self.cycle   = cycle
        self.scale    = scale;   self.palette = palette
        self.pauseMax = pauseMax
    }
}

/// Animated stroke-width change: steps through a numeric size palette.
public struct StrokeWidthChange: Equatable, Codable, Sendable {
    public var enabled:      Bool
    public var kind:         ChangeKind
    public var motion:       ChangeMotion
    public var cycle:        ChangeCycle
    public var scale:        ChangeScale
    public var sizePalette:  [Double]
    public var pauseMax:     Int

    public init(
        enabled:     Bool         = false,
        kind:        ChangeKind   = .random,
        motion:      ChangeMotion = .up,
        cycle:       ChangeCycle  = .constant,
        scale:       ChangeScale  = .poly,
        sizePalette: [Double]     = [],
        pauseMax:    Int          = 0
    ) {
        self.enabled     = enabled; self.kind       = kind
        self.motion      = motion;  self.cycle      = cycle
        self.scale       = scale;   self.sizePalette = sizePalette
        self.pauseMax    = pauseMax
    }
}

/// All render-parameter changes declared inside a single `<Renderer>`.
///
/// Each change is optional; a nil value means that parameter is static.
public struct RendererChanges: Equatable, Codable, Sendable {
    public var fillColor:    FillColorChange?
    public var strokeColor:  StrokeColorChange?
    public var strokeWidth:  StrokeWidthChange?

    public init(
        fillColor:   FillColorChange?   = nil,
        strokeColor: StrokeColorChange? = nil,
        strokeWidth: StrokeWidthChange? = nil
    ) {
        self.fillColor   = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    /// True when no changes are defined.
    public var isEmpty: Bool {
        fillColor == nil && strokeColor == nil && strokeWidth == nil
    }
}

// MARK: - Renderer drivers

/// Continuous/keyframed renderer parameters evaluated against global frame time.
public struct RendererDrivers: Equatable, Codable, Sendable {
    public var fillColor: ColorDriver?
    public var strokeColor: ColorDriver?
    public var strokeWidth: DoubleDriver = .one
    /// Per-renderer alpha multiplier. 1 = fully opaque, 0 = invisible.
    public var opacity: DoubleDriver = .one
    /// Per-renderer Gaussian blur radius in logical pixels. 0 = off.
    public var blur: DoubleDriver = .zero

    /// Blend factor between `gradientConfig` (0) and `gradientConfigB` (1).
    /// Only evaluated when `gradientConfigB` is non-nil and mode is gradient.
    public var gradientBlend: DoubleDriver = .zero

    public init(
        fillColor: ColorDriver? = nil,
        strokeColor: ColorDriver? = nil,
        strokeWidth: DoubleDriver = .one,
        opacity: DoubleDriver = .one,
        blur: DoubleDriver = .zero,
        gradientBlend: DoubleDriver = .zero
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.blur = blur
        self.gradientBlend = gradientBlend
    }

    private enum CodingKeys: String, CodingKey {
        case fillColor, strokeColor, strokeWidth, opacity, blur, gradientBlend
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fillColor = try c.decodeIfPresent(ColorDriver.self, forKey: .fillColor)
        strokeColor = try c.decodeIfPresent(ColorDriver.self, forKey: .strokeColor)
        strokeWidth = try c.decodeIfPresent(DoubleDriver.self, forKey: .strokeWidth) ?? .one
        opacity = try c.decodeIfPresent(DoubleDriver.self, forKey: .opacity) ?? .one
        blur = try c.decodeIfPresent(DoubleDriver.self, forKey: .blur) ?? .zero
        gradientBlend = try c.decodeIfPresent(DoubleDriver.self, forKey: .gradientBlend) ?? .zero
    }
}

// MARK: - Gradient

public enum GradientType: String, Codable, CaseIterable, Sendable {
    case linear = "linear"
    case radial = "radial"

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .radial: return "Radial"
        }
    }
}

/// A single colour stop in a gradient, position in 0…1.
public struct GradientStop: Equatable, Codable, Sendable {
    public var color:    LoomColor
    public var position: Double

    public init(color: LoomColor = .black, position: Double = 0) {
        self.color = color; self.position = position
    }
}

/// Gradient fill configuration attached to a `Renderer`.
///
/// Control points (x0/y0, x1/y1) are expressed as fractions of the polygon's
/// screen-space bounding box: (0,0) = top-left, (1,1) = bottom-right.
/// For radial gradients `x0/y0` is the centre and `radius` is a fraction of
/// `max(bbox.width, bbox.height)`.
public struct GradientConfig: Equatable, Codable, Sendable {
    public var type:   GradientType
    public var stops:  [GradientStop]
    /// Linear start / radial centre — X as fraction of bbox width.
    public var x0: Double
    /// Linear start / radial centre — Y as fraction of bbox height.
    public var y0: Double
    /// Linear end — X as fraction of bbox width. (Unused for radial.)
    public var x1: Double
    /// Linear end — Y as fraction of bbox height. (Unused for radial.)
    public var y1: Double
    /// Radial only: radius as fraction of `max(bbox.width, bbox.height)`.
    public var radius: Double

    public init(
        type:   GradientType   = .linear,
        stops:  [GradientStop] = [GradientStop(color: .white, position: 0),
                                   GradientStop(color: .black, position: 1)],
        x0: Double = 0.5, y0: Double = 0.0,
        x1: Double = 0.5, y1: Double = 1.0,
        radius: Double = 0.5
    ) {
        self.type = type; self.stops = stops
        self.x0 = x0; self.y0 = y0
        self.x1 = x1; self.y1 = y1
        self.radius = radius
    }

    public init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        type   = try c.decodeIfPresent(GradientType.self,    forKey: .type)   ?? .linear
        stops  = try c.decodeIfPresent([GradientStop].self,  forKey: .stops)  ?? []
        x0     = try c.decodeIfPresent(Double.self, forKey: .x0) ?? 0.5
        y0     = try c.decodeIfPresent(Double.self, forKey: .y0) ?? 0.0
        x1     = try c.decodeIfPresent(Double.self, forKey: .x1) ?? 0.5
        y1     = try c.decodeIfPresent(Double.self, forKey: .y1) ?? 1.0
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.5
    }

    /// Linearly interpolate all numeric fields and stop colours toward `other`.
    /// Stops are paired by index; if `other` has fewer stops, the extra A stops blend toward themselves.
    public func lerped(to other: GradientConfig, t: Double) -> GradientConfig {
        let t = max(0, min(1, t))
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func lerp8(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        var blendedStops: [GradientStop] = []
        for i in stops.indices {
            let sa = stops[i]
            let sb = other.stops.indices.contains(i) ? other.stops[i] : sa
            blendedStops.append(GradientStop(
                color: LoomColor(r: lerp8(sa.color.r, sb.color.r),
                                 g: lerp8(sa.color.g, sb.color.g),
                                 b: lerp8(sa.color.b, sb.color.b),
                                 a: lerp8(sa.color.a, sb.color.a)),
                position: lerp(sa.position, sb.position)
            ))
        }
        return GradientConfig(
            type: t < 0.5 ? type : other.type,
            stops: blendedStops,
            x0: lerp(x0, other.x0), y0: lerp(y0, other.y0),
            x1: lerp(x1, other.x1), y1: lerp(y1, other.y1),
            radius: lerp(radius, other.radius)
        )
    }
}

// MARK: - Renderer mode

/// Rendering output mode for a `Renderer`.
public enum RendererMode: String, CaseIterable, Codable, Sendable {
    case points               = "POINTS"
    case stroked              = "STROKED"
    case filled               = "FILLED"
    case filledStroked        = "FILLED_STROKED"
    case gradientFilled       = "GRADIENT_FILLED"
    case gradientFilledStroked = "GRADIENT_FILLED_STROKED"
    case brushed              = "BRUSHED"
    case stenciled            = "STENCILED"
    case stamped              = "STAMPED"
}

/// How a `RendererSet` cycles through its renderers.
public enum PlaybackMode: String, Codable, Sendable {
    case `static`  = "STATIC"
    case sequential = "SEQUENTIAL"
    case random    = "RANDOM"
    case all       = "ALL"
}

/// Controls playback behaviour of a `RendererSet`.
public struct RendererPlaybackConfig: Equatable, Codable, Sendable {
    public var mode: PlaybackMode             = .sequential
    public var preferredRenderer: String      = ""
    public var preferredProbability: Double   = 50.0
    public var modifyInternalParameters: Bool = false

    public init() {}
}

/// A single rendering style.
///
/// Corresponds to `<Renderer>` in `rendering.xml`.
/// `changes` holds any animated parameter variations declared in `<Changes>`.
public struct Renderer: Equatable, Codable, Sendable {
    public var name: String
    public var enabled: Bool
    public var mode: RendererMode
    public var strokeWidth: Double
    public var strokeColor: LoomColor
    public var fillColor: LoomColor
    public var pointSize: Double
    public var holdLength: Int
    /// Gaussian blur radius in logical pixels applied to this renderer's output. 0 = off.
    public var blurRadius: Double
    /// Animated render-parameter changes. Empty when the renderer is static.
    public var changes: RendererChanges
    /// Continuous/keyframed render-parameter drivers. Nil for static legacy renderers.
    public var drivers: RendererDrivers?
    /// Non-nil when `mode == .brushed`.
    public var brushConfig: BrushConfig?
    /// Non-nil when `mode == .stamped` (or `.stenciled`).
    public var stencilConfig: StencilConfig?
    /// Non-nil when `mode == .gradientFilled` or `.gradientFilledStroked`.
    public var gradientConfig: GradientConfig?
    /// Optional second gradient target for blend-driver animation.
    public var gradientConfigB: GradientConfig?

    public init(
        name: String              = "",
        enabled: Bool             = true,
        mode: RendererMode        = .stroked,
        strokeWidth: Double       = 1.0,
        strokeColor: LoomColor    = .black,
        fillColor: LoomColor      = .black,
        pointSize: Double         = 2.0,
        holdLength: Int           = 1,
        blurRadius: Double        = 0.0,
        changes: RendererChanges  = RendererChanges(),
        drivers: RendererDrivers? = nil,
        brushConfig: BrushConfig?    = nil,
        stencilConfig: StencilConfig? = nil,
        gradientConfig: GradientConfig? = nil,
        gradientConfigB: GradientConfig? = nil
    ) {
        self.name = name; self.enabled = enabled; self.mode = mode
        self.strokeWidth = strokeWidth; self.strokeColor = strokeColor
        self.fillColor = fillColor; self.pointSize = pointSize
        self.holdLength = holdLength; self.blurRadius = blurRadius
        self.changes = changes; self.drivers = drivers
        self.brushConfig = brushConfig; self.stencilConfig = stencilConfig
        self.gradientConfig = gradientConfig; self.gradientConfigB = gradientConfigB
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled, mode, strokeWidth, strokeColor, fillColor,
             pointSize, holdLength, blurRadius, changes, drivers,
             brushConfig, stencilConfig, gradientConfig, gradientConfigB
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name            = try c.decodeIfPresent(String.self,           forKey: .name)            ?? ""
        enabled         = try c.decodeIfPresent(Bool.self,             forKey: .enabled)         ?? true
        mode            = try c.decodeIfPresent(RendererMode.self,     forKey: .mode)            ?? .stroked
        strokeWidth     = try c.decodeIfPresent(Double.self,           forKey: .strokeWidth)     ?? 1.0
        strokeColor     = try c.decodeIfPresent(LoomColor.self,        forKey: .strokeColor)     ?? .black
        fillColor       = try c.decodeIfPresent(LoomColor.self,        forKey: .fillColor)       ?? .black
        pointSize       = try c.decodeIfPresent(Double.self,           forKey: .pointSize)       ?? 2.0
        holdLength      = try c.decodeIfPresent(Int.self,              forKey: .holdLength)      ?? 1
        blurRadius      = try c.decodeIfPresent(Double.self,           forKey: .blurRadius)      ?? 0.0
        changes         = try c.decodeIfPresent(RendererChanges.self,  forKey: .changes)         ?? RendererChanges()
        drivers         = try c.decodeIfPresent(RendererDrivers.self,  forKey: .drivers)
        brushConfig     = try c.decodeIfPresent(BrushConfig.self,      forKey: .brushConfig)
        stencilConfig   = try c.decodeIfPresent(StencilConfig.self,    forKey: .stencilConfig)
        gradientConfig  = try c.decodeIfPresent(GradientConfig.self,   forKey: .gradientConfig)
        gradientConfigB = try c.decodeIfPresent(GradientConfig.self,   forKey: .gradientConfigB)
    }
}

/// A named collection of renderers with playback configuration.
public struct RendererSet: Equatable, Codable, Sendable {
    public var name: String
    public var playbackConfig: RendererPlaybackConfig
    public var renderers: [Renderer]

    public init(name: String, playbackConfig: RendererPlaybackConfig = .init(), renderers: [Renderer] = []) {
        self.name = name; self.playbackConfig = playbackConfig; self.renderers = renderers
    }

    private enum CodingKeys: String, CodingKey {
        case name, playbackConfig, renderers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name         = try c.decodeIfPresent(String.self,                  forKey: .name)         ?? ""
        playbackConfig = try c.decodeIfPresent(RendererPlaybackConfig.self, forKey: .playbackConfig) ?? RendererPlaybackConfig()
        renderers    = try c.decodeIfPresent([Renderer].self,              forKey: .renderers)    ?? []
    }
}

/// All renderer sets loaded from `rendering.xml`.
public struct RendererSetLibrary: Equatable, Codable, Sendable {
    public var name: String
    public var rendererSets: [RendererSet]

    public init(name: String = "", rendererSets: [RendererSet] = []) {
        self.name = name; self.rendererSets = rendererSets
    }

    private enum CodingKeys: String, CodingKey {
        case name, rendererSets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name         = try c.decodeIfPresent(String.self,          forKey: .name)         ?? ""
        rendererSets = try c.decodeIfPresent([RendererSet].self,   forKey: .rendererSets) ?? []
    }

    /// Look up a renderer set by name. Returns `nil` when not found.
    public func rendererSet(named name: String) -> RendererSet? {
        rendererSets.first { $0.name == name }
    }
}

/// Root wrapper matching the `<RenderingConfig>` element.
public struct RenderingConfig: Equatable, Codable, Sendable {
    public var library: RendererSetLibrary

    public init(library: RendererSetLibrary = RendererSetLibrary()) {
        self.library = library
    }
}
