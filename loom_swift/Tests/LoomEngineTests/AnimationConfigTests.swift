import XCTest
@testable import LoomEngine
import Foundation

// MARK: - Shared fixture path

private var fixtureDir: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_052")
}

private func configFile(_ name: String) -> URL {
    fixtureDir.appendingPathComponent("configuration/\(name)")
}

private func polygonFile(_ name: String) -> URL {
    fixtureDir.appendingPathComponent("polygonSets/\(name)")
}

private func morphFile(_ name: String) -> URL {
    fixtureDir.appendingPathComponent("morphTargets/\(name)")
}

// MARK: - GlobalConfig052Tests

final class GlobalConfig052Tests: XCTestCase {

    func testLoadGlobalConfig() throws {
        let cfg = try XMLConfigLoader.loadGlobalConfig(url: configFile("global_config.xml"))
        XCTAssertEqual(cfg.name, "Test_052")
        XCTAssertEqual(cfg.width, 1080)
        XCTAssertTrue(cfg.animating)
        XCTAssertTrue(cfg.drawBackgroundOnce)
        XCTAssertTrue(cfg.subdividing)
    }
}

// MARK: - SubdivisionConfig052Tests

final class SubdivisionConfig052Tests: XCTestCase {

    private func loadParams() throws -> SubdivisionParams {
        let cfg = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        return try XCTUnwrap(cfg.paramsSet(named: "rect_Subdivide")?.params.first)
    }

    func testParamsSetsCount() throws {
        let cfg = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        XCTAssertEqual(cfg.paramsSets.count, 2)
        XCTAssertNotNil(cfg.paramsSet(named: "rect_Subdivide"))
        XCTAssertNotNil(cfg.paramsSet(named: "saw_Subdivide"))
        XCTAssertNil(cfg.paramsSet(named: "none"), "\"none\" is not defined in subdivision.xml")
    }

    func testNewPTWBoolFields() throws {
        let p = try loadParams()
        XCTAssertFalse(p.pTW_randomTranslation)
        XCTAssertFalse(p.pTW_randomScale)
        XCTAssertFalse(p.pTW_randomRotation)
    }

    func testPTWTransform() throws {
        let p = try loadParams()
        XCTAssertEqual(p.pTW_transform.scale.x,    1.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_transform.scale.y,    1.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_transform.translation.x, 0.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_transform.rotation,   0.0, accuracy: 1e-10)
    }

    func testPTWRandomCentreDivisor() throws {
        let p = try loadParams()
        XCTAssertEqual(p.pTW_randomCentreDivisor, 100.0, accuracy: 1e-10)
    }

    func testPTWRandomTranslationRange() throws {
        let p = try loadParams()
        XCTAssertEqual(p.pTW_randomTranslationRange.x.min, 0.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomTranslationRange.x.max, 0.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomTranslationRange.y.min, 0.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomTranslationRange.y.max, 0.0, accuracy: 1e-10)
    }

    func testPTWRandomScaleRange() throws {
        let p = try loadParams()
        XCTAssertEqual(p.pTW_randomScaleRange.x.min, 1.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomScaleRange.x.max, 1.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomScaleRange.y.min, 1.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomScaleRange.y.max, 1.0, accuracy: 1e-10)
    }

    func testPTWRandomRotationRange() throws {
        let p = try loadParams()
        XCTAssertEqual(p.pTW_randomRotationRange.min, 0.0, accuracy: 1e-10)
        XCTAssertEqual(p.pTW_randomRotationRange.max, 0.0, accuracy: 1e-10)
    }

    func testSubdivisionParamsRoundTrip() throws {
        let cfg     = try XMLConfigLoader.loadSubdivisionConfig(url: configFile("subdivision.xml"))
        let data    = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(SubdivisionConfig.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }
}

// MARK: - SpriteAnimation052Tests

final class SpriteAnimation052Tests: XCTestCase {

    private func loadSprites() throws -> [SpriteDef] {
        let cfg = try XMLConfigLoader.loadSpriteConfig(url: configFile("sprites.xml"))
        return cfg.library.allSprites
    }

