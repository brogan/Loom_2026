import XCTest
@testable import LoomEngine
import Foundation

// MARK: - Shared fixture path

private var fixtureDir: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_051")
}

private func configFile(_ name: String) -> URL {
    fixtureDir.appendingPathComponent("configuration/\(name)")
}

private func polygonFile(_ name: String) -> URL {
    fixtureDir.appendingPathComponent("polygonSets/\(name)")
}

// MARK: - GlobalConfigTests

final class GlobalConfigTests: XCTestCase {

    func testLoadGlobalConfig() throws {
        let cfg = try XMLConfigLoader.loadGlobalConfig(url: configFile("global_config.xml"))
        XCTAssertEqual(cfg.name, "Test_051")
        XCTAssertEqual(cfg.width, 1080)
        XCTAssertEqual(cfg.height, 1080)
        XCTAssertEqual(cfg.qualityMultiple, 1)
        XCTAssertFalse(cfg.animating)
        XCTAssertFalse(cfg.fullscreen)
        XCTAssertTrue(cfg.subdividing)
        XCTAssertTrue(cfg.drawBackgroundOnce)
    }

    func testGlobalConfigColors() throws {
        let cfg = try XMLConfigLoader.loadGlobalConfig(url: configFile("global_config.xml"))
        XCTAssertEqual(cfg.borderColor, LoomColor(r: 0, g: 0, b: 0, a: 255))
        XCTAssertEqual(cfg.backgroundColor, LoomColor(r: 255, g: 255, b: 255, a: 255))
        XCTAssertEqual(cfg.overlayColor.a, 170, "overlay alpha should be 170")
    }

    func testGlobalConfigDefaults() {
        let cfg = GlobalConfig.default
        XCTAssertEqual(cfg.width, 1080)
        XCTAssertEqual(cfg.qualityMultiple, 1)
        XCTAssertTrue(cfg.subdividing)
    }

    func testGlobalConfigCodableRoundTrip() throws {
        let cfg = try XMLConfigLoader.loadGlobalConfig(url: configFile("global_config.xml"))
        let data    = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(GlobalConfig.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }
}

// MARK: - ShapeConfigTests

final class ShapeConfigTests: XCTestCase {

    func testLoadShapeConfig() throws {
        let cfg = try XMLConfigLoader.loadShapeConfig(url: configFile("shapes.xml"))
        XCTAssertEqual(cfg.library.shapeSets.count, 1, "one shape set")
        XCTAssertEqual(cfg.library.shapeSets[0].shapes.count, 1, "one shape")
    }

    func testShapeDef() throws {
        let cfg   = try XMLConfigLoader.loadShapeConfig(url: configFile("shapes.xml"))
        let shape = cfg.library.shapeSets[0].shapes[0]
        XCTAssertEqual(shape.name, "goodcat_mesh_mesh_sprite_001")
        XCTAssertEqual(shape.sourceType, .polygonSet)
        XCTAssertEqual(shape.polygonSetName, "Mesh")
        XCTAssertEqual(shape.subdivisionParamsSetName, "goodcat_mesh_mesh_Subdivide")
    }
}

// MARK: - PolygonConfigTests

final class PolygonConfigTests: XCTestCase {

    func testLoadPolygonConfig() throws {
        let cfg = try XMLConfigLoader.loadPolygonConfig(url: configFile("polygons.xml"))
        XCTAssertEqual(cfg.library.polygonSets.count, 2, "two polygon set defs")
    }

    func testPolygonSetDefFields() throws {
        let cfg    = try XMLConfigLoader.loadPolygonConfig(url: configFile("polygons.xml"))
        let first  = cfg.library.polygonSets[0]
        XCTAssertEqual(first.name, "Mesh")
        XCTAssertEqual(first.filename, "goodcat_mesh_mesh.xml")
        XCTAssertEqual(first.polygonType, .splinePolygon)
    }
}

// MARK: - SubdivisionConfigTests

final class SubdivisionConfigTests: XCTestCase {

    func testLoadSubdivisionConfig() throws {
        let cfg = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        XCTAssertEqual(cfg.paramsSets.count, 1, "one params set")
        XCTAssertEqual(cfg.paramsSets[0].name, "goodcat_mesh_mesh_Subdivide")
        XCTAssertEqual(cfg.paramsSets[0].params.count, 1, "one SubdivisionParams entry")
    }

    func testSubdivisionParamsFields() throws {
        let cfg    = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        let params = cfg.paramsSets[0].params[0]
        XCTAssertEqual(params.name, "A")
        XCTAssertEqual(params.subdivisionType, .quad)
        XCTAssertEqual(params.visibilityRule, .all)
        XCTAssertFalse(params.ranMiddle)
        XCTAssertEqual(params.ranDiv, 100.0, accuracy: 1e-10)
        XCTAssertTrue(params.continuous)
    }

