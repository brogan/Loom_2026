/// Shape source type — how a `ShapeDef` acquires its polygon geometry.
public enum ShapeSourceType: String, Codable, Sendable {
    case polygonSet     = "POLYGON_SET"
    case regularPolygon = "REGULAR_POLYGON"
    case inlinePoints   = "INLINE_POINTS"
    case openCurveSet   = "OPEN_CURVE_SET"
    case pointSet       = "POINT_SET"
    case ovalSet        = "OVAL_SET"
    case unknown        = ""

    /// Initialise from an XML `type` attribute, accepting both canonical
    /// `UPPER_SNAKE_CASE` and legacy camelCase variants (e.g. `"ovalSet"`).
    public init(xmlName: String) {
        if let v = ShapeSourceType(rawValue: xmlName) { self = v; return }
        switch xmlName {
        case "ovalSet":      self = .ovalSet
        case "openCurveSet": self = .openCurveSet
        case "pointSet":     self = .pointSet
        case "polygonSet":   self = .polygonSet
        default:             self = .unknown
        }
    }
}

/// One shape definition within a `ShapeSet`.
///
/// Corresponds to `<Shape>` in `shapes.xml`.
public struct ShapeDef: Codable, Sendable {
    public var name: String
    public var sourceType: ShapeSourceType
    /// Non-empty when `sourceType == .polygonSet`.
    public var polygonSetName: String
    /// Non-empty when `sourceType == .openCurveSet`.
    public var openCurveSetName: String
    /// Non-empty when `sourceType == .pointSet`.
    public var pointSetName: String
    /// Non-empty when `sourceType == .ovalSet`.
    public var ovalSetName: String
    /// Number of sides when `sourceType == .regularPolygon`.
    public var regularPolygonSides: Int
    /// Optional name of the `SubdivisionParamsSet` applied to this shape.
    public var subdivisionParamsSetName: String

    public init(
        name: String,
        sourceType: ShapeSourceType   = .unknown,
        polygonSetName: String        = "",
        openCurveSetName: String      = "",
        pointSetName: String          = "",
        ovalSetName: String           = "",
        regularPolygonSides: Int      = 0,
        subdivisionParamsSetName: String = ""
    ) {
        self.name                    = name
        self.sourceType              = sourceType
        self.polygonSetName          = polygonSetName
        self.openCurveSetName        = openCurveSetName
        self.pointSetName            = pointSetName
        self.ovalSetName             = ovalSetName
        self.regularPolygonSides     = regularPolygonSides
        self.subdivisionParamsSetName = subdivisionParamsSetName
    }

    public init(from decoder: Decoder) throws {
        let c                    = try decoder.container(keyedBy: CodingKeys.self)
        name                     = try c.decodeIfPresent(String.self,          forKey: .name)                     ?? ""
        sourceType               = try c.decodeIfPresent(ShapeSourceType.self, forKey: .sourceType)               ?? .unknown
        polygonSetName           = try c.decodeIfPresent(String.self,          forKey: .polygonSetName)           ?? ""
        openCurveSetName         = try c.decodeIfPresent(String.self,          forKey: .openCurveSetName)         ?? ""
        pointSetName             = try c.decodeIfPresent(String.self,          forKey: .pointSetName)             ?? ""
        ovalSetName              = try c.decodeIfPresent(String.self,          forKey: .ovalSetName)              ?? ""
        regularPolygonSides      = try c.decodeIfPresent(Int.self,             forKey: .regularPolygonSides)      ?? 0
        subdivisionParamsSetName = try c.decodeIfPresent(String.self,          forKey: .subdivisionParamsSetName) ?? ""
    }
}

/// A named group of shape definitions.
public struct ShapeSet: Codable, Sendable {
    public var name: String
    public var shapes: [ShapeDef]

    public init(name: String, shapes: [ShapeDef] = []) {
        self.name = name; self.shapes = shapes
    }
}

/// The top-level shape library loaded from `shapes.xml`.
public struct ShapeLibrary: Codable, Sendable {
    public var name: String
    public var shapeSets: [ShapeSet]

    public init(name: String = "", shapeSets: [ShapeSet] = []) {
        self.name = name; self.shapeSets = shapeSets
    }
}

/// Root wrapper matching the `<ShapeConfig>` element.
public struct ShapeConfig: Codable, Sendable {
    public var library: ShapeLibrary

    public init(library: ShapeLibrary = ShapeLibrary()) {
        self.library = library
    }
}
