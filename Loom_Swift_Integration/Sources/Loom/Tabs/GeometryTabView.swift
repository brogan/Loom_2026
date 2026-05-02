import SwiftUI
import LoomEngine

// Left-panel list view for the Geometry tab.
// Shows geometry sets grouped by type; + on each group header creates new geometry of that type.
struct GeometryTabView: View {

    @EnvironmentObject private var controller: AppController
    @State private var showingRenameAlert = false
    @State private var renameText         = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $controller.selectedGeometryKey) {
                geometryGroup(label: "Algorithmic",    folder: "regularPolygons", icon: "hexagon")
                geometryGroup(label: "Polygon Sets",   folder: "polygonSets",     icon: "pentagon")
                geometryGroup(label: "Curve Sets",     folder: "curveSets",       icon: "scribble")
                geometryGroup(label: "Point Sets",     folder: "pointSets",       icon: "circle.grid.3x3.fill")
            }
            .listStyle(.sidebar)

            Divider()
            actionBar
        }
        .alert("Rename Geometry", isPresented: $showingRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                guard let key = controller.selectedGeometryKey, !renameText.isEmpty else { return }
                controller.renameGeometry(key: key, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 2) {
            Button("Rename") {
                if let key = controller.selectedGeometryKey {
                    renameText = String(key.split(separator: "/", maxSplits: 1).last ?? "")
                    showingRenameAlert = true
                }
            }
            .disabled(controller.selectedGeometryKey == nil)

            Button("Duplicate") {
                if let key = controller.selectedGeometryKey {
                    controller.duplicateGeometry(key: key)
                }
            }
            .disabled(controller.selectedGeometryKey == nil)

            Button("Delete") {
                if let key = controller.selectedGeometryKey {
                    controller.deleteGeometry(key: key)
                }
            }
            .disabled(controller.selectedGeometryKey == nil)
            .foregroundStyle(controller.selectedGeometryKey != nil ? Color.red : Color.secondary)

            Spacer()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Group builder

    @ViewBuilder
    private func geometryGroup(label: String, folder: String, icon: String) -> some View {
        let items = geometryItems(folder: folder)
        Section {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            } else {
                ForEach(items, id: \.self) { name in
                    geometryRow(name: name, folder: folder, icon: icon)
                        .tag("\(folder)/\(name)")
                        .contextMenu {
                            Button("Rename…") {
                                renameText = name
                                controller.selectedGeometryKey = "\(folder)/\(name)"
                                showingRenameAlert = true
                            }
                            Button("Duplicate") { controller.duplicateGeometry(key: "\(folder)/\(name)") }
                            Divider()
                            Button("Delete", role: .destructive) { controller.deleteGeometry(key: "\(folder)/\(name)") }
                        }
                }
            }
        } header: {
            HStack {
                Text(label)
                Spacer()
                Button {
                    // TODO: create new geometry of this type
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("New \(label)")
            }
        }
    }

    @ViewBuilder
    private func geometryRow(name: String, folder: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Label(name, systemImage: icon)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            let count = spriteCount(folder: folder, name: name)
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(count > 0 ? Color.secondary : Color.clear)
                .frame(minWidth: 16, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func spriteCount(folder: String, name: String) -> Int {
        guard let cfg = controller.projectConfig else { return 0 }
        let shapeSetNames: Set<String> = Set(cfg.shapeConfig.library.shapeSets.compactMap { ss in
            let matches = ss.shapes.contains { shape in
                switch folder {
                case "polygonSets", "regularPolygons": return shape.polygonSetName == name
                case "curveSets":   return shape.openCurveSetName == name
                case "pointSets":   return shape.pointSetName == name
                default:            return false
                }
            }
            return matches ? ss.name : nil
        })
        return cfg.spriteConfig.library.allSprites.filter { shapeSetNames.contains($0.shapeSetName) }.count
    }

    private func geometryItems(folder: String) -> [String] {
        guard let base = controller.projectURL else { return [] }
        let dir = base.appendingPathComponent(folder)
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ !$0.lastPathComponent.hasPrefix(".") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return [] }
        return contents.map { $0.deletingPathExtension().lastPathComponent }
    }
}

// MARK: - Center panel

// Center-panel main view for the Geometry tab.
// Shows wireframe of selected geometry set; falls back to live canvas when nothing is selected.
struct GeometryMainView: View {

    @EnvironmentObject private var controller: AppController
    @State private var loadedPolygons: [Polygon2D] = []
    @State private var loadError:      String?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)

            if controller.selectedGeometryKey != nil {
                if !loadedPolygons.isEmpty {
                    WireframeCanvas(polygons: loadedPolygons)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Text("No geometry data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                if let engine = controller.engine {
                    RenderSurfaceView(
                        engine:        engine,
                        playbackState: controller.playbackState,
                        onFrameTick:   { _ in }
                    )
                }
            }
        }
        .onAppear        { loadGeometry() }
        .onChange(of: controller.selectedGeometryKey) { _, _ in loadGeometry() }
        .onChange(of: controller.projectURL)          { _, _ in loadGeometry() }
    }

    private func loadGeometry() {
        guard let key = controller.selectedGeometryKey else {
            loadedPolygons = []; loadError = nil; return
        }
        do {
            loadedPolygons = try resolvePolygons(key: key)
            loadError = nil
        } catch {
            loadedPolygons = []
            loadError = error.localizedDescription
        }
    }

    private func resolvePolygons(key: String) throws -> [Polygon2D] {
        guard let projURL = controller.projectURL,
              let cfg     = controller.projectConfig
        else { return [] }

        let parts = key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return [] }
        let folder = String(parts[0])
        let name   = String(parts[1])

        switch folder {
        case "polygonSets":
            guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name })
            else { return [] }
            if let rp = def.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }
            let dir = (def.folder == "polygonSet" || def.folder.isEmpty) ? "polygonSets" : def.folder
            let url = projURL.appendingPathComponent(dir).appendingPathComponent(def.filename)
            return try XMLPolygonLoader.load(url: url)

        case "regularPolygons":
            guard let def = cfg.polygonConfig.library.polygonSets.first(where: { $0.name == name }),
                  let rp  = def.regularParams
            else { return [] }
            return [RegularPolygonGenerator.generate(params: rp)]

        case "curveSets":
            guard let def = cfg.curveConfig.library.curveSets.first(where: { $0.name == name })
            else { return [] }
            let url = projURL.appendingPathComponent(def.folder).appendingPathComponent(def.filename)
            return try XMLPolygonLoader.loadOpenCurveSet(url: url)

        case "pointSets":
            guard let def = cfg.pointConfig.library.pointSets.first(where: { $0.name == name })
            else { return [] }
            let url = projURL.appendingPathComponent(def.folder).appendingPathComponent(def.filename)
            return try XMLPolygonLoader.loadPointSet(url: url)

        default:
            return []
        }
    }
}

