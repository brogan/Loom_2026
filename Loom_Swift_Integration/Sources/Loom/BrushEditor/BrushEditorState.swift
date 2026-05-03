import AppKit
import Combine

enum BrushPaintMode: String, CaseIterable {
    case draw, erase, imgDraw, select, deselect
}

final class BrushEditorState: ObservableObject {
    @Published var grid: [[Float]]
    @Published var rows: Int
    @Published var cols: Int
    @Published var outW: Int
    @Published var outH: Int
    @Published var mode: BrushPaintMode = .draw
    @Published var paintValue: Float = 1.0
    @Published var showGrid: Bool = true
    @Published var wrapShifts: Bool = false
    @Published var selection: BrushSelection? = nil
    @Published var refImage: NSImage? = nil
    @Published var refOpacity: Double = 0.4

    var currentFile: URL? = nil
    var brushesDir: URL? = nil
    var onSave: ((String) -> Void)? = nil

    init(rows: Int = 32, cols: Int = 32, outW: Int = 32, outH: Int = 32) {
        self.rows = rows
        self.cols = cols
        self.outW = outW
        self.outH = outH
        self.grid = makeBlankGrid(rows: rows, cols: cols)
    }

    /// Resample grid to new dimensions (nearest-neighbour) and update row/col counts.
    func resizeGrid(rows newRows: Int, cols newCols: Int) {
        grid = resampleGrid(grid, toRows: newRows, toCols: newCols)
        rows = newRows
        cols = newCols
        selection = nil
    }

    func loadFromFile(_ url: URL) throws {
        let (g, r, c) = try loadGreyscalePNG(from: url)
        currentFile = url
        if let meta = loadMetaJSON(forFile: url) {
            rows = meta.gridH; cols = meta.gridW
            outW = meta.outW;  outH = meta.outH
        } else {
            rows = r; cols = c
            outW = c; outH = r
        }
        grid = g.count == rows && (g.first?.count ?? 0) == cols
            ? g
            : resampleGrid(g, toRows: rows, toCols: cols)
        selection = nil
    }

    func saveToFile(_ url: URL) throws {
        try exportGreyscalePNG(grid: grid, outW: outW, outH: outH, to: url)
        try saveMetaJSON(forFile: url, gridW: cols, gridH: rows, outW: outW, outH: outH)
        currentFile = url
    }
}