    func testSpriteCount() throws {
        XCTAssertEqual(try loadSprites().count, 4)
    }

    func testSpriteNames() throws {
        let names = try loadSprites().map { $0.name }
        XCTAssertEqual(names, ["keyframe_rect", "jitter_rect", "morphTarget_saw", "jitter_morph_saw"])
    }

    // MARK: keyframe_rect

    func testKeyframeRectAnimationType() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "keyframe_rect" })
        XCTAssertTrue(sprite.animation.enabled)
        XCTAssertEqual(sprite.animation.type, .keyframe)
        XCTAssertEqual(sprite.animation.loopMode, .loop)
        XCTAssertEqual(sprite.animation.totalDraws, 200)
    }

    func testKeyframeRectKeyframeCount() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "keyframe_rect" })
        XCTAssertEqual(sprite.animation.keyframes.count, 4)
    }

    func testKeyframeRectFirstKeyframe() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "keyframe_rect" })
        let kf = sprite.animation.keyframes[0]
        XCTAssertEqual(kf.drawCycle, 0)
        XCTAssertEqual(kf.position.x,  0.0, accuracy: 1e-10)
        XCTAssertEqual(kf.scale.x,     1.0, accuracy: 1e-10)
        XCTAssertEqual(kf.rotation,    0.0, accuracy: 1e-10)
        XCTAssertEqual(kf.easing, .easeInOutQuad)
    }

    func testKeyframeRectSecondKeyframe() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "keyframe_rect" })
        let kf = sprite.animation.keyframes[1]
        XCTAssertEqual(kf.drawCycle, 50)
        XCTAssertEqual(kf.position.x,  50.0, accuracy: 1e-10)
        XCTAssertEqual(kf.scale.x,      0.5, accuracy: 1e-10)
        XCTAssertEqual(kf.scale.y,      0.5, accuracy: 1e-10)
        XCTAssertEqual(kf.rotation,   -45.0, accuracy: 1e-10)
    }

    func testKeyframeRectRendererSet() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "keyframe_rect" })
        XCTAssertEqual(sprite.rendererSetName, "rect_renderSet")
    }

    // MARK: jitter_rect

    func testJitterRectAnimationType() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "jitter_rect" })
        XCTAssertTrue(sprite.animation.enabled)
        XCTAssertEqual(sprite.animation.type, .random)
        XCTAssertEqual(sprite.animation.totalDraws, 0)
    }

    func testJitterRectTranslationRange() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "jitter_rect" })
        let tr = sprite.animation.translationRange
        XCTAssertEqual(tr.x.min, -30.0, accuracy: 1e-10)
        XCTAssertEqual(tr.x.max,  30.0, accuracy: 1e-10)
        XCTAssertEqual(tr.y.min,   0.0, accuracy: 1e-10)
        XCTAssertEqual(tr.y.max,   0.0, accuracy: 1e-10)
    }

    func testJitterRectNoKeyframes() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "jitter_rect" })
        XCTAssertTrue(sprite.animation.keyframes.isEmpty)
    }

    // MARK: morphTarget_saw

    func testMorphTargetSawAnimationType() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "morphTarget_saw" })
        XCTAssertTrue(sprite.animation.enabled)
        XCTAssertEqual(sprite.animation.type, .keyframeMorph)
        XCTAssertEqual(sprite.animation.loopMode, .pingPong)
        XCTAssertEqual(sprite.animation.totalDraws, 100)
    }

    func testMorphTargetSawMorphTargets() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "morphTarget_saw" })
        XCTAssertEqual(sprite.animation.morphTargets.count, 2)
        XCTAssertEqual(sprite.animation.morphTargets[0].file, "saw_mt_1.poly.xml")
        XCTAssertEqual(sprite.animation.morphTargets[1].file, "saw_mt_2.poly.xml")
    }

    func testMorphTargetSawKeyframesMorphAmount() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "morphTarget_saw" })
        let kfs = sprite.animation.keyframes
        XCTAssertEqual(kfs.count, 2)
        XCTAssertEqual(kfs[0].morphAmount, 1.0, accuracy: 1e-10)
        XCTAssertEqual(kfs[1].morphAmount, 2.0, accuracy: 1e-10)
        XCTAssertEqual(kfs[0].easing, .linear)
    }

    // MARK: jitter_morph_saw

    func testJitterMorphSawAnimationType() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "jitter_morph_saw" })
        XCTAssertTrue(sprite.animation.enabled)
        XCTAssertEqual(sprite.animation.type, .jitterMorph)
    }

    func testJitterMorphSawMorphRange() throws {
        let sprite = try XCTUnwrap(try loadSprites().first { $0.name == "jitter_morph_saw" })
        XCTAssertEqual(sprite.animation.morphMin, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sprite.animation.morphMax, 2.0, accuracy: 1e-10)
        XCTAssertEqual(sprite.animation.morphTargets.count, 2)
    }
}

