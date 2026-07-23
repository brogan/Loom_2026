import Foundation

public enum ConvolutionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case torsion = "Torsion"
    case shear   = "Shear"
    case bend    = "Bend"
}

/// Where a Torsion/Shear pass's reference point is resolved from.
public enum ConvolutionCentre: String, Codable, CaseIterable, Equatable, Sendable {
    /// Average of all points (`Polygon2D.centroid`) — the same "anchor-average"
    /// convention already used elsewhere for both closed and open shapes, so no
    /// separate open-curve fallback is needed.
    case centroid    = "Centroid"
    /// Geometric centre of the point list's axis-aligned bounding box — differs
    /// from centroid whenever points are unevenly distributed (e.g. more control
    /// points bunched toward one side).
    case boundingBox = "Bounding Box Centre"
    /// A fixed, user-specified canvas point.
    case custom      = "Custom"
}

/// Radial falloff shape for Torsion — how rotation angle varies with distance
/// from the reference centre.
public enum ConvolutionTwistFalloff: String, Codable, CaseIterable, Equatable, Sendable {
    /// Angle grows proportionally with distance from centre (unbounded outward) —
    /// the classic spiral/pinwheel twist. Distant points can rotate far past
    /// `twistAmount` itself.
    case linear   = "Linear"
    /// Angle is strongest near the centre and decays smoothly outward, never
    /// exceeding `twistAmount` — a gentler, localized torsion that doesn't
    /// over-rotate distant points.
    case inverse  = "Inverse"
    /// Every point rotates by exactly `twistAmount` regardless of distance —
    /// degenerates to a plain rigid rotation of the whole shape (already available
    /// at the sprite level). Kept as an explicit, labelled corner case rather than
    /// removed, so the three options form a complete range from "uniform" to
    /// "unbounded spiral."
    case constant = "Constant"
}

/// Convolution — a continuous coordinate-space warp (Torsion, Shear) applied to
/// an already-resolved point list. Unlike Involution/Extension it neither adds
/// nor removes vertices; unlike Evolution it isn't stateful or trajectory-based.
/// One `operationType` active per pass; stack multiple passes (e.g. a Torsion
/// pass followed by a Shear pass) to combine effects — see Specs/Convolution.md
/// §8 for why this mirrors Extension's Branch/Extrude picker rather than
/// Dissolution's several-simultaneous-toggles model.
public struct ConvolutionParams: Equatable, Codable, Sendable {
    public var name:          String
    public var enabled:       Bool
    public var operationType: ConvolutionOperationType

    // Torsion settings (operationType == .torsion)
    public var twistCentre:          ConvolutionCentre
    public var twistCentreCustomX:   Double
    public var twistCentreCustomY:   Double
    public var twistAmount:          DoubleDriver  // degrees of rotation at twistReferenceRadius (same degrees convention as branchAngle/extrusionDepartureAngle)
    public var twistFalloff:         ConvolutionTwistFalloff
    public var twistReferenceRadius: Double         // canvas units; normalizes the falloff curve

    // Shear settings (operationType == .shear)
    public var shearAxis:           Double          // degrees, direction of the shear axis
    public var shearAmount:         DoubleDriver     // displacement per unit distance along the perpendicular
    public var shearOrigin:         ConvolutionCentre
    public var shearOriginCustomX:  Double
    public var shearOriginCustomY:  Double

    // Bend settings (operationType == .bend)
    public var bendAxis:           Double           // degrees; direction of the "along" bend axis
    public var bendCurvature:      DoubleDriver      // inverse radius of the virtual bend circle; 0 = straight
    public var bendCentre:         ConvolutionCentre // reference point the axis passes through ("across" = 0)
    public var bendCentreCustomX:  Double
    public var bendCentreCustomY:  Double
    public var bendOrigin:         Double            // 0–1 position along the shape's own extent on bendAxis where curvature is centred (0.5 = symmetric outward bend from the middle)

    public init(
        name:                  String                  = "",
        enabled:               Bool                    = true,
        operationType:         ConvolutionOperationType = .torsion,
        twistCentre:           ConvolutionCentre        = .centroid,
        twistCentreCustomX:    Double                   = 0.0,
        twistCentreCustomY:    Double                   = 0.0,
        twistAmount:           DoubleDriver             = .constant(30.0),
        twistFalloff:          ConvolutionTwistFalloff  = .linear,
        twistReferenceRadius:  Double                   = 0.5,
        shearAxis:             Double                   = 0.0,
        shearAmount:           DoubleDriver             = .constant(0.3),
        shearOrigin:           ConvolutionCentre        = .centroid,
        shearOriginCustomX:    Double                   = 0.0,
        shearOriginCustomY:    Double                   = 0.0,
        bendAxis:              Double                   = 0.0,
        bendCurvature:         DoubleDriver             = .constant(1.0),
        bendCentre:            ConvolutionCentre        = .centroid,
        bendCentreCustomX:     Double                   = 0.0,
        bendCentreCustomY:     Double                   = 0.0,
        bendOrigin:            Double                   = 0.5
    ) {
        self.name                 = name
        self.enabled              = enabled
        self.operationType        = operationType
        self.twistCentre          = twistCentre
        self.twistCentreCustomX   = twistCentreCustomX
        self.twistCentreCustomY   = twistCentreCustomY
        self.twistAmount          = twistAmount
        self.twistFalloff         = twistFalloff
        self.twistReferenceRadius = twistReferenceRadius
        self.shearAxis            = shearAxis
        self.shearAmount          = shearAmount
        self.shearOrigin          = shearOrigin
        self.shearOriginCustomX   = shearOriginCustomX
        self.shearOriginCustomY   = shearOriginCustomY
        self.bendAxis             = bendAxis
        self.bendCurvature        = bendCurvature
        self.bendCentre           = bendCentre
        self.bendCentreCustomX    = bendCentreCustomX
        self.bendCentreCustomY    = bendCentreCustomY
        self.bendOrigin           = bendOrigin
    }

