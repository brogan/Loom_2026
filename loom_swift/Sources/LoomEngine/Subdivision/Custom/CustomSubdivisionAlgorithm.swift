import Foundation

// MARK: - Point Primitive

/// Describes how one named point is computed relative to the current edge.
public struct PointPrimitive: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case vertexStart      = "V.start"
        case vertexEnd        = "V.end"
        case edgeFrac         = "edgeFrac"
        case edgeNormal       = "edgeNormal"
        case edgePrevFrac     = "edgePrevFrac"
        case edgePrevNormal   = "edgePrevNormal"
        case edgeNextFrac     = "edgeNextFrac"
        case edgeNextNormal   = "edgeNextNormal"
        case centroid         = "centroid"
        case centroidOffset   = "centroidOffset"
        case midringInterp    = "midringInterp"

        public var displayName: String {
            switch self {
            case .vertexStart:    return "Vertex Start"
            case .vertexEnd:      return "Vertex End"
            case .edgeFrac:       return "Edge t"
            case .edgeNormal:     return "Edge Normal"
            case .edgePrevFrac:   return "Prev Edge t"
            case .edgePrevNormal: return "Prev Normal"
            case .edgeNextFrac:   return "Next Edge t"
            case .edgeNextNormal: return "Next Normal"
            case .centroid:       return "Centroid"
            case .centroidOffset: return "Centroid Offset"
            case .midringInterp:  return "Midring"
            }
        }

        public var hasT: Bool {
            switch self {
            case .edgeFrac, .edgeNormal, .edgePrevFrac, .edgePrevNormal,
                 .edgeNextFrac, .edgeNextNormal: return true
            default: return false
            }
        }

        public var hasD: Bool {
            switch self {
            case .edgeNormal, .edgePrevNormal, .edgeNextNormal,
                 .centroidOffset: return true
            default: return false
            }
        }

        public var hasAngle: Bool { self == .centroidOffset }
        public var hasS: Bool     { self == .midringInterp }
    }

    public var kind: Kind
    public var t: Double       // fraction along edge [0, 1]
    public var d: Double       // inward perpendicular distance (signed)
    public var angle: Double   // degrees, for centroidOffset
    public var s: Double       // [0=midpoint, 1=centroid] for midringInterp

    public init(kind: Kind, t: Double = 0.5, d: Double = 0,
                angle: Double = 0, s: Double = 0.5) {
        self.kind  = kind
        self.t     = t
        self.d     = d
        self.angle = angle
        self.s     = s
    }

    // MARK: Convenience factories

    public static var vertexStart: PointPrimitive  { .init(kind: .vertexStart) }
    public static var vertexEnd: PointPrimitive    { .init(kind: .vertexEnd) }
    public static var centroid: PointPrimitive     { .init(kind: .centroid) }

    public static func edgeFrac(_ t: Double) -> PointPrimitive {
        .init(kind: .edgeFrac, t: t)
    }
    public static func edgeNormal(_ t: Double, _ d: Double) -> PointPrimitive {
        .init(kind: .edgeNormal, t: t, d: d)
    }
    public static func edgePrevFrac(_ t: Double) -> PointPrimitive {
        .init(kind: .edgePrevFrac, t: t)
    }
    public static func edgePrevNormal(_ t: Double, _ d: Double) -> PointPrimitive {
        .init(kind: .edgePrevNormal, t: t, d: d)
    }
    public static func edgeNextFrac(_ t: Double) -> PointPrimitive {
        .init(kind: .edgeNextFrac, t: t)
    }
    public static func edgeNextNormal(_ t: Double, _ d: Double) -> PointPrimitive {
        .init(kind: .edgeNextNormal, t: t, d: d)
    }
    public static func midringInterp(_ s: Double) -> PointPrimitive {
        .init(kind: .midringInterp, s: s)
    }
    public static func centroidOffset(_ d: Double, _ angle: Double) -> PointPrimitive {
        .init(kind: .centroidOffset, d: d, angle: angle)
    }
}

// MARK: - Named Point

public struct NamedPoint: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var primitive: PointPrimitive

    public init(id: UUID = UUID(), name: String, primitive: PointPrimitive) {
        self.id        = id
        self.name      = name
        self.primitive = primitive
    }
}

// MARK: - Child Polygon Definition

/// Ordered sequence of point name references forming one child polygon per edge.
///
/// Each name is either a built-in ("V.start", "V.end", "C"), a user-defined
/// point name (evaluated for the current edge), or a cross-edge reference of
/// the form "prev.NAME" or "next.NAME" (same point evaluated for the adjacent edge).
public struct ChildPolygonDef: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var pointNames: [String]

    public init(id: UUID = UUID(), name: String = "Child", pointNames: [String] = []) {
        self.id         = id
        self.name       = name
        self.pointNames = pointNames
    }
}

// MARK: - Custom Subdivision Algorithm

/// A user-defined subdivision algorithm stored in a SubdivisionParams.
///
/// For each edge i of the input polygon the engine evaluates all `points`
/// into a per-edge map, then assembles each `edgeChild` polygon from point
/// name references (current, prev, next edge).  If `globalChildPointName` is
/// set, one vertex is collected from every edge iteration to form a single
/// additional global polygon.
public struct CustomSubdivisionAlgorithm: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var points: [NamedPoint]
    public var edgeChildren: [ChildPolygonDef]
    public var globalChildPointName: String?

    public init(
        id: UUID = UUID(),
        name: String = "Custom",
        points: [NamedPoint] = [],
        edgeChildren: [ChildPolygonDef] = [],
        globalChildPointName: String? = nil
    ) {
        self.id                   = id
        self.name                 = name
        self.points               = points
        self.edgeChildren         = edgeChildren
        self.globalChildPointName = globalChildPointName
    }

    /// All resolvable base names (built-ins + user-defined).
    public var allBaseNames: [String] {
        ["V.start", "V.end", "C"] + points.map(\.name)
    }

    /// All resolvable names including prev/next cross-edge prefixes.
    public var allPointRefs: [String] {
        let base = allBaseNames
        let prev = base.filter { !["V.start","V.end","C"].contains($0) }.map { "prev.\($0)" }
        let next = base.filter { !["V.start","V.end","C"].contains($0) }.map { "next.\($0)" }
        return base + prev + next
    }

    // MARK: Starters

    /// Minimal starter: each edge → one triangle converging at centroid.
    public static var starter: CustomSubdivisionAlgorithm {
        CustomSubdivisionAlgorithm(
            name: "Custom",
            points: [
                NamedPoint(name: "mid", primitive: .edgeFrac(0.5)),
            ],
            edgeChildren: [
                ChildPolygonDef(name: "Child", pointNames: ["V.start", "V.end", "C"])
            ]
        )
    }
}
