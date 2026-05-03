import AppKit
import CoreGraphics
import SwiftUI

// MARK: - NSViewRepresentable

struct StampGridCanvas: NSViewRepresentable {
    @ObservedObject var state: StampEditorState

    func makeNSView(context: Context) -> StampGridView {
        let view = StampGridView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: StampGridView, context: Context) {
        nsView.state = state
        nsView.needsDisplay = true
    }
}

// MARK: - NSView subclass

final class StampGridView: NSView {

    var state: StampEditorState? { didSet { needsDisplay = true } }

    private var refCache: [[RGBAPixel]]?
    private weak var refCacheImage: NSImage?
    private var refCacheRows: Int = 0
    private var refCacheCols: Int = 0

    private var lastPaintCell: (r: Int, c: Int)? = nil
    private var lastPaintPixel: RGBAPixel = .black
    private var selAnchor: (r: Int, c: Int)? = nil

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let state = state else { return }
        let rows = state.rows
        let cols = state.cols
        guard rows > 0, cols > 0 else { return }

        let W = bounds.width
        let H = bounds.height
        let cellW = W / CGFloat(cols)
        let cellH = H / CGFloat(rows)

        // 1. Checkered background (8×8 pt squares)
        let sq: CGFloat = 8
        var row = 0
        var y: CGFloat = 0
        while y < H {
            var col = 0
            var x: CGFloat = 0
            while x < W {
                NSColor(white: (row + col) % 2 == 0 ? 0.70 : 0.45, alpha: 1).setFill()
                NSRect(x: x, y: y, width: sq, height: sq).fill()
                x += sq; col += 1
            }
            y += sq; row += 1
        }

