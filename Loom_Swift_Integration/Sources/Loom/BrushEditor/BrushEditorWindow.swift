import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppController integration

extension AppController {

    /// Open (or re-focus) the shared brush editor window.
    /// - file: existing PNG to edit; nil = blank canvas
    /// - brushesDir: default directory for open/save panels
    /// - onSave: called with the saved file's basename after every save
    func openBrushEditor(file: URL? = nil,
                         brushesDir: URL,
                         onSave: @escaping (String) -> Void) {
        if brushEditorWindow == nil {
            let state = BrushEditorState()
            brushEditorState = state
            let hosting = NSHostingController(rootView: BrushEditorWindowView(state: state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Brush Editor"
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            win.setContentSize(NSSize(width: 740, height: 540))
            win.minSize    = NSSize(width: 520, height: 400)
            brushEditorWindow = win
        }

        guard let state = brushEditorState else { return }
        state.brushesDir = brushesDir
        state.onSave = onSave
        if let file {
            try? state.loadFromFile(file)
        } else {
            state.grid = makeBlankGrid(rows: state.rows, cols: state.cols)
            state.currentFile = nil
        }
        brushEditorWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Main view

struct BrushEditorWindowView: View {
    @ObservedObject var state: BrushEditorState

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
                BrushGridCanvas(state: state)
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    // MARK: - Row 1: mode picker + file ops

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
            Button("New") { newBrush() }
                .keyboardShortcut("n")
                .controlSize(.small)
            Button("Open…") { openFile() }
                .keyboardShortcut("o")
                .controlSize(.small)
            Button("Save") { save() }
                .keyboardShortcut("s")
                .controlSize(.small)
            Button("Save As…") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .controlSize(.small)
        }
    }

    // MARK: - Row 2: edit + transform

    private var row2: some View {
        HStack(spacing: 4) {
            Toggle("Grid", isOn: $state.showGrid)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Divider().frame(height: 18)
            Button("Clear") {
                state.grid = clearGrid(state.grid, selection: nil)
            }.controlSize(.small)
            Button("Clr Sel") {
                guard state.selection != nil else { return }
                state.grid = clearGrid(state.grid, selection: state.selection)
                state.selection = nil
            }.controlSize(.small)
            Button("Invert") { state.grid = invertGrid(state.grid) }
                .controlSize(.small)
            Divider().frame(height: 18)
            Button("Flip H")  { state.grid = flipHGrid(state.grid) }.controlSize(.small)
            Button("Flip V")  { state.grid = flipVGrid(state.grid) }.controlSize(.small)
            Button("Mir H")   { state.grid = mirrorHGrid(state.grid) }.controlSize(.small)
            Button("Mir V")   { state.grid = mirrorVGrid(state.grid) }.controlSize(.small)
            Button("Rot ←") {
                let r = rotateLeftGrid(state.grid)
                state.rows = r.rows; state.cols = r.cols; state.grid = r.grid
            }.controlSize(.small)
            Button("Rot →") {
                let r = rotateRightGrid(state.grid)
                state.rows = r.rows; state.cols = r.cols; state.grid = r.grid
            }.controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Row 3: shift buttons

    private var row3: some View {
        HStack(spacing: 4) {
            Text("Shift:").font(.system(size: 11))
            Button("◄") {
                state.grid = shiftGrid(state.grid, dr: 0, dc: -1, wrap: state.wrapShifts)
            }.controlSize(.small)
            Button("►") {
                state.grid = shiftGrid(state.grid, dr: 0, dc: 1, wrap: state.wrapShifts)
            }.controlSize(.small)
            Button("▲") {
                state.grid = shiftGrid(state.grid, dr: -1, dc: 0, wrap: state.wrapShifts)
            }.controlSize(.small)
            Button("▼") {
                state.grid = shiftGrid(state.grid, dr: 1, dc: 0, wrap: state.wrapShifts)
            }.controlSize(.small)
            Toggle("Wrap", isOn: $state.wrapShifts)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
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
                    BrushIntField(value: $state.outW, min: 1, max: 2048)
                    Text("H:").font(.system(size: 11))
                    BrushIntField(value: $state.outH, min: 1, max: 2048)
                }
                .padding(.bottom, 6)

                Divider()
                panelHeader("Grid Resolution")
                HStack(spacing: 4) {
                    Text("Rows:").font(.system(size: 11))
                    BrushIntField(value: Binding(
                        get: { state.rows },
                        set: { state.resizeGrid(rows: $0, cols: state.cols) }
                    ), min: 1, max: 512)
                }
                HStack(spacing: 4) {
                    Text("Cols:").font(.system(size: 11))
                    BrushIntField(value: Binding(
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
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.bottom, 6)

                Divider()
                panelHeader("Palette")
                paletteGrid
                HStack(spacing: 4) {
                    Text("Value:").font(.system(size: 11))
                    BrushValueField(value: $state.paintValue)
                }
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
                    Button("Circle") {
                        state.grid = makeCircle(rows: state.rows, cols: state.cols)
                    }.controlSize(.small)
                    Button("Soft") {
                        state.grid = makeSoftCircle(rows: state.rows, cols: state.cols)
                    }.controlSize(.small)
                    Button("Scatter") {
                        state.grid = makeScatter(rows: state.rows, cols: state.cols)
                    }.controlSize(.small)
                }
                .padding(.bottom, 8)

                Spacer()
            }
            .padding(8)
        }
        .frame(width: 164)
    }

    // MARK: - Palette swatch grid (11 evenly-spaced grey values)

    private var paletteGrid: some View {
        let vals: [Float] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 18, maximum: 22), spacing: 2)],
            spacing: 2
        ) {
            ForEach(0 ..< vals.count, id: \.self) { i in
                let v = vals[i]
                BrushPaletteSwatch(value: v, isSelected: abs(state.paintValue - v) < 0.01) {
                    state.paintValue = v
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Section header

    private func panelHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    // MARK: - File operations

    private func newBrush() {
        state.grid = makeBlankGrid(rows: state.rows, cols: state.cols)
        state.selection = nil
        state.currentFile = nil
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Brush"
        panel.allowedContentTypes = [.png]
        panel.directoryURL = state.brushesDir
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
        panel.title = "Save Brush"
        panel.allowedContentTypes = [.png]
        panel.directoryURL = state.brushesDir
        panel.nameFieldStringValue = state.currentFile?.lastPathComponent ?? "brush.png"
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

    /// Stamp the reference image onto the entire grid at full opacity.
    private func applyRefToAll() {
        guard let img = state.refImage else { return }
        state.grid = buildGreyscaleGrid(img, rows: state.rows, cols: state.cols)
    }
}

// MARK: - Palette swatch

private struct BrushPaletteSwatch: View {
    let value: Float
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(white: Double(value)))
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isSelected ? Color.accentColor : Color(white: 0.4),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .onTapGesture { onTap() }
    }
}

// MARK: - Palette value field (0–255 integer display of a Float 0–1)

private struct BrushValueField: View {
    @Binding var value: Float
    @State private var text = "255"
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 44)
            .focused($focused)
            .onAppear { text = fmt(value) }
            .onChange(of: value) { _, v in if !focused { text = fmt(v) } }
            .onChange(of: focused) { _, f in
                if !f { commit(); text = fmt(value) }
            }
            .onSubmit { commit(); text = fmt(value) }
    }

    private func fmt(_ v: Float) -> String { "\(Int((v * 255).rounded()))" }

    private func commit() {
        if let i = Int(text) { value = Float(max(0, min(255, i))) / 255.0 }
    }
}

// MARK: - Buffered integer text field

private struct BrushIntField: View {
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
            .onChange(of: focused) { _, f in
                if !f { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        if let i = Int(text) { value = Swift.max(min, Swift.min(max, i)) }
        text = "\(value)"
    }
}

// MARK: - Greyscale grid sample (shared with BrushGridCanvas.buildGreyscaleCache)

/// Downsample image to a float grid via CGContext(DeviceGray).
/// CGImage origin is bottom-left; output row 0 maps to image top.
private func buildGreyscaleGrid(_ image: NSImage, rows: Int, cols: Int) -> [[Float]] {
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
    return (0 ..< rows).map { r in
        let cgRow = rows - 1 - r
        return (0 ..< cols).map { c in Float(px[cgRow * cols + c]) / 255.0 }
    }
}
