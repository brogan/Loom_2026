import Foundation

/// Encode and decode `ProjectConfig` as JSON.
///
/// All config structs are `Codable`, so round-trips are lossless (within
/// floating-point precision).  This is the write path for the Swift-native
/// project format; `XMLConfigLoader` remains the read path for legacy projects.
public enum JSONConfigLoader {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Encode

    public static func encode(_ config: ProjectConfig) throws -> Data {
        try encoder.encode(config)
    }

    public static func save(_ config: ProjectConfig, to url: URL) throws {
        let data = try encode(config)
        try data.write(to: url, options: .atomicWrite)
    }

    // MARK: - Decode

    public static func decode(from data: Data) throws -> ProjectConfig {
        try decoder.decode(ProjectConfig.self, from: data)
    }

    public static func load(url: URL) throws -> ProjectConfig {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