    func testSubdivisionParamsRatios() throws {
        let cfg    = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        let params = cfg.paramsSets[0].params[0]
        XCTAssertEqual(params.lineRatios.x, 0.5, accuracy: 1e-10)
        XCTAssertEqual(params.lineRatios.y, 0.5, accuracy: 1e-10)
        XCTAssertEqual(params.controlPointRatios.x, 0.25, accuracy: 1e-10)
        XCTAssertEqual(params.controlPointRatios.y, 0.75, accuracy: 1e-10)
    }

    func testSubdivisionParamsSetLookup() throws {
        let cfg = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        XCTAssertNotNil(cfg.paramsSet(named: "goodcat_mesh_mesh_Subdivide"))
        XCTAssertNil(cfg.paramsSet(named: "nonexistent"))
    }

    func testSubdivisionTypeXMLNameRoundTrip() {
        for type in SubdivisionType.allCases {
            XCTAssertEqual(SubdivisionType(xmlName: type.xmlName), type,
                "\(type.xmlName) should round-trip")
        }
    }

    func testVisibilityRuleXMLNameRoundTrip() {
        for rule in VisibilityRule.allCases {
            XCTAssertEqual(VisibilityRule(xmlName: rule.xmlName), rule,
                "\(rule.xmlName) should round-trip")
        }
    }

    func testUnknownXMLNamesReturnNil() {
        XCTAssertNil(SubdivisionType(xmlName: "NOT_A_TYPE"))
        XCTAssertNil(VisibilityRule(xmlName: "NOT_A_RULE"))
    }
}

// MARK: - RenderingConfigTests

final class RenderingConfigTests: XCTestCase {

    func testLoadRenderingConfig() throws {
        let cfg = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        XCTAssertEqual(cfg.library.rendererSets.count, 1, "one renderer set")
        XCTAssertEqual(cfg.library.rendererSets[0].renderers.count, 1, "one renderer")
    }

    func testRendererFields() throws {
        let cfg      = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        let renderer = cfg.library.rendererSets[0].renderers[0]
        XCTAssertEqual(renderer.name, "goodcat_mesh_mesh_renderer")
        XCTAssertEqual(renderer.mode, .stroked)
        XCTAssertEqual(renderer.strokeWidth, 1.0, accuracy: 1e-10)
        XCTAssertEqual(renderer.strokeColor, LoomColor(r: 0, g: 0, b: 0, a: 255))
        XCTAssertEqual(renderer.pointSize, 2.0, accuracy: 1e-10)
        XCTAssertEqual(renderer.holdLength, 1)
    }

    func testRendererSetPlaybackConfig() throws {
        let cfg = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        let pb  = cfg.library.rendererSets[0].playbackConfig
        XCTAssertEqual(pb.mode, .sequential)
    }

    func testRendererSetLibraryLookup() throws {
        let cfg = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        XCTAssertNotNil(cfg.library.rendererSet(named: "goodcat_mesh_mesh_renderSet"))
        XCTAssertNil(cfg.library.rendererSet(named: "nonexistent"))
    }

    func testRendererModeCoverage() {
        // All RendererMode raw values must parse correctly
        let known = ["POINTS", "STROKED", "FILLED", "FILLED_STROKED", "BRUSHED", "STENCILED"]
        for raw in known {
            XCTAssertNotNil(RendererMode(rawValue: raw), "\(raw) must parse")
        }
    }
}

// MARK: - SpriteConfigTests

final class SpriteConfigTests: XCTestCase {

    func testLoadSpriteConfig() throws {
        let cfg = try XMLConfigLoader.loadSpriteConfig(url: configFile("sprites.xml"))
        XCTAssertEqual(cfg.library.spriteSets.count, 1)
        XCTAssertEqual(cfg.library.allSprites.count, 1, "one sprite total")
    }

    func testSpriteDef() throws {
        let cfg    = try XMLConfigLoader.loadSpriteConfig(url: configFile("sprites.xml"))
        let sprite = cfg.library.allSprites[0]
        XCTAssertEqual(sprite.name, "goodcat_mesh_mesh_sprite_001")
        XCTAssertEqual(sprite.rendererSetName, "DefaultSet")
        XCTAssertEqual(sprite.shapeSetName, "goodcat_mesh_mesh_sprite")
        XCTAssertEqual(sprite.shapeName, "goodcat_mesh_mesh_sprite_001")
    }

    func testSpritePosition() throws {
        let cfg    = try XMLConfigLoader.loadSpriteConfig(url: configFile("sprites.xml"))
        let sprite = cfg.library.allSprites[0]
        XCTAssertEqual(sprite.position.x, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sprite.position.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sprite.scale.x, 1.0, accuracy: 1e-10)
        XCTAssertEqual(sprite.scale.y, 1.0, accuracy: 1e-10)
    }
}

// MARK: - XMLPolygonLoaderTests

final class XMLPolygonLoaderTests: XCTestCase {

