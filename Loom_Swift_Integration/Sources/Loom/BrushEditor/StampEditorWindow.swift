import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppController integration

extension AppController {

    func openStampEditor(file: URL? = nil,
                         stampsDir: URL,
                         onSave: @escaping (String) -> Void) {
        if stampEditorWindow == nil {
            let state = StampEditorState()
            stampEditorState = state
            let hosting = NSHostingController(rootView: StampEditorWindowView(state: state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Stamp Editor"
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            win.setContentSize(NSSize(width: 740, height: 540))
            win.minSize    = NSSize(width: 520, height: 400)
            stampEditorWindow = win
        }

        guard let state = stampEditorState else { return }
        state.stampsDir = stampsDir
        state.onSave = onSave
        if let file {
            try? state.loadFromFile(file)
        } else {
            state.grid = makeBlankRGBAGrid(rows: state.rows, cols: state.cols)
            state.currentFile = nil
        }
        stampEditorWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Main view

struct StampEditorWindowView: View {
    @ObservedObject var state: StampEditorState

    @State private var scaleFactor: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            row1.padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            row2.padding(.horizontal, 8).padding(.bottom, 2)
            row3.padding(.horizontal, 8).padding(.bottom, 4)
            Divider()
            HStack(spacing: 0) {
                leftPanel
                Divider()
                StampGridCanvas(state: state)
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    // MARK: - Row 1: mode + file ops

    private var row1: some View {
        HStack(spacing: 6) {
            Text("Mode:").font(.system(size: 11))
            Picker("", selection: $state.mode) {
                Text("Draw").tag(BrushPaintMode.draw)
                Text("Erase").tag(BrushPaintMode.erase)
                Text("Img").tag(BrushPaintMode.imgDraw)
                Text("Sel").tag(BrushPaintMode.select)
                Text("Desel").tag(BrushPaintMode.deselect)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("New")      { newStamp() }       .keyboardShortcut("n").controlSize(.small)
            Button("Open…")    { openFile() }        .keyboardShortcut("o").controlSize(.small)
            Button("Save")     { save() }            .keyboardShortcut("s").controlSize(.small)
            Button("Save As…") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .controlSize(.small)
        }
    }

    // MARK: - Row 2: edit + transform

    private var row2: some View {
        HStack(spacing: 4) {
            Toggle("Grid", isOn: $state.showGrid)
                .toggleStyle(.checkbox).font(.system(size: 11))
            Divider().frame(height: 18)
            Button("Clear") {
                state.grid = clearRGBA(state.grid, selection: nil)
            }.controlSize(.small)
            Button("Clr Sel") {
                guard state.selection != nil else { return }
                state.grid = clearRGBA(state.grid, selection: state.selection)
                state.selection = nil
            }.controlSize(.small)
            Button("Invert") { state.grid = invertRGBA(state.grid) }.controlSize(.small)
            Divider().frame(height: 18)
            Button("Flip H")  { state.grid = flipHRGBA(state.grid) }.controlSize(.small)
            Button("Flip V")  { state.grid = flipVRGBA(state.grid) }.controlSize(.small)
            Button("Mir H")   { state.grid = mirrorHRGBA(state.grid) }.controlSize(.small)
            Button("Mir V")   { state.grid = mirrorVRGBA(state.grid) }.controlSize(.small)
            Button("Rot ←") {
                let r = rotateLeftRGBA(state.grid)
                state.rows = r.rows; state.cols = r.cols; state.grid = r.grid
            }.controlSize(.small)
            Button("Rot →") {
                let r = rotateRightRGBA(state.grid)
                state.rows = r.rows; state.cols = r.cols; state.grid = r.grid
            }.controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Row 3: shifts

    private var row3: some View {
        HStack(spacing: 4) {
            Text("Shift:").font(.system(size: 11))
            Button("◄") { state.grid = shiftRGBA(state.grid, dr: 0, dc: -1, wrap: state.wrapShifts) }.controlSize(.small)
            Button("►") { state.grid = shiftRGBA(state.grid, dr: 0, dc:  1, wrap: state.wrapShifts) }.controlSize(.small)
            Button("▲") { state.grid = shiftRGBA(state.grid, dr: -1, dc: 0, wrap: state.wrapShifts) }.controlSize(.small)
            Button("▼") { state.grid = shiftRGBA(state.grid, dr:  1, dc: 0, wrap: state.wrapShifts) }.controlSize(.small)
            Toggle("Wrap", isOn: $state.wrapShifts)
                .toggleStyle(.checkbox).font(.system(size: 11))
            Spacer()
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                panelHeader("Output Size (px)")
                HStack(spacing: 4) {
                    Text("W:").font(.system(size: 11))
                    StampIntField(value: $state.outW, min: 1, max: 2048)
                    Text("H:").font(.system(size: 11))
                    StampIntField(value: $state.outH, min: 1, max: 2048)
                }
                .padding(.bottom, 6)

                Divider()
                panelHeader("Grid Resolution")
                HStack(spacing: 4) {
                    Text("Rows:").font(.system(size: 11))
                    StampIntField(value: Binding(
                        get: { state.rows },
                        set: { state.resizeGrid(rows: $0, cols: state.cols) }
                    ), min: 1, max: 512)
                }
                HStack(spacing: 4) {
                    Text("Cols:").font(.system(size: 11))
                    StampIntField(value: Binding(
                        get: { state.cols },
                        set: { state.resizeGrid(rows: state.rows, cols: $0) }
                    ), min: 1, max: 512)
                }
                HStack(spacing: 4) {
                    Text("×:").font(.system(size: 11))
                    FloatEntryField(value: $scaleFactor, width: 40, fractionDigits: 2)
                    Button("Apply ×") { applyScale() }.controlSize(.small)
                }
                .padding(.bottom, 4)
                Toggle("Wrap shifts", isOn: $state.wrapShifts)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                    .padding(.bottom, 6)

                Divider()
                panelHeader("Paint Color")
                HStack(spacing: 6) {
                    ColorPicker("", selection: paintColorBinding)
                        .labelsHidden()
                        .frame(width: 44, height: 26)
                    Text("Paint color").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                Divider()
                panelHeader("Color Select")
                HStack(spacing: 6) {
                    ColorPicker("", selection: selectTargetBinding)
                        .labelsHidden()
                        .frame(width: 44, height: 26)
                    Text("Target").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("Tol:").font(.system(size: 11))
                    Slider(value: $state.colorSelectTolerance, in: 0...255)
                        .frame(maxWidth: 70)
                    Text("\(Int(state.colorSelectTolerance))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28)
                }
                Button("Make Transparent") { applyColorSelect() }
                    .controlSize(.small)
                    .padding(.top, 2)
                    .padding(.bottom, 6)

                Divider()
                panelHeader("Reference Image")
                Button("Load Image…") { loadRefImage() }.controlSize(.small)
                HStack(spacing: 4) {
                    Text("Opacity:").font(.system(size: 11))
                    FloatEntryField(value: $state.refOpacity, width: 40, fractionDigits: 2)
                }
                if state.refImage != nil {
                    Button("Apply to All") { applyRefToAll() }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                Spacer(minLength: 6)

                Divider()
                panelHeader("Presets")
                HStack(spacing: 4) {
                    Button("Clear") {
                        state.grid = makeBlankRGBAGrid(rows: state.rows, cols: state.cols)
                    }.controlSize(.small)
                    Button("Fill") {
                        fillWithPaintColor()
                    }.controlSize(.small)
                }
                .padding(.bottom, 8)

                Spacer()
            }
            .padding(8)
        }
        .frame(width: 164)
    }

    // MARK: - Color bindings (NSColor ↔ SwiftUI Color)

    private var paintColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.paintColor) },
            set: { state.paintColor = NSColor($0) }
        )
    }

    private var selectTargetBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.colorSelectTarget) },
            set: { state.colorSelectTarget = NSColor($0) }
        )
    }

    // MARK: - Section header

    private func panelHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    // MARK: - File operations

    private func newStamp() {
        state.grid = makeBlankRGBAGrid(rows: state.rows, cols: state.cols)
        state.selection = nil
        state.currentFile = nil
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Stamp"
        panel.allowedContentTypes = [.png]
        panel.directoryURL = state.stampsDir
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? state.loadFromFile(url)
        }
    }

    private func save() {
        if let url = state.currentFile {
            try? state.saveToFile(url)
            state.onSave?(url.lastPathComponent)
        } else {
            saveAs()
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.title = "Save Stamp"
        panel.allowedContentTypes = [.png]
        panel.directoryURL = state.stampsDir
        panel.nameFieldStringValue = state.currentFile?.lastPathComponent ?? "stamp.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? state.saveToFile(url)
            state.onSave?(url.lastPathComponent)
        }
    }

    // MARK: - Grid operations

    private func applyScale() {
        guard scaleFactor > 0 else { return }
        let newR = max(1, min(512, Int((Double(state.rows) * scaleFactor).rounded())))
        let newC = max(1, min(512, Int((Double(state.cols) * scaleFactor).rounded())))
        state.resizeGrid(rows: newR, cols: newC)
    }

    private func loadRefImage() {
        let panel = NSOpenPanel()
        panel.title = "Load Reference Image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            state.refImage = NSImage(contentsOf: url)
        }
    }

