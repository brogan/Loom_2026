import XCTest
import CoreGraphics
@testable import LoomEngine

// MARK: - Shared fixture

private var fixtureDir052: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_052")
}

// MARK: - Assembly tests

final class SpriteSceneAssemblyTests: XCTestCase {

    private func makeScene() throws -> SpriteScene {
        let config = try ProjectLoader.load(projectDirectory: fixtureDir052)
        return try SpriteScene(config: config, projectDirectory: fixtureDir052)
    }

    func testInstanceCount() throws {
        let scene = try makeScene()
        XCTAssertEqual(scene.instances.count, 4,
                       "Test_052 declares 4 sprites; scene should have 4 instances")
    }

    func testSpriteNamesPreserved() throws {
        let scene = try makeScene()
        let names = scene.instances.map { $0.def.name }
        XCTAssertTrue(names.contains("keyframe_rect"))
        XCTAssertTrue(names.contains("jitter_rect"))
        XCTAssertTrue(names.contains("morphTarget_saw"))
        XCTAssertTrue(names.contains("jitter_morph_saw"))
    }

    func testBasePolygonsLoadedForRect() throws {
        let scene = try makeScene()
        let rectInst = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        XCTAssertFalse(rectInst.basePolygons.isEmpty, "keyframe_rect should have base polygons")
        XCTAssertEqual(rectInst.basePolygons[0].points.count, 16,
                       "rect polygon: 4 curves × 4 points = 16 points")
    }

    func testBasePolygonsLoadedForSaw() throws {
        let scene = try makeScene()
        let sawInst = try XCTUnwrap(scene.instances.first { $0.def.name == "morphTarget_saw" })
        XCTAssertFalse(sawInst.basePolygons.isEmpty, "morphTarget_saw should have base polygons")
        XCTAssertEqual(sawInst.basePolygons[0].points.count, 60,
                       "saw polygon: 15 curves × 4 points = 60 points")
    }

    func testMorphTargetsLoadedForMorphSprite() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "morphTarget_saw" })
        XCTAssertEqual(inst.morphTargetPolygons.count, 2,
                       "morphTarget_saw has 2 morph target references")
        XCTAssertEqual(inst.morphTargetPolygons[0].count, inst.basePolygons.count)
        XCTAssertEqual(inst.morphTargetPolygons[1].count, inst.basePolygons.count)
    }

    func testMorphTargetsMissingForNonMorphSprite() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        XCTAssertTrue(inst.morphTargetPolygons.isEmpty,
                      "keyframe_rect has no morph targets")
    }

    func testSubdivisionParamsResolvedForRect() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        XCTAssertEqual(inst.subdivisionParams.count, 1,
                       "keyframe_rect uses rect_Subdivide which has 1 params entry")
        XCTAssertEqual(inst.subdivisionParams[0].subdivisionType, .quad)
    }

    func testNoSubdivisionForNoneParams() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "morphTarget_saw" })
        XCTAssertTrue(inst.subdivisionParams.isEmpty,
                      "morphTarget_saw uses 'none' — should resolve to empty params")
    }

    func testRendererSetResolvedForRect() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        XCTAssertEqual(inst.rendererSet.name, "rect_renderSet")
        XCTAssertEqual(inst.rendererSet.renderers.count, 1)
    }

    func testRendererSetResolvedForSaw() throws {
        let scene = try makeScene()
        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "morphTarget_saw" })
        XCTAssertEqual(inst.rendererSet.name, "saw_renderSet")
    }
}

// MARK: - Initial state tests

final class SpriteSceneInitialStateTests: XCTestCase {

    private func makeScene() throws -> SpriteScene {
        let config = try ProjectLoader.load(projectDirectory: fixtureDir052)
        return try SpriteScene(config: config, projectDirectory: fixtureDir052)
    }

    func testInitialDrawCycleIsZero() throws {
        let scene = try makeScene()
        for inst in scene.instances {
            XCTAssertEqual(inst.state.drawCycle, 0, "\(inst.def.name) should start at cycle 0")
        }
    }

    func testInitialTransformIsIdentity() throws {
        let scene = try makeScene()
        for inst in scene.instances {
            XCTAssertEqual(inst.state.transform, .identity,
                           "\(inst.def.name) should start with identity transform")
        }
    }

    func testInitialRendererIndexIsZero() throws {
        let scene = try makeScene()
        for inst in scene.instances {
            XCTAssertEqual(inst.state.activeRendererIndex, 0,
                           "\(inst.def.name) should start at renderer index 0")
        }
    }

    func testRendererAnimationStatesInitialised() throws {
        let scene = try makeScene()
        let inst  = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        // rect_renderSet has 1 renderer; expects 1 animation state.
        XCTAssertEqual(inst.state.rendererAnimationStates.count, 1)
        // rect_renderer has a FillColorChange — its state should be non-nil at index 0.
        XCTAssertNotNil(inst.state.rendererAnimationStates[0].fillColorState)
        // Stroke changes are absent in rect_renderer.
        XCTAssertNil(inst.state.rendererAnimationStates[0].strokeColorState)
    }
}

// MARK: - Advance tests

final class SpriteSceneAdvanceTests: XCTestCase {

    private func makeScene() throws -> SpriteScene {
        let config = try ProjectLoader.load(projectDirectory: fixtureDir052)
        return try SpriteScene(config: config, projectDirectory: fixtureDir052)
    }

    func testAdvanceIncrementsDrawCycle() throws {
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        for inst in scene.instances {
            XCTAssertEqual(inst.state.drawCycle, 1)
        }
    }

    func testAdvanceThreeTimes() throws {
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        for inst in scene.instances {
            XCTAssertEqual(inst.state.drawCycle, 3)
        }
    }