    func testPolygonCount() throws {
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"))
        XCTAssertEqual(polygons.count, 54, "goodcat_mesh_mesh has 54 polygons")
    }

    func testAllPolygonsAreSpline() throws {
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"))
        for (i, p) in polygons.enumerated() {
            XCTAssertEqual(p.type, .spline, "polygon[\(i)] should be .spline")
        }
    }

    func testAllPolygonsHaveMultipleOf4Points() throws {
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"))
        for (i, p) in polygons.enumerated() {
            XCTAssertEqual(p.points.count % 4, 0,
                "polygon[\(i)] has \(p.points.count) points, must be multiple of 4")
        }
    }

    func testFirstPolygonPointCount() throws {
        // First polygon has 4 curves → 16 points
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"))
        XCTAssertEqual(polygons[0].points.count, 16, "first polygon has 4 curves")
    }

    func testNormalisationApplied() throws {
        // First polygon, first point: original (-0.43, 0.11) → normalised (-0.43, -0.11)
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"),
                                                  normalise: true)
        let p0 = polygons[0].points[0]
        XCTAssertEqual(p0.x, -0.43, accuracy: 1e-9)
        XCTAssertEqual(p0.y, -0.11, accuracy: 1e-9, "Y should be negated by normalisation")
    }

    func testNormalisationDisabled() throws {
        // Without normalisation, original Y is preserved
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"),
                                                  normalise: false)
        let p0 = polygons[0].points[0]
        XCTAssertEqual(p0.x, -0.43, accuracy: 1e-9)
        XCTAssertEqual(p0.y,  0.11, accuracy: 1e-9, "Y should be unmodified when normalise=false")
    }

    func testPressureArray() throws {
        let polygons = try XMLPolygonLoader.load(url: polygonFile("goodcat_mesh_mesh.xml"))
        for p in polygons {
            // pressure array has one entry per curve (anchor point)
            let curves = p.points.count / 4
            XCTAssertEqual(p.pressures.count, curves,
                "pressure array length should equal curve count")
        }
    }
}

// MARK: - JSONConfigLoaderTests

final class JSONConfigLoaderTests: XCTestCase {

    func testGlobalConfigRoundTrip() throws {
        let original = try XMLConfigLoader.loadGlobalConfig(url: configFile("global_config.xml"))
        let data     = try JSONConfigLoader.encode(ProjectConfig(globalConfig: original))
        let decoded  = try JSONConfigLoader.decode(from: data)
        XCTAssertEqual(decoded.globalConfig, original)
    }

    func testProjectConfigRoundTrip() throws {
        let original = try ProjectLoader.load(projectDirectory: fixtureDir)
        let data     = try JSONConfigLoader.encode(original)
        let decoded  = try JSONConfigLoader.decode(from: data)
        // Spot-check key fields rather than testing Codable exhaustively
        XCTAssertEqual(decoded.globalConfig.name, original.globalConfig.name)
        XCTAssertEqual(decoded.polygonConfig.library.polygonSets.count,
                       original.polygonConfig.library.polygonSets.count)
        XCTAssertEqual(decoded.subdivisionConfig.paramsSets.count,
                       original.subdivisionConfig.paramsSets.count)
        XCTAssertEqual(decoded.spriteConfig.library.allSprites.count,
                       original.spriteConfig.library.allSprites.count)
    }

    func testJSONContainsProjectName() throws {
        let cfg  = try ProjectLoader.load(projectDirectory: fixtureDir)
        let data = try JSONConfigLoader.encode(cfg)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("Test_051"), "JSON should contain project name")
    }
}

// MARK: - ProjectLoaderTests

final class ProjectLoaderTests: XCTestCase {

    func testLoadProject() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertEqual(cfg.globalConfig.name, "Test_051")
    }

    func testProjectSpriteCount() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertEqual(cfg.spriteConfig.library.allSprites.count, 1,
                       "Test_051 has one sprite")
    }

    func testProjectPolygonSetCount() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertEqual(cfg.polygonConfig.library.polygonSets.count, 2,
                       "Test_051 has two polygon set defs")
    }

    func testProjectSubdivisionType() throws {
        let cfg    = try ProjectLoader.load(projectDirectory: fixtureDir)
        let params = cfg.subdivisionConfig.paramsSets[0].params[0]
        XCTAssertEqual(params.subdivisionType, .quad,
                       "Test_051 first subdivision params should be QUAD")
    }

    func testMissingDirectoryThrows() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to/project")
        XCTAssertThrowsError(try ProjectLoader.load(projectDirectory: badURL)) { error in
            guard case ProjectLoaderError.projectDirectoryNotFound = error else {
                XCTFail("Expected projectDirectoryNotFound, got \(error)")
                return
            }
        }
    }
}