    private func applyRefToAll() {
        guard let img = state.refImage else { return }
        state.grid = buildRGBAGrid(img, rows: state.rows, cols: state.cols)
    }

    private func fillWithPaintColor() {
        let px = nsColorToPixel(state.paintColor)
        state.grid = (0 ..< state.rows).map { _ in
            [RGBAPixel](repeating: px, count: state.cols)
        }
    }

    private func applyColorSelect() {
        let target = state.colorSelectTarget.usingColorSpace(.deviceRGB) ?? state.colorSelectTarget
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let tol = state.colorSelectTolerance
        var g = state.grid
        for r in 0 ..< state.rows {
            for c in 0 ..< state.cols {
                let px = g[r][c]
                let dr = Double(px.r) - tr * 255
                let dg = Double(px.g) - tg * 255
                let db = Double(px.b) - tb * 255
                if sqrt(dr*dr + dg*dg + db*db) < tol {
                    g[r][c] = .clear
                }
            }
        }
        state.grid = g
    }
}

// MARK: - Buffered integer field

private struct StampIntField: View {
    @Binding var value: Int
    var min: Int = 1
    var max: Int = 1024

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 44)
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        if let i = Int(text) { value = Swift.max(min, Swift.min(max, i)) }
        text = "\(value)"
    }
}

// MARK: - Sample reference image to RGBA grid (same y-flip logic as greyscale variant)

private func buildRGBAGrid(_ image: NSImage, rows: Int, cols: Int) -> [[RGBAPixel]] {
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