        // 2. Cell fills composited over checker
        let grid = state.grid
        for r in 0 ..< min(rows, grid.count) {
            let gridRow = grid[r]
            for c in 0 ..< min(cols, gridRow.count) {
                let px = gridRow[c]
                guard px.a > 0 else { continue }
                NSColor(
                    red:   CGFloat(px.r) / 255,
                    green: CGFloat(px.g) / 255,
                    blue:  CGFloat(px.b) / 255,
                    alpha: CGFloat(px.a) / 255
                ).setFill()
                NSRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH,
                       width: cellW, height: cellH).fill()
            }
        }

        // 3. Reference image overlay
        if let img = state.refImage, state.refOpacity > 0 {
            img.draw(in: bounds, from: .zero, operation: .sourceOver,
                     fraction: state.refOpacity, respectFlipped: true, hints: nil)
        }

        // 4. Grid lines (skip sub-pixel)
        if state.showGrid, cellW >= 2, cellH >= 2 {
            let path = NSBezierPath()
            path.lineWidth = 0.5
            for c in 1 ..< cols {
                let x = CGFloat(c) * cellW
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: H))
            }
            for r in 1 ..< rows {
                let y = CGFloat(r) * cellH
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: W, y: y))
            }
            NSColor(white: 0.33, alpha: 0.6).setStroke()
            path.stroke()
        }

        // 5. Centre guides
        let guideColor = NSColor(calibratedRed: 0.3, green: 0.4, blue: 1.0, alpha: 0.75)
        guideColor.setStroke()
        let guide = NSBezierPath()
        guide.lineWidth = 1.0
        let cx = CGFloat(cols / 2) * cellW
        let cy = CGFloat(rows / 2) * cellH
        guide.move(to: NSPoint(x: cx, y: 0)); guide.line(to: NSPoint(x: cx, y: H))
        guide.move(to: NSPoint(x: 0, y: cy)); guide.line(to: NSPoint(x: W, y: cy))
        guide.stroke()

        // 6. Selection rectangle
        if let sel = state.selection {
            let sx = CGFloat(sel.c1) * cellW
            let sy = CGFloat(sel.r1) * cellH
            let sw = CGFloat(sel.c2 - sel.c1 + 1) * cellW
            let sh = CGFloat(sel.r2 - sel.r1 + 1) * cellH
            let selPath = NSBezierPath(rect: NSRect(x: sx, y: sy, width: sw, height: sh))
            selPath.lineWidth = 1.5
            let dash: [CGFloat] = [4, 3]
            selPath.setLineDash(dash, count: dash.count, phase: 0)
            NSColor(calibratedRed: 0.2, green: 0.55, blue: 1.0, alpha: 1).setStroke()
            selPath.stroke()
        }
    }

    // MARK: - Coordinate helpers

    private func cell(for event: NSEvent) -> (r: Int, c: Int)? {
        guard let state = state, state.rows > 0, state.cols > 0 else { return nil }
        let pt = convert(event.locationInWindow, from: nil)
        let c = Int(pt.x / (bounds.width  / CGFloat(state.cols)))
        let r = Int(pt.y / (bounds.height / CGFloat(state.rows)))
        guard c >= 0, c < state.cols, r >= 0, r < state.rows else { return nil }
        return (r, c)
    }

    // MARK: - Paint value

    private func currentPixel(at rc: (r: Int, c: Int)) -> RGBAPixel {
        guard let state = state else { return .clear }
        switch state.mode {
        case .draw:              return nsColorToPixel(state.paintColor)
        case .erase:             return .clear
        case .imgDraw:           return refPixel(row: rc.r, col: rc.c)
        case .select, .deselect: return .clear
        }
    }

    private func refPixel(row: Int, col: Int) -> RGBAPixel {
        guard let state = state else { return .clear }
        let needRebuild = refCacheImage !== state.refImage
            || refCache == nil
            || refCacheRows != state.rows
            || refCacheCols != state.cols
        if needRebuild {
            refCacheImage = state.refImage
            refCacheRows  = state.rows
            refCacheCols  = state.cols
            refCache = state.refImage.map {
                buildRGBACache($0, rows: state.rows, cols: state.cols)
            }
        }
        guard let cache = refCache,
              row < cache.count,
              col < (cache.first?.count ?? 0)
        else { return .clear }
        return cache[row][col]
    }

    private func buildRGBACache(_ image: NSImage, rows: Int, cols: Int) -> [[RGBAPixel]] {
        guard rows > 0, cols > 0,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return makeBlankRGBAGrid(rows: rows, cols: cols) }
        let cs   = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let bpr  = cols * 4
        guard let ctx = CGContext(data: nil, width: cols, height: rows,
                                  bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: cs, bitmapInfo: info)
        else { return makeBlankRGBAGrid(rows: rows, cols: cols) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let buf = ctx.data else { return makeBlankRGBAGrid(rows: rows, cols: cols) }
        let px = buf.bindMemory(to: UInt8.self, capacity: rows * bpr)
        return (0 ..< rows).map { r in
            let cgRow = rows - 1 - r
            return (0 ..< cols).map { c in
                let base = cgRow * bpr + c * 4
                let a  = px[base + 3]
                let af = a > 0 ? 255.0 / Float(a) : 0
                return RGBAPixel(
                    r: UInt8(min(255, Float(px[base])     * af)),
                    g: UInt8(min(255, Float(px[base + 1]) * af)),
                    b: UInt8(min(255, Float(px[base + 2]) * af)),
                    a: a
                )
            }
        }
    }

    // MARK: - Grid mutation

    private func applyPaint(row: Int, col: Int, pixel: RGBAPixel) {
        guard let state = state else { return }
        var g = state.grid
        g[row][col] = pixel
        state.grid = g
    }

    private func applyLine(r0: Int, c0: Int, r1: Int, c1: Int, pixel: RGBAPixel, erase: Bool) {
        guard let state = state else { return }
        var g = state.grid
        paintLineRGBA(into: &g, r0: r0, c0: c0, r1: r1, c1: c1, pixel: pixel, erase: erase)
        state.grid = g
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        guard let state = state, let cell = cell(for: event) else { return }
        switch state.mode {
        case .draw, .erase, .imgDraw:
            let px = currentPixel(at: cell)
            applyPaint(row: cell.r, col: cell.c, pixel: px)
            lastPaintCell  = cell
            lastPaintPixel = px
        case .select:
            selAnchor = cell
            state.selection = BrushSelection(r1: cell.r, c1: cell.c, r2: cell.r, c2: cell.c)
        case .deselect:
            state.selection = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = state, let cell = cell(for: event) else { return }
        let isShift = event.modifierFlags.contains(.shift)
        switch state.mode {
        case .draw, .erase, .imgDraw:
            let px = currentPixel(at: cell)
            if isShift, let last = lastPaintCell {
                applyLine(r0: last.r, c0: last.c, r1: cell.r, c1: cell.c,
                          pixel: lastPaintPixel, erase: state.mode == .erase)
            } else {
                applyPaint(row: cell.r, col: cell.c, pixel: px)
            }
            lastPaintCell  = cell
            lastPaintPixel = px
        case .select:
            if let anchor = selAnchor {
                state.selection = BrushSelection(r1: anchor.r, c1: anchor.c,
                                                 r2: cell.r,   c2: cell.c)
            }
        case .deselect:
            state.selection = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastPaintCell = nil
        selAnchor     = nil
    }
}

// MARK: - NSColor → RGBAPixel

func nsColorToPixel(_ color: NSColor) -> RGBAPixel {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return RGBAPixel(
        r: UInt8((r * 255).rounded()),
        g: UInt8((g * 255).rounded()),
        b: UInt8((b * 255).rounded()),
        a: UInt8((a * 255).rounded())
    )
}
