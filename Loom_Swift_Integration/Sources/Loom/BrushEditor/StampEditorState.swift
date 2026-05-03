import AppKit
import Combine

final class StampEditorState: ObservableObject {
    @Published var grid: [[RGBAPixel]]
    @Published var rows: Int
    @Published var cols: Int
    @Published var outW: Int
    @Published var outH: Int
    @Published var mode: BrushPaintMode = .draw
    @Published var paintColor: NSColor = .white
    @Published var showGrid: Bool = true
    @Published var wrapShifts: Bool = false
    @Published var selection: BrushSelection? = nil
    @Published var refImage: NSImage? = nil
    @Published var refOpacity: Double = 0.4
    @Published var colorSelectTarget: NSColor = .white
    @Published var colorSelectTolerance: Double = 30.0

    var currentFile: URL? = nil
    var stampsDir: URL? = nil
    var onSave: ((String) -> Void)? = nil

    init(rows: Int = 32, cols: Int = 32, outW: Int = 32, outH: Int = 32) {
        self.rows = rows
        self.cols = cols
        self.outW = outW
        self.outH = outH
        self.grid = makeBlankRGBAGrid(rows: rows, cols: cols)
    }

    func resizeGrid(rows newRows: Int, cols newCols: Int) {
        grid = resampleRGBA(grid, toRows: newRows, toCols: newCols)
        rows = newRows
        cols = newCols
        selection = nil
    }

    func loadFromFile(_ url: URL) throws {
        let (g, r, c) = try loadRGBAPNG(from: url)
        currentFile = url
        if let meta = loadMetaJSON(forFile: url) {
            rows = meta.gridH; cols = meta.gridW
            outW = meta.outW;  outH = meta.outH
        } else {
            rows = r; cols = c
            outW = c; outH = r
        }
        grid = (g.count == rows && (g.first?.count ?? 0) == cols)
            ? g
            : resampleRGBA(g, toRows: rows, toCols: cols)
        selection = nil
    }

    func saveToFile(_ url: URL) throws {
        try exportRGBAPNG(grid: grid, outW: outW, outH: outH, to: url)
        try saveMetaJSON(forFile: url, gridW: cols, gridH: rows, outW: outW, outH: outH)
        currentFile = url
    }
}