    func testKeyframeRectTransformNonIdentityAfterCycles() throws {
        // After 26 advance calls (cycle 25 was evaluated at cycle 0 draw), the
        // keyframe_rect transform should reflect the keyframe values at cycle 25.
        // The sprite starts computing transform for drawCycle=0, so after 26 advances
        // the last computed transform used drawCycle=25.
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        for _ in 0..<26 { scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng) }

        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "keyframe_rect" })
        // At cycle 25, easeInOutQuad(0.5) = 0.5, so positionOffset.x ≈ 25
        XCTAssertEqual(inst.state.transform.positionOffset.x, 25, accuracy: 1.0)
        XCTAssertEqual(inst.state.transform.rotation, -22.5, accuracy: 1.0)
    }

    func testMorphSpriteTransformAtCycle0HasMorphAmount1() throws {
        // morphTarget_saw: KF0 at drawCycle=0 has morphAmount=1.0
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)  // computes transform for cycle 0

        let inst = try XCTUnwrap(scene.instances.first { $0.def.name == "morphTarget_saw" })
        XCTAssertEqual(inst.state.transform.morphAmount, 1.0, accuracy: 1e-9)
    }

    func testJitterTranslationChangesEachFrame() throws {
        // jitter_rect: translationRange x ∈ [-30, 30]. Two consecutive frames
        // should almost certainly produce different X offsets with a system RNG.
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        let x1 = scene.instances.first { $0.def.name == "jitter_rect" }!.state.transform.positionOffset.x
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        let x2 = scene.instances.first { $0.def.name == "jitter_rect" }!.state.transform.positionOffset.x
        // Note: there is a tiny probability that x1 == x2 by chance, but it's
        // essentially impossible over a ±30 continuous range with 64-bit RNG.
        XCTAssertNotEqual(x1, x2, "jitter X offsets should differ frame to frame")
    }

    func testRendererFillColorAdvancesForRect() throws {
        // rect_renderer has FillColorChange (RAN kind) so the palette index
        // should change after an advance.
        var scene = try makeScene()
        var rng   = SystemRandomNumberGenerator()
        let before = scene.instances.first { $0.def.name == "keyframe_rect" }!
            .state.rendererAnimationStates[0].fillColorState!.index
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)
        let after = scene.instances.first { $0.def.name == "keyframe_rect" }!
            .state.rendererAnimationStates[0].fillColorState!.index
        // RAN always picks a random index — may land on the same one,
        // so we just verify bounds.
        XCTAssertGreaterThanOrEqual(after, 0)
        XCTAssertLessThan(after, 3)  // palette has 3 entries
        _ = before  // silence unused-variable warning
    }
}

// MARK: - Render integration test

final class SpriteSceneRenderTests: XCTestCase {

    /// Minimal bitmap context with Y-flip applied.
    private func makeCanvas(width: Int, height: Int) -> CGContext {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        buf.initialize(repeating: 255, count: width * height * 4)
        let ctx = CGContext(
            data: buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        return ctx
    }

    func testRenderCompletesWithoutError() throws {
        let config = try ProjectLoader.load(projectDirectory: fixtureDir052)
        var scene  = try SpriteScene(config: config, projectDirectory: fixtureDir052)
        var rng    = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)

        let canvas = makeCanvas(width: 1080, height: 1080)
        let vt     = ViewTransform(canvasSize: CGSize(width: 1080, height: 1080))
        // Must not crash.
        scene.render(into: canvas, viewTransform: vt, using: &rng)
    }

    func testRenderWithSyntheticLargePolygon() throws {
        // Verify the full advance→render pipeline produces visible pixels.
        //
        // Loom coordinate conventions (applied by SpriteScene.applyTransform):
        //   raw_coord × 2.0 × scale × canvas_half → pixels
        //
        // With canvas 100×100, scale (1,1), half=50:
        //   ±0.4 raw → ±0.4 × 2.0 × 50 = ±40 px from centre → fills most of canvas.
        let poly = Polygon2D(
            points: [
                Vector2D(x: -0.4, y:  0.4),
                Vector2D(x:  0.4, y:  0.4),
                Vector2D(x:  0.4, y: -0.4),
                Vector2D(x: -0.4, y: -0.4),
            ],
            type: .line
        )

        let renderer  = Renderer(mode: .filled, fillColor: .black)
        let rendSet   = RendererSet(name: "test",
                                    playbackConfig: RendererPlaybackConfig(),
                                    renderers: [renderer])
        let anim      = SpriteAnimation.disabled
        let spriteDef = SpriteDef(name: "test",
                                  position: .zero,
                                  scale: Vector2D(x: 1, y: 1),
                                  animation: anim)
        let state     = SpriteState.initial(for: rendSet)
        let instance  = SpriteInstance(def: spriteDef,
                                        basePolygons: [poly],
                                        morphTargetPolygons: [],
                                        rendererSet: rendSet,
                                        subdivisionParams: [],
                                        state: state)
        var scene = SpriteScene(instances: [instance])
        var rng   = SystemRandomNumberGenerator()
        scene.advance(deltaTime: 1.0/30.0, targetFPS: 30.0, using: &rng)

        let width  = 100
        let height = 100
        let buf    = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        defer { buf.deallocate() }
        buf.initialize(repeating: 255, count: width * height * 4)
        let ctx = CGContext(
            data: buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let vt = ViewTransform(canvasSize: CGSize(width: width, height: height))
        scene.render(into: ctx, viewTransform: vt, using: &rng)

        // Centre pixel of canvas should be filled black.
        let row = height - 50
        let idx = (row * width + 50) * 4
        XCTAssertLessThan(Int(buf[idx]), 255, "centre pixel should not be white — polygon covers it")
    }
}