// MARK: - Wireframe canvas

private struct WireframeCanvas: View {
    let polygons: [Polygon2D]

    var body: some View {
        Canvas { ctx, size in
            draw(ctx: ctx, size: size)
        }
    }

    // MARK: Layout

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let allPts = polygons.flatMap { $0.points }
        guard !allPts.isEmpty else { return }

        // Bounding box
        var minX = allPts[0].x, maxX = allPts[0].x
        var minY = allPts[0].y, maxY = allPts[0].y
        for p in allPts {
            if p.x < minX { minX = p.x }; if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }; if p.y > maxY { maxY = p.y }
        }

        let dataW   = max(maxX - minX, 1e-6)
        let dataH   = max(maxY - minY, 1e-6)
        let pad     = max(dataW, dataH) * 0.15
        let paddedW = dataW + pad * 2
        let paddedH = dataH + pad * 2
        let w       = Double(size.width)
        let h       = Double(size.height)
        let scale   = min(w / paddedW, h / paddedH)
        let ox      = (w - paddedW * scale) / 2 - (minX - pad) * scale
        let oy      = (h - paddedH * scale) / 2 - (minY - pad) * scale

        func sc(_ v: Vector2D) -> CGPoint {
            CGPoint(x: v.x * scale + ox, y: v.y * scale + oy)
        }

        for poly in polygons {
            guard !poly.points.isEmpty else { continue }
            switch poly.type {
            case .spline:     drawSpline(ctx: ctx, poly: poly, sc: sc, closed: true)
            case .openSpline: drawSpline(ctx: ctx, poly: poly, sc: sc, closed: false)
            case .line:       drawLinePolygon(ctx: ctx, poly: poly, sc: sc)
            case .point:      drawPoint(ctx: ctx, poly: poly, sc: sc)
            case .oval:       drawOval(ctx: ctx, poly: poly, sc: sc)
            }
        }
    }

    // MARK: Spline

    private func drawSpline(ctx: GraphicsContext, poly: Polygon2D,
                            sc: (Vector2D) -> CGPoint, closed: Bool) {
        let segCount = poly.points.count / 4
        guard segCount > 0 else { return }

        // Control handles (drawn behind main path)
        for i in 0..<segCount {
            let b  = i * 4
            let a0 = sc(poly.points[b])
            let c0 = sc(poly.points[b + 1])
            let c1 = sc(poly.points[b + 2])
            let a1 = sc(poly.points[b + 3])
            var h  = Path()
            h.move(to: a0); h.addLine(to: c0)
            h.move(to: a1); h.addLine(to: c1)
            ctx.stroke(h, with: .color(white: 1, opacity: 0.28), lineWidth: 0.75)
            for cp in [c0, c1] {
                let r: CGFloat = 2
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cp.x - r, y: cp.y - r, width: r * 2, height: r * 2)),
                    with: .color(white: 1, opacity: 0.28), lineWidth: 0.75
                )
            }
        }

        // Main path
        var path = Path()
        path.move(to: sc(poly.points[0]))
        for i in 0..<segCount {
            let b = i * 4
            path.addCurve(
                to:       sc(poly.points[b + 3]),
                control1: sc(poly.points[b + 1]),
                control2: sc(poly.points[b + 2])
            )
        }
        if closed { path.closeSubpath() }
        ctx.stroke(path, with: .color(white: 1, opacity: 0.9), lineWidth: 1.5)

        // Anchor circles (one per segment start)
        for i in 0..<segCount {
            let a = sc(poly.points[i * 4])
            let r: CGFloat = 3.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)),
                with: .color(.white)
            )
        }
    }

    // MARK: Line polygon

    private func drawLinePolygon(ctx: GraphicsContext, poly: Polygon2D,
                                 sc: (Vector2D) -> CGPoint) {
        let pts = poly.points.map(sc)
        var path = Path()
        path.move(to: pts[0])
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        ctx.stroke(path, with: .color(white: 1, opacity: 0.9), lineWidth: 1.5)
        for pt in pts {
            let r: CGFloat = 3.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(.white)
            )
        }
    }

    // MARK: Point

    private func drawPoint(ctx: GraphicsContext, poly: Polygon2D,
                           sc: (Vector2D) -> CGPoint) {
        let pt = sc(poly.points[0])
        let r: CGFloat = 4
        var cross = Path()
        cross.move(to: CGPoint(x: pt.x - r, y: pt.y)); cross.addLine(to: CGPoint(x: pt.x + r, y: pt.y))
        cross.move(to: CGPoint(x: pt.x, y: pt.y - r)); cross.addLine(to: CGPoint(x: pt.x, y: pt.y + r))
        ctx.stroke(cross, with: .color(.cyan), lineWidth: 1.5)
    }

    // MARK: Oval

    private func drawOval(ctx: GraphicsContext, poly: Polygon2D,
                          sc: (Vector2D) -> CGPoint) {
        guard poly.points.count >= 2 else { return }
        let c  = sc(poly.points[0])
        let rp = sc(poly.points[1])
        let rx = abs(rp.x - c.x), ry = abs(rp.y - c.y)
        ctx.stroke(
            Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)),
            with: .color(white: 1, opacity: 0.9), lineWidth: 1.5
        )
        let r: CGFloat = 3.5
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(.white)
        )
    }
}
