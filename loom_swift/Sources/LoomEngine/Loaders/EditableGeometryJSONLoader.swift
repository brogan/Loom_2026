import Foundation

public struct EditableGeometryFile: Codable, Equatable, Sendable {
    public var schema: String
    public var schemaVersion: Int
    public var document: EditableGeometryDocument

    public init(
        schema: String = EditableGeometryJSONLoader.schema,
        schemaVersion: Int = EditableGeometryJSONLoader.schemaVersion,
        document: EditableGeometryDocument
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.document = document
    }
}

public enum EditableGeometryJSONError: Error, Equatable, LocalizedError {
    case unsupportedSchema(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported editable geometry schema: \(schema)"
        case .unsupportedVersion(let version):
            return "Unsupported editable geometry schema version: \(version)"
        }
    }
}

/// Swift-native JSON read/write for editable Geometry-tab authoring data.
///
/// This is the new standard authoring format for hand-edited geometry. Legacy
/// XML remains an import/export compatibility path through `Polygon2D` and
/// `XMLPolygonLoader`/`XMLPolygonWriter`.
public enum EditableGeometryJSONLoader {
    public static let schema = "loom.editableGeometry"
    public static let schemaVersion = 1

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    public static func encode(_ document: EditableGeometryDocument) throws -> Data {
        try encoder.encode(EditableGeometryFile(document: document))
    }

    public static func decode(from data: Data) throws -> EditableGeometryDocument {
        let file = try decoder.decode(EditableGeometryFile.self, from: data)
        guard file.schema == schema else {
            throw EditableGeometryJSONError.unsupportedSchema(file.schema)
        }
        guard file.schemaVersion == schemaVersion else {
            throw EditableGeometryJSONError.unsupportedVersion(file.schemaVersion)
        }
        return file.document
    }

    public static func save(_ document: EditableGeometryDocument, to url: URL) throws {
        let data = try encode(document)
        try data.write(to: url, options: .atomicWrite)
    }

    public static func load(url: URL) throws -> EditableGeometryDocument {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
