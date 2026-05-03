import Foundation

// All transforms return new grids; none mutate in place.
// Rotate functions also return the new row/col counts (they swap).

// MARK: - Greyscale transforms

func shiftGrid(_ grid: [[Float]], dr: Int, dc: Int, wrap: Bool) -> [[Float]] {
    let rows = grid.count
    guard rows > 0 else { return grid }
    let cols = grid[0].count
    guard cols > 0 else { return grid }
    var out = [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
    for r in 0 ..< rows {
        for c in 0 ..< cols {
            let sr = r - dr
            let sc = c - dc
            if wrap {
                let wr = ((sr % rows) + rows) % rows
                let wc = ((sc % cols) + cols) % cols
                out[r][c] = grid[wr][wc]
            } else {
                out[r][c] = (sr >= 0 && sr < rows && sc >= 0 && sc < cols) ? grid[sr][sc] : 0
            }
        }
    }
    return out
}

func flipHGrid(_ grid: [[Float]]) -> [[Float]] {
    grid.map { $0.reversed() }
}

func flipVGrid(_ grid: [[Float]]) -> [[Float]] {
    grid.reversed()
}

func mirrorHGrid(_ grid: [[Float]]) -> [[Float]] {
    let rows = grid.count
    guard rows > 0 else { return grid }
    let cols = grid[0].count
    guard cols > 0 else { return grid }
    let half = cols / 2
    var out = grid
    for r in 0 ..< rows {
        for c in 0 ..< half {
            out[r][cols - 1 - c] = grid[r][c]
        }
    }
    return out
}

func mirrorVGrid(_ grid: [[Float]]) -> [[Float]] {
    let rows = grid.count
    guard rows > 0 else { return grid }
    let half = rows / 2
    var out = grid
    for r in 0 ..< half {
        out[rows - 1 - r] = grid[r]
    }
    return out
}

/// Returns (newGrid, newRows, newCols) — rows and cols swap on rotation.
func rotateLeftGrid(_ grid: [[Float]]) -> (grid: [[Float]], rows: Int, cols: Int) {
    let rows = grid.count
    guard rows > 0 else { return (grid, 0, 0) }
    let cols = grid[0].count
    // CCW 90°: out[c][rows-1-r] = grid[r][c]  →  out[r][c] = grid[c][rows-1-r]
    var out = [[Float]](repeating: [Float](repeating: 0, count: rows), count: cols)
    for r in 0 ..< rows {
        for c in 0 ..< cols {
            out[c][rows - 1 - r] = grid[r][c]
        }
    }
    return (out, cols, rows)
}

func rotateRightGrid(_ grid: [[Float]]) -> (grid: [[Float]], rows: Int, cols: Int) {
    let rows = grid.count
    guard rows > 0 else { return (grid, 0, 0) }
    let cols = grid[0].count
    // CW 90°: out[cols-1-c][r] = grid[r][c]  →  out[r][c] = grid[cols-1-c][... ]
    var out = [[Float]](repeating: [Float](repeating: 0, count: rows), count: cols)
    for r in 0 ..< rows {
        for c in 0 ..< cols {
            out[cols - 1 - c][r] = grid[r][c]
        }
    }
    return (out, cols, rows)
}

func invertGrid(_ grid: [[Float]]) -> [[Float]] {
    grid.map { $0.map { 1.0 - $0 } }
}

/// Clear entire grid or a rectangular selection to 0.
func clearGrid(_ grid: [[Float]], selection: BrushSelection?) -> [[Float]] {
    guard let sel = selection else {
        let rows = grid.count
        let cols = rows > 0 ? grid[0].count : 0
        return [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
    }
    var out = grid
    for r in sel.r1 ... sel.r2 {
        for c in sel.c1 ... sel.c2 {
            out[r][c] = 0
        }
    }
    return out
}

/// Paint a Bresenham line of values between two cells.
/// v0 is the value at (r0,c0); v1 at (r1,c1); erase=true forces 0 throughout.
func paintLine(into grid: inout [[Float]],
               r0: Int, c0: Int, v0: Float,
               r1: Int, c1: Int, v1: Float,
               erase: Bool) {
    let rows = grid.count
    let cols = rows > 0 ? grid[0].count : 0
    let points = bresenham(r0: r0, c0: c0, r1: r1, c1: c1)
    let n = points.count
    for (i, pt) in points.enumerated() {
        guard pt.r >= 0, pt.r < rows, pt.c >= 0, pt.c < cols else { continue }
        if erase {
            grid[pt.r][pt.c] = 0
        } else {
            let t = n > 1 ? Float(i) / Float(n - 1) : 0
            grid[pt.r][pt.c] = v0 + (v1 - v0) * t
        }
    }
}

/// Paint a Bresenham line of a single pixel colour into an RGBA grid.
/// erase=true forces .clear at every point instead.
func paintLineRGBA(into grid: inout [[RGBAPixel]],
                   r0: Int, c0: Int,
                   r1: Int, c1: Int,
                   pixel: RGBAPixel, erase: Bool) {
    let rows = grid.count
    let cols = rows > 0 ? grid[0].count : 0
    for pt in bresenham(r0: r0, c0: c0, r1: r1, c1: c1) {
        guard pt.r >= 0, pt.r < rows, pt.c >= 0, pt.c < cols else { continue }
        grid[pt.r][pt.c] = erase ? .clear : pixel
    }
}

// MARK: - RGBA transforms (same logic, different element type)

func shiftRGBA(_ grid: [[RGBAPixel]], dr: Int, dc: Int, wrap: Bool) -> [[RGBAPixel]] {
    let rows = grid.count
    guard rows > 0 else { return grid }
    let cols = grid[0].count
    var out = [[RGBAPixel]](repeating: [RGBAPixel](repeating: .clear, count: cols), count: rows)
    for r in 0 ..< rows {
        for c in 0 ..< cols {
            let sr = r - dr; let sc = c - dc
            if wrap {
                out[r][c] = grid[((sr % rows) + rows) % rows][((sc % cols) + cols) % cols]
            } else if sr >= 0, sr < rows, sc >= 0, sc < cols {
                out[r][c] = grid[sr][sc]
            }
        }
    }
    return out
}

func flipHRGBA(_ grid: [[RGBAPixel]]) -> [[RGBAPixel]] { grid.map { $0.reversed() } }
func flipVRGBA(_ grid: [[RGBAPixel]]) -> [[RGBAPixel]] { grid.reversed() }

func mirrorHRGBA(_ grid: [[RGBAPixel]]) -> [[RGBAPixel]] {
    let rows = grid.count; guard rows > 0 else { return grid }
    let cols = grid[0].count; let half = cols / 2
    var out = grid
    for r in 0 ..< rows { for c in 0 ..< half { out[r][cols - 1 - c] = grid[r][c] } }
    return out
}

func mirrorVRGBA(_ grid: [[RGBAPixel]]) -> [[RGBAPixel]] {
    let rows = grid.count; let half = rows / 2
    var out = grid
    for r in 0 ..< half { out[rows - 1 - r] = grid[r] }
    return out
}

func rotateLeftRGBA(_ grid: [[RGBAPixel]]) -> (grid: [[RGBAPixel]], rows: Int, cols: Int) {
    let rows = grid.count; guard rows > 0 else { return (grid, 0, 0) }
    let cols = grid[0].count
    var out = [[RGBAPixel]](repeating: [RGBAPixel](repeating: .clear, count: rows), count: cols)
    for r in 0 ..< rows { for c in 0 ..< cols { out[c][rows - 1 - r] = grid[r][c] } }
    return (out, cols, rows)
}

func rotateRightRGBA(_ grid: [[RGBAPixel]]) -> (grid: [[RGBAPixel]], rows: Int, cols: Int) {
    let rows = grid.count; guard rows > 0 else { return (grid, 0, 0) }
    let cols = grid[0].count
    var out = [[RGBAPixel]](repeating: [RGBAPixel](repeating: .clear, count: rows), count: cols)
    for r in 0 ..< rows { for c in 0 ..< cols { out[cols - 1 - c][r] = grid[r][c] } }
    return (out, cols, rows)
}

func invertRGBA(_ grid: [[RGBAPixel]]) -> [[RGBAPixel]] {
    grid.map { row in row.map { p in
        RGBAPixel(r: 255 - p.r, g: 255 - p.g, b: 255 - p.b, a: p.a)
    }}
}

func clearRGBA(_ grid: [[RGBAPixel]], selection: BrushSelection?) -> [[RGBAPixel]] {
    guard let sel = selection else {
        let rows = grid.count; let cols = rows > 0 ? grid[0].count : 0
        return [[RGBAPixel]](repeating: [RGBAPixel](repeating: .clear, count: cols), count: rows)
    }
    var out = grid
    for r in sel.r1 ... sel.r2 { for c in sel.c1 ... sel.c2 { out[r][c] = .clear } }
    return out
}

// MARK: - Shared helpers

struct BrushSelection: Equatable {
    var r1, c1, r2, c2: Int

    /// Normalised so r1≤r2, c1≤c2.
    init(r1: Int, c1: Int, r2: Int, c2: Int) {
        self.r1 = min(r1, r2); self.c1 = min(c1, c2)
        self.r2 = max(r1, r2); self.c2 = max(c1, c2)
    }

    func contains(r: Int, c: Int) -> Bool {
        r >= r1 && r <= r2 && c >= c1 && c <= c2
    }
}

private struct Cell { var r, c: Int }

private func bresenham(r0: Int, c0: Int, r1: Int, c1: Int) -> [Cell] {
    var pts: [Cell] = []
    var r = r0; var c = c0
    let dr = abs(r1 - r0); let dc = abs(c1 - c0)
    let sr = r1 > r0 ? 1 : -1; let sc = c1 > c0 ? 1 : -1
    var err = dr - dc
    while true {
        pts.append(Cell(r: r, c: c))
        if r == r1 && c == c1 { break }
        let e2 = 2 * err
        if e2 > -dc { err -= dc; r += sr }
        if e2 <  dr { err += dr; c += sc }
    }
    return pts
}