// MARK: - RendererChanges052Tests

final class RendererChanges052Tests: XCTestCase {

    private func loadRectRenderer() throws -> Renderer {
        let cfg = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        let set = try XCTUnwrap(cfg.library.rendererSet(named: "rect_renderSet"))
        return try XCTUnwrap(set.renderers.first)
    }

    private func loadSawRenderer() throws -> Renderer {
        let cfg = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        let set = try XCTUnwrap(cfg.library.rendererSet(named: "saw_renderSet"))
        return try XCTUnwrap(set.renderers.first)
    }

    // MARK: rect_renderer — fill colour change

    func testRectRendererHasFillColorChange() throws {
        let r = try loadRectRenderer()
        XCTAssertNotNil(r.changes.fillColor, "rect_renderer must have a FillColorChange")
        XCTAssertNil(r.changes.strokeColor)
        XCTAssertNil(r.changes.strokeWidth)
    }

    func testFillColorChangeEnabled() throws {
        let change = try XCTUnwrap(try loadRectRenderer().changes.fillColor)
        XCTAssertTrue(change.enabled)
    }

    func testFillColorChangeKindAndMotion() throws {
        let change = try XCTUnwrap(try loadRectRenderer().changes.fillColor)
        XCTAssertEqual(change.kind,   .random)
        XCTAssertEqual(change.motion, .pingPong)
        XCTAssertEqual(change.cycle,  .pausing)
        XCTAssertEqual(change.scale,  .poly)
    }

    func testFillColorPaletteCount() throws {
        let change = try XCTUnwrap(try loadRectRenderer().changes.fillColor)
        XCTAssertEqual(change.palette.count, 3)
    }

    func testFillColorPaletteFirstEntry() throws {
        let change = try XCTUnwrap(try loadRectRenderer().changes.fillColor)
        let c = change.palette[0]
        XCTAssertEqual(c.r, 56);  XCTAssertEqual(c.g, 59)
        XCTAssertEqual(c.b, 102); XCTAssertEqual(c.a, 31)
    }

    func testFillColorPauseMax() throws {
        let change = try XCTUnwrap(try loadRectRenderer().changes.fillColor)
        XCTAssertEqual(change.pauseMax, 5)
    }

    // MARK: saw_renderer — stroke width and colour changes

    func testSawRendererHasBothStrokeChanges() throws {
        let r = try loadSawRenderer()
        XCTAssertNotNil(r.changes.strokeWidth,  "saw_renderer must have StrokeWidthChange")
        XCTAssertNotNil(r.changes.strokeColor,  "saw_renderer must have StrokeColorChange")
        XCTAssertNil(r.changes.fillColor)
    }

    func testStrokeWidthChangeKindAndPalette() throws {
        let change = try XCTUnwrap(try loadSawRenderer().changes.strokeWidth)
        XCTAssertTrue(change.enabled)
        XCTAssertEqual(change.kind,   .random)
        XCTAssertEqual(change.motion, .up)
        XCTAssertEqual(change.cycle,  .constant)
        XCTAssertEqual(change.sizePalette.count, 3)
        XCTAssertEqual(change.sizePalette[0], 0.1, accuracy: 1e-10)
        XCTAssertEqual(change.sizePalette[1], 0.3, accuracy: 1e-10)
        XCTAssertEqual(change.sizePalette[2], 0.6, accuracy: 1e-10)
    }

