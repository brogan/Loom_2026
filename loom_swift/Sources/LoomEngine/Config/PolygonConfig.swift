/// How the polygon data is represented in the source file.
public enum PolygonFileType: String, Codable, Sendable {
    case splinePolygon = "SPLINE_POLYGON"
    case linePolygon   = "LINE_POLYGON"
}

/// Parameters for an algorithmically-generated star/regular polygon
/// (`<Source type="regular">` in `polygons.xml`).
public struct RegularPolygonParams: Codable, Sendable {
    /// Number of outer tips; total vertex count = `totalPoints * 2`.
    public var totalPoints:      Int    = 4
    /// Inner radius expressed as a fraction of the outer radius (0.0–1.0).
    public var internalRadius:   Double = 0.5
    /// Rotation offset applied after generation (degrees).
    public var offset:           Double = 0.0
    public var scaleX:           Double = 1.0
    public var scaleY:           Double = 1.0
    public var rotationAngle:    Double = 0.0
    /// Translation; Scala stores centre as (0.5, 0.5) → Swift offset = transX − 0.5.
    public var transX:           Double = 0.5
    public var transY:           Double = 0.5
    public var positiveSynch:    Bool   = true
    public var synchMultiplier:  Double = 1.0
}

/// A named polygon set that references an external XML file **or** is generated
/// algorithmically from `RegularPolygonParams`.
///
/// Corresponds to `<PolygonSet>` in `polygons.xml`.
public struct PolygonSetDef: Codable, Sendable {
    /// The name used by `ShapeDef.polygonSetName` to reference this set.
    public var name: String
    /// Sub-folder inside `polygonSets/` where the file lives.  Usually "polygonSet".
    public var folder: String
    /// Filename of the polygon XML file.  Empty when `regularParams` is non-nil.
    public var filename: String
    /// Controls whether closed or open curves are produced.
    public var polygonType: PolygonFileType
    /// Non-nil when the polygon set is generated from a `<Source type="regular">` element.
    public var regularParams: RegularPolygonParams?

    public init(
        name: String,
        folder: String               = "polygonSet",
        filename: String             = "",
        polygonType: PolygonFileType = .splinePolygon,
        regularParams: RegularPolygonParams? = nil
    ) {
        self.name          = name
        self.folder        = folder
        self.filename      = filename
        self.polygonType   = polygonType
        self.regularParams = regularParams
    }
}

/// The library of polygon set definitions, loaded from `polygons.xml`.
public struct PolygonSetLibrary: Codable, Sendable {
    public var name: String
    public var polygonSets: [PolygonSetDef]

    public init(name: String = "", polygonSets: [PolygonSetDef] = []) {
        self.name = name; self.polygonSets = polygonSets
    }
}

/// Root wrapper matching the `<PolygonConfig>` element.
public struct PolygonConfig: Codable, Sendable {
    public var library: PolygonSetLibrary

    public init(library: PolygonSetLibrary = PolygonSetLibrary()) {
        self.library = library
    }
}
