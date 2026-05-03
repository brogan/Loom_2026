import Foundation

// MARK: - Greyscale presets

/// Hard-edged circle: cells within radius = 1.0, outside = 0.0.
func makeCircle(rows: Int, cols: Int) -> [[Float]] {
    let cr = Double(rows - 1) / 2.0
    let cc = Double(cols - 1) / 2.0
    let radius = min(cr, cc)
    return (0 ..< rows).map { r in
        (0 ..< cols).map { c in
            let d = hypot(Double(r) - cr, Double(c) - cc)
            return d <= radius ? 1.0 : 0.0
        }
    }
}

/// Soft circle: value = 1.0 - (dist / radius), clamped to [0, 1].
func makeSoftCircle(rows: Int, cols: Int) -> [[Float]] {
    let cr = Double(rows - 1) / 2.0
    let cc = Double(cols - 1) / 2.0
    let radius = min(cr, cc)
    guard radius > 0 else { return makeBlankGrid(rows: rows, cols: cols) }
    return (0 ..< rows).map { r in
        (0 ..< cols).map { c in
            let d = hypot(Double(r) - cr, Double(c) - cc)
            return Float(max(0.0, 1.0 - d / radius))
        }
    }
}

/// Scatter: random dots within the inscribed circle, density ~30%.
func makeScatter(rows: Int, cols: Int, seed: Int = 42) -> [[Float]] {
    let cr = Double(rows - 1) / 2.0
    let cc = Double(cols - 1) / 2.0
    let radius = min(cr, cc)
    var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed)))
    return (0 ..< rows).map { r in
        (0 ..< cols).map { c in
            let d = hypot(Double(r) - cr, Double(c) - cc)
            guard d <= radius else { return 0.0 as Float }
            let t = Float(rng.next() & 0x00FF_FFFF) / Float(0x00FF_FFFF)
            return t < 0.3 ? 1.0 : 0.0
        }
    }
}

/// All-zero grid of given dimensions.
func makeBlankGrid(rows: Int, cols: Int) -> [[Float]] {
    [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
}

/// All-transparent RGBA grid.
func makeBlankRGBAGrid(rows: Int, cols: Int) -> [[RGBAPixel]] {
    [[RGBAPixel]](repeating: [RGBAPixel](repeating: .clear, count: cols), count: rows)
}

// MARK: - Resample float grid to new dimensions (nearest-neighbour)

func resampleGrid(_ grid: [[Float]], toRows newRows: Int, toCols newCols: Int) -> [[Float]] {
    let oldRows = grid.count
    guard oldRows > 0 else { return makeBlankGrid(rows: newRows, cols: newCols) }
    let oldCols = grid[0].count
    guard oldCols > 0 else { return makeBlankGrid(rows: newRows, cols: newCols) }
    return (0 ..< newRows).map { r in
        let sr = Int(Double(r) * Double(oldRows) / Double(newRows))
        return (0 ..< newCols).map { c in
            let sc = Int(Double(c) * Double(oldCols) / Double(newCols))
            return grid[min(sr, oldRows - 1)][min(sc, oldCols - 1)]
        }
    }
}

func resampleRGBA(_ grid: [[RGBAPixel]], toRows newRows: Int, toCols newCols: Int) -> [[RGBAPixel]] {
    let oldRows = grid.count
    guard oldRows > 0 else { return makeBlankRGBAGrid(rows: newRows, cols: newCols) }
    let oldCols = grid[0].count
    guard oldCols > 0 else { return makeBlankRGBAGrid(rows: newRows, cols: newCols) }
    return (0 ..< newRows).map { r in
        let sr = Int(Double(r) * Double(oldRows) / Double(newRows))
        return (0 ..< newCols).map { c in
            let sc = Int(Double(c) * Double(oldCols) / Double(newCols))
            return grid[min(sr, oldRows - 1)][min(sc, oldCols - 1)]
        }
    }
}