    func testStrokeColorChangeKindAndPalette() throws {
        let change = try XCTUnwrap(try loadSawRenderer().changes.strokeColor)
        XCTAssertTrue(change.enabled)
        XCTAssertEqual(change.kind,   .sequential)
        XCTAssertEqual(change.motion, .up)
        XCTAssertEqual(change.cycle,  .constant)
        XCTAssertEqual(change.palette.count, 3)
        let first = change.palette[0]
        XCTAssertEqual(first.r, 140); XCTAssertEqual(first.g, 31)
        XCTAssertEqual(first.b, 38);  XCTAssertEqual(first.a, 255)
    }

    // MARK: JSON round-trip

    func testRenderingConfigRoundTrip() throws {
        let cfg     = try XMLConfigLoader.loadRenderingConfig(url: configFile("rendering.xml"))
        let data    = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(RenderingConfig.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }
}

// MARK: - MorphTargetPolygonTests

final class MorphTargetPolygonTests: XCTestCase {

    func testMorphTargetFilesLoad() throws {
        let mt1 = try XMLPolygonLoader.load(url: morphFile("saw_mt_1.poly.xml"))
        let mt2 = try XMLPolygonLoader.load(url: morphFile("saw_mt_2.poly.xml"))
        XCTAssertFalse(mt1.isEmpty, "saw_mt_1 must contain polygons")
        XCTAssertFalse(mt2.isEmpty, "saw_mt_2 must contain polygons")
    }

    func testMorphTargetsSameStructure() throws {
        let base = try XMLPolygonLoader.load(url: polygonFile("saw.xml"))
        let mt1  = try XMLPolygonLoader.load(url: morphFile("saw_mt_1.poly.xml"))
        let mt2  = try XMLPolygonLoader.load(url: morphFile("saw_mt_2.poly.xml"))
        XCTAssertEqual(base.count, mt1.count, "morph target must have same polygon count as base")
        XCTAssertEqual(base.count, mt2.count)
        for i in base.indices {
            XCTAssertEqual(base[i].points.count, mt1[i].points.count,
                "polygon[\(i)] point count must match between base and mt1")
            XCTAssertEqual(base[i].points.count, mt2[i].points.count,
                "polygon[\(i)] point count must match between base and mt2")
        }
    }
}

// MARK: - ProjectLoader052Tests

final class ProjectLoader052Tests: XCTestCase {

    func testLoadProject() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertEqual(cfg.globalConfig.name, "Test_052")
    }

    func testProject4Sprites() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertEqual(cfg.spriteConfig.library.allSprites.count, 4)
    }

    func testProjectRendererSets() throws {
        let cfg = try ProjectLoader.load(projectDirectory: fixtureDir)
        XCTAssertNotNil(cfg.renderingConfig.library.rendererSet(named: "rect_renderSet"))
        XCTAssertNotNil(cfg.renderingConfig.library.rendererSet(named: "saw_renderSet"))
    }

    func testProjectRoundTrip() throws {
        let original = try ProjectLoader.load(projectDirectory: fixtureDir)
        let data     = try JSONConfigLoader.encode(original)
        let decoded  = try JSONConfigLoader.decode(from: data)
        XCTAssertEqual(decoded.globalConfig.name, original.globalConfig.name)
        XCTAssertEqual(decoded.spriteConfig.library.allSprites.count,
                       original.spriteConfig.library.allSprites.count)
        XCTAssertEqual(decoded.renderingConfig.library.rendererSets.count,
                       original.renderingConfig.library.rendererSets.count)
        XCTAssertEqual(decoded.subdivisionConfig.paramsSets.count,
                       original.subdivisionConfig.paramsSets.count)
    }
}
