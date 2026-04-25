import Foundation

// MARK: - PointSetDef

/// References one point-set data file inside `<project>/pointSets/`.
public struct PointSetDef: Codable, Sendable {
    public var name:     String
    public var folder:   String
    public var filename: String

    public init(name: String = "", folder: String = "pointSets", filename: String = "") {
        self.name = name; self.folder = folder; self.filename = filename
    }
}

// MARK: - PointSetLibrary / PointConfig

public struct PointSetLibrary: Codable, Sendable {
    public var name:      String
    public var pointSets: [PointSetDef]

    public init(name: String = "", pointSets: [PointSetDef] = []) {
        self.name = name; self.pointSets = pointSets
    }
}

public struct PointConfig: Codable, Sendable {
    public var library: PointSetLibrary

    public init(library: PointSetLibrary = PointSetLibrary()) {
        self.library = library
    }
}