    // MARK: - Codable
    //
    // Written manually (not synthesized), matching every other params struct in
    // this file family (ExtensionParams, EvolutionParams, ...), so that adding
    // Bend/Displacement fields later (Specs/Convolution.md §3.3–3.4) is just a
    // new `decodeIfPresent(...) ?? <default>` line rather than a breaking change
    // for projects saved before those fields existed.

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case twistCentre, twistCentreCustomX, twistCentreCustomY
        case twistAmount, twistFalloff, twistReferenceRadius
        case shearAxis, shearAmount, shearOrigin, shearOriginCustomX, shearOriginCustomY
        case bendAxis, bendCurvature, bendCentre, bendCentreCustomX, bendCentreCustomY, bendOrigin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name                 = try c.decodeIfPresent(String.self,                  forKey: .name)                 ?? ""
        enabled              = try c.decodeIfPresent(Bool.self,                    forKey: .enabled)              ?? true
        operationType        = try c.decodeIfPresent(ConvolutionOperationType.self, forKey: .operationType)        ?? .torsion
        twistCentre          = try c.decodeIfPresent(ConvolutionCentre.self,        forKey: .twistCentre)          ?? .centroid
        twistCentreCustomX   = try c.decodeIfPresent(Double.self,                  forKey: .twistCentreCustomX)   ?? 0.0
        twistCentreCustomY   = try c.decodeIfPresent(Double.self,                  forKey: .twistCentreCustomY)   ?? 0.0
        twistAmount          = try c.decodeIfPresent(DoubleDriver.self,            forKey: .twistAmount)          ?? .constant(30.0)
        twistFalloff         = try c.decodeIfPresent(ConvolutionTwistFalloff.self, forKey: .twistFalloff)         ?? .linear
        twistReferenceRadius = try c.decodeIfPresent(Double.self,                  forKey: .twistReferenceRadius) ?? 0.5
        shearAxis            = try c.decodeIfPresent(Double.self,                  forKey: .shearAxis)            ?? 0.0
        shearAmount          = try c.decodeIfPresent(DoubleDriver.self,            forKey: .shearAmount)          ?? .constant(0.3)
        shearOrigin          = try c.decodeIfPresent(ConvolutionCentre.self,        forKey: .shearOrigin)          ?? .centroid
        shearOriginCustomX   = try c.decodeIfPresent(Double.self,                  forKey: .shearOriginCustomX)   ?? 0.0
        shearOriginCustomY   = try c.decodeIfPresent(Double.self,                  forKey: .shearOriginCustomY)   ?? 0.0
        bendAxis             = try c.decodeIfPresent(Double.self,                  forKey: .bendAxis)             ?? 0.0
        bendCurvature        = try c.decodeIfPresent(DoubleDriver.self,            forKey: .bendCurvature)        ?? .constant(1.0)
        bendCentre           = try c.decodeIfPresent(ConvolutionCentre.self,        forKey: .bendCentre)           ?? .centroid
        bendCentreCustomX    = try c.decodeIfPresent(Double.self,                  forKey: .bendCentreCustomX)    ?? 0.0
        bendCentreCustomY    = try c.decodeIfPresent(Double.self,                  forKey: .bendCentreCustomY)    ?? 0.0
        bendOrigin           = try c.decodeIfPresent(Double.self,                  forKey: .bendOrigin)           ?? 0.5
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,                 forKey: .name)
        try c.encode(enabled,              forKey: .enabled)
        try c.encode(operationType,        forKey: .operationType)
        try c.encode(twistCentre,          forKey: .twistCentre)
        try c.encode(twistCentreCustomX,   forKey: .twistCentreCustomX)
        try c.encode(twistCentreCustomY,   forKey: .twistCentreCustomY)
        try c.encode(twistAmount,          forKey: .twistAmount)
        try c.encode(twistFalloff,         forKey: .twistFalloff)
        try c.encode(twistReferenceRadius, forKey: .twistReferenceRadius)
        try c.encode(shearAxis,            forKey: .shearAxis)
        try c.encode(shearAmount,          forKey: .shearAmount)
        try c.encode(shearOrigin,          forKey: .shearOrigin)
        try c.encode(shearOriginCustomX,   forKey: .shearOriginCustomX)
        try c.encode(shearOriginCustomY,   forKey: .shearOriginCustomY)
        try c.encode(bendAxis,             forKey: .bendAxis)
        try c.encode(bendCurvature,        forKey: .bendCurvature)
        try c.encode(bendCentre,           forKey: .bendCentre)
        try c.encode(bendCentreCustomX,    forKey: .bendCentreCustomX)
        try c.encode(bendCentreCustomY,    forKey: .bendCentreCustomY)
        try c.encode(bendOrigin,           forKey: .bendOrigin)
    }
}
