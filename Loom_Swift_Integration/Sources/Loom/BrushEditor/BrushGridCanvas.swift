import AppKit
import SwiftUI

// MARK: - NSViewRepresentable

struct BrushGridCanvas: NSViewRepresentable {
    @ObservedObject var state: BrushEditorState

    func makeNSView(context: Context) -> BrushGridView {
        let view = BrushGridView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: BrushGridView, context: Context) {
        nsView.state = state
        nsView.needsDisplay = true
    }
}

// MARK: - NSView subclass

final class BrushGridView: NSView {

    var state: BrushEditorState? {
        didSet { needsDisplay = true }
    }

    // Cached greyscale downsample of refImage at grid resolution.
    // Rebuilt only when refImage or grid dims change.
    private var refCache: [[Float]]?
    private weak var refCacheImage: NSImage?
    private var refCacheRows: Int = 0
    private var refCacheCols: Int = 0

    private var lastPaintCell: (r: Int, c: Int)? = nil
    private var lastPaintValue: Float = 1.0
    private var selAnchor: (r: Int, c: Int)? = nil

    override var isFlipped: Bool { true }   // row 0 at top
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

        // 1. Black background
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

        // 2. Cell fills (skip black cells for speed)
        let grid = state.grid
        for r in 0 ..< min(rows, grid.count) {
            let row = grid[r]
            for c in 0 ..< min(cols, row.count) {
                let v = row[c]
                guard v > 0 else { continue }
                NSColor(white: CGFloat(v), alpha: 1).setFill()
                NSRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH,
                       width: cellW, height: cellH).fill()
            }
        }

        // 3. Reference image overlay
        if let img = state.refImage, state.refOpacity > 0 {
            img.draw(in: bounds, from: .zero, operation: .sourceOver,
                     fraction: state.refOpacity, respectFlipped: true, hints: nil)
        }

        // 4. Grid lines (skip when cells are sub-pixel)
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
            NSColor(white: 0.33, alpha: 1).setStroke()
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

    // MARK: - Grid mutation helpers

    private func applyPaint(row: Int, col: Int, value: Float) {
        guard let state = state else { return }
        var g = state.grid
        g[row][col] = value
        state.grid = g
    }

    private func applyLine(r0: Int, c0: Int, v0: Float, r1: Int, c1: Int, v1: Float, erase: Bool) {
        guard let state = state else { return }
        var g = state.grid
        paintLine(into: &g, r0: r0, c0: c0, v0: v0, r1: r1, c1: c1, v1: v1, erase: erase)
        state.grid = g
    }

    // MARK: - Paint value helpers

    private func currentPaintValue(at rc: (r: Int, c: Int)) -> Float {
        guard let state = state else { return 1.0 }
        switch state.mode {
        case .draw:              return state.paintValue
        case .erase:             return 0.0
        case .imgDraw:           return refValue(row: rc.r, col: rc.c)
        case .select, .deselect: return 0.0
        }
    }

    private func refValue(row: Int, col: Int) -> Float {
        guard let state = state else { return 0 }
        let needRebuild = refCacheImage !== state.refImage
            || refCache == nil
            || refCacheRows != state.rows
            || refCacheCols != state.cols
        if needRebuild {
            refCacheImage = state.refImage
            refCacheRows  = state.rows
            refCacheCols  = state.cols
            refCache = state.refImage.map {
                buildGreyscaleCache($0, rows: state.rows, cols: state.cols)
            }
        }
        guard let cache = refCache,
              row < cache.count,
              col < (cache.first?.count ?? 0) else { return 0 }
        return cache[row][col]
    }

    /// Downsample an NSImage to a Float grid of the given dimensions.
    /// Uses CGContext with DeviceGray; handles CGImage's bottom-left origin.
    private func buildGreyscaleCache(_ image: NSImage, rows: Int, cols: Int) -> [[Float]] {
        guard rows > 0, cols > 0,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return makeBlankGrid(rows: rows, cols: cols) }
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: cols, height: rows,
                                  bitsPerComponent: 8, bytesPerRow: cols,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return makeBlankGrid(rows: rows, cols: cols) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let buf = ctx.data else { return makeBlankGrid(rows: rows, cols: cols) }
        let px = buf.bindMemory(to: UInt8.self, capacity: rows * cols)
        // CGImage origin is bottom-left; our grid row 0 is top → flip vertically.
        return (0 ..< rows).map { r in
            let cgRow = rows - 1 - r
            return (0 ..< cols).map { c in Float(px[cgRow * cols + c]) / 255.0 }
        }
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        guard let state = state, let cell = cell(for: event) else { return }
        switch state.mode {
        case .draw, .erase, .imgDraw:
            let v = currentPaintValue(at: cell)
            applyPaint(row: cell.r, col: cell.c, value: v)
            lastPaintCell  = cell
            lastPaintValue = v
        case .select:
            selAnchor      = cell
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
            let v = currentPaintValue(at: cell)
            if isShift, let last = lastPaintCell {
                applyLine(r0: last.r, c0: last.c, v0: lastPaintValue,
                          r1: cell.r, c1: cell.c, v1: v,
                          erase: state.mode == .erase)
            } else {
                applyPaint(row: cell.r, col: cell.c, value: v)
            }
            lastPaintCell  = cell
            lastPaintValue = v
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
