import AppKit
import SwiftUI
import LoomEngine

struct CyclePreviewPanel: View {
    @EnvironmentObject private var controller: AppController
    let cycle: SpriteCycle
    @Binding var selectedStateIndex: Int?

    @State private var allPolygons: [Int: [Polygon2D]] = [:]
    @State private var allSVGImages: [Int: NSImage] = [:]
    @State private var isPlaying = false
    @State private var playFrame = 0

    private let previewFPS = 12.0

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                legend
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Canvas
            Canvas { ctx, size in
                drawBackground(ctx: ctx, size: size)
                if !allPolygons.isEmpty {
                    drawShapes(ctx: ctx, size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.07, green: 0.075, blue: 0.10))
            .overlay(
                Group {
                    if cycle.states.isEmpty {
                        Text("Add states to preview")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if allPolygons.isEmpty && allSVGImages.isEmpty {
                        Text("No geometry")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            )

            Divider()

            // Playback controls
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Frame \(playFrame + 1) / \(max(1, cycle.totalCycleFrames))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let si = currentStateIndex {
                        Text("State \(si + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: stepBack) {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Previous frame (stops playback)")

                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15))
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Pause" : "Play cycle")

                    Button(action: stepForward) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Next frame (stops playback)")

                    Spacer()

                    Button(action: rewind) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to frame 1")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadAllPolygons()
            syncFrameToSelection()
        }
        .onChange(of: cycle) { _, _ in loadAllPolygons() }
        .onChange(of: selectedStateIndex) { _, _ in
            guard !isPlaying else { return }
            syncFrameToSelection()
        }
        .onReceive(
            Timer.publish(every: 1.0 / previewFPS, on: .main, in: .common).autoconnect()
        ) { _ in
            guard isPlaying else { return }
            let total = max(1, cycle.totalCycleFrames)
            playFrame = (playFrame + 1) % total
            if let si = currentStateIndex, selectedStateIndex != si {
                selectedStateIndex = si
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("prev")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 0.36, green: 0.82, blue: 0.50))
                .frame(width: 5, height: 5)
            Text("cur")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("next")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Drawing

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.07, green: 0.075, blue: 0.10)))
        let cx = size.width / 2, cy = size.height / 2
        var cross = Path()
        cross.move(to: CGPoint(x: cx - 10, y: cy)); cross.addLine(to: CGPoint(x: cx + 10, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - 10)); cross.addLine(to: CGPoint(x: cx, y: cy + 10))
        ctx.stroke(cross, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
    }

    private func drawShapes(ctx: GraphicsContext, size: CGSize) {
        guard !cycle.states.isEmpty else { return }
        let count = cycle.states.count
        let currentIdx = currentStateIndex ?? 0

        if count > 1 {
            let prevIdx = (currentIdx - 1 + count) % count
            if let polys = allPolygons[prevIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.28),
                     lineWidth: 1.0)
            } else if let img = allSVGImages[prevIdx] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: 0.28)
            }
        }

        if count > 2 {
            let nextIdx = (currentIdx + 1) % count
            if let polys = allPolygons[nextIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.28),
                     lineWidth: 1.0)
            } else if let img = allSVGImages[nextIdx] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: 0.28)
            }
        }

        for layer in cycle.renderLayers(atFrame: playFrame) {
            if let polys = allPolygons[layer.stateIndex] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.36, green: 0.82, blue: 0.50).opacity(layer.alpha * 0.92),
                     lineWidth: 1.3)
            } else if let img = allSVGImages[layer.stateIndex] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: layer.alpha * 0.92)
            }
        }
    }

    private func drawSVGImage(_ nsImage: NSImage, ctx: GraphicsContext, size: CGSize, alpha: Double) {
        let drawSize = min(size.width, size.height) * 0.80
        let cx = size.width / 2
        let cy = size.height / 2
        let rect = CGRect(x: cx - drawSize / 2, y: cy - drawSize / 2,
                          width: drawSize, height: drawSize)
        ctx.withCGContext { cgCtx in
            cgCtx.saveGState()
            cgCtx.setAlpha(CGFloat(alpha))
            let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            nsImage.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            cgCtx.restoreGState()
        }
    }

    private func draw(_ polygons: [Polygon2D], in ctx: GraphicsContext, size: CGSize,
                      color: Color, lineWidth: CGFloat) {
        let scale = min(size.width, size.height) * 0.80
        let cx = size.width / 2
        let cy = size.height / 2
        for polygon in polygons where polygon.visible {
            guard !polygon.points.isEmpty else { continue }
            let pts = polygon.points.map { p in
                CGPoint(x: cx + p.x * scale, y: cy - p.y * scale)
            }
            ctx.stroke(buildPath(pts, type: polygon.type), with: .color(color), lineWidth: lineWidth)
        }
    }

    private func buildPath(_ pts: [CGPoint], type: PolygonType) -> Path {
        guard !pts.isEmpty else { return Path() }
        var p = Path()
        switch type {
        case .spline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
            p.closeSubpath()
        case .openSpline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
        case .point:
            for pt in pts {
                p.addEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
            }
        case .oval:
            if pts.count >= 2 {
                let ox = pts[0].x, oy = pts[0].y
                let rx = abs(pts[1].x - ox), ry = abs(pts[1].y - oy)
                p.addEllipse(in: CGRect(x: ox - rx, y: oy - ry, width: rx * 2, height: ry * 2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    // MARK: State tracking

    private var currentStateIndex: Int? {
        cycle.renderLayers(atFrame: playFrame).first?.stateIndex
    }

    private func firstFrame(ofState stateIdx: Int) -> Int {
        var f = 0
        for i in 0..<stateIdx where i < cycle.states.count {
            f += max(1, cycle.states[i].holdFrames) + max(0, cycle.states[i].transitionFrames)
        }
        return f
    }

    private func syncFrameToSelection() {
        if let si = selectedStateIndex {
            playFrame = firstFrame(ofState: si)
        }
    }

    // MARK: Playback

    private func togglePlay() { isPlaying.toggle() }

    private func stepBack() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame - 1 + total) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func stepForward() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame + 1) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func rewind() {
        isPlaying = false
        playFrame = 0
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    // MARK: Geometry loading

    private func loadAllPolygons() {
        guard let cfg = controller.projectConfig,
              let projectURL = controller.projectURL
        else { return }
        var polyResult: [Int: [Polygon2D]] = [:]
        var svgResult:  [Int: NSImage]     = [:]
        for (i, state) in cycle.states.enumerated() {
            if let svgFile = state.svgFilename, !svgFile.isEmpty {
                let url = projectURL
                    .appendingPathComponent("svgs/sprites")
                    .appendingPathComponent(svgFile)
                if let img = NSImage(contentsOf: url) { svgResult[i] = img }
            } else {
                let polys = loadPolygons(for: state, config: cfg, projectURL: projectURL)
                if !polys.isEmpty { polyResult[i] = polys }
            }
        }
        allPolygons  = polyResult
        allSVGImages = svgResult
    }

    private func loadPolygons(for state: SpriteCycleState,
                              config: ProjectConfig,
                              projectURL: URL) -> [Polygon2D] {
        guard !state.shapeSetName.isEmpty else { return [] }
        guard let shapeDef = config.shapeConfig.library.shapeSets
            .first(where: { $0.name == state.shapeSetName })?
            .shapes.first(where: { $0.name == state.shapeName })
        else { return [] }

        switch shapeDef.sourceType {

        case .regularPolygon:
            let sides = shapeDef.regularPolygonSides
            guard sides >= 3 else { return [] }
            let angInc = 2.0 * .pi / Double(sides)
            var pts = [Vector2D]()
            for i in 0..<sides {
                let angle = Double(i) * angInc - .pi / 2
                pts.append(Vector2D(x: 0.5 * cos(angle), y: 0.5 * sin(angle)))
            }
            return [Polygon2D(points: pts, type: .line)]

        case .polygonSet:
            guard !shapeDef.polygonSetName.isEmpty,
                  let polyDef = config.polygonConfig.library.polygonSets
                      .first(where: { $0.name == shapeDef.polygonSetName })
            else { return [] }

            if let rp = polyDef.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }

            let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                ? "polygonSets" : polyDef.folder
            let url = projectURL
                .appendingPathComponent(folder)
                .appendingPathComponent(polyDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }

            if polyDef.filename.lowercased().hasSuffix(".json") {
                return (try? EditableGeometryJSONLoader.load(url: url).runtimePolygons(
                    targetLayerID: polyDef.editableLayerID,
                    targetLayerName: polyDef.editableLayerName
                )) ?? []
            }
            return (try? XMLPolygonLoader.load(url: url)) ?? []

        default:
            return []
        }
    }
}
