import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LoomEngine

// MARK: - Color palette editor

struct ColorPaletteEditor: View {
    @EnvironmentObject private var controller: AppController
    @Binding var palette: [LoomColor]

    @State private var selectedIndex: Int? = nil

    private var palettesDir: URL? {
        controller.projectURL?.appendingPathComponent("palettes")
    }

    var body: some View {
        colorPaletteHeader
        colorPaletteRows
    }

    private var colorPaletteHeader: some View {
        HStack(spacing: 4) {
            Text("Palette")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dup") { duplicateSelectedColor() }
                .controlSize(.mini)
                .disabled(selectedIndex == nil)
            Button("Save…") { saveColorPalette() }
                .controlSize(.mini)
                .disabled(palette.isEmpty)
            Button("Import…") { importColorPalette() }
                .controlSize(.mini)
            Button {
                palette.append(LoomColor(r: 0, g: 0, b: 0, a: 255))
                selectedIndex = palette.count - 1
            } label: {
                Image(systemName: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var colorPaletteRows: some View {
        ForEach(palette.indices, id: \.self) { ci in
            HStack(spacing: 4) {
                LoomColorField(label: "  \(ci)", color: colorItemBinding(ci))
                    .background(selectedIndex == ci
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedIndex = ci }
                Button {
                    removeColor(at: ci)
                } label: {
                    Image(systemName: "minus").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
            }
        }
    }

    private func colorItemBinding(_ i: Int) -> Binding<LoomColor> {
        Binding(
            get: { i < palette.count ? palette[i] : LoomColor(r: 0, g: 0, b: 0, a: 255) },
            set: { v in guard i < palette.count else { return }; palette[i] = v }
        )
    }

    private func duplicateSelectedColor() {
        guard let i = selectedIndex, i < palette.count else { return }
        palette.insert(palette[i], at: i + 1)
        selectedIndex = i + 1
    }

    private func removeColor(at i: Int) {
        guard i < palette.count else { return }
        palette.remove(at: i)
        if selectedIndex == i { selectedIndex = nil }
        else if let s = selectedIndex, s > i { selectedIndex = s - 1 }
    }

    private func saveColorPalette() {
        guard let base = palettesDir else { return }
        ensurePalettesDir(base)
        let panel = NSSavePanel()
        panel.title = "Save Color Palette"
        panel.nameFieldStringValue = "palette_colors.xml"
        panel.allowedContentTypes = [UTType.xml]
        panel.directoryURL = base
        let snap = palette
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? saveColorPaletteXML(snap, to: url)
        }
    }

    private func importColorPalette() {
        let panel = NSOpenPanel()
        panel.title = "Import Color Palette"
        panel.allowedContentTypes = [UTType.xml]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let base = palettesDir { panel.directoryURL = base }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let loaded = try? loadColorPaletteXML(from: url) {
                palette = loaded
                selectedIndex = nil
            }
        }
    }

    private func ensurePalettesDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - Size palette editor

struct SizePaletteEditor: View {
    @EnvironmentObject private var controller: AppController
    @Binding var palette: [Double]

    @State private var selectedIndex: Int? = nil

    private var palettesDir: URL? {
        controller.projectURL?.appendingPathComponent("palettes")
    }

    var body: some View {
        sizePaletteHeader
        sizePaletteRows
    }

    private var sizePaletteHeader: some View {
        HStack(spacing: 4) {
            Text("Palette")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dup") { duplicateSelectedSize() }
                .controlSize(.mini)
                .disabled(selectedIndex == nil)
            Button("Save…") { saveSizePalette() }
                .controlSize(.mini)
                .disabled(palette.isEmpty)
            Button("Import…") { importSizePalette() }
                .controlSize(.mini)
            Button {
                palette.append(1.0)
                selectedIndex = palette.count - 1
            } label: {
                Image(systemName: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var sizePaletteRows: some View {
        ForEach(palette.indices, id: \.self) { si in
            HStack(spacing: 4) {
                InspectorField("  \(si)") {
                    FloatEntryField(value: sizeItemBinding(si), width: 70, fractionDigits: 3)
                }
                .background(selectedIndex == si
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { selectedIndex = si }
                Button {
                    removeSize(at: si)
                } label: {
                    Image(systemName: "minus").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
            }
        }
    }

    private func sizeItemBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { i < palette.count ? palette[i] : 1.0 },
            set: { v in guard i < palette.count else { return }; palette[i] = v }
        )
    }

    private func duplicateSelectedSize() {
        guard let i = selectedIndex, i < palette.count else { return }
        palette.insert(palette[i], at: i + 1)
        selectedIndex = i + 1
    }

    private func removeSize(at i: Int) {
        guard i < palette.count else { return }
        palette.remove(at: i)
        if selectedIndex == i { selectedIndex = nil }
        else if let s = selectedIndex, s > i { selectedIndex = s - 1 }
    }

    private func saveSizePalette() {
        guard let base = palettesDir else { return }
        ensurePalettesDir(base)
        let panel = NSSavePanel()
        panel.title = "Save Size Palette"
        panel.nameFieldStringValue = "palette_sizes.xml"
        panel.allowedContentTypes = [UTType.xml]
        panel.directoryURL = base
        let snap = palette
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? saveSizePaletteXML(snap, to: url)
        }
    }

    private func importSizePalette() {
        let panel = NSOpenPanel()
        panel.title = "Import Size Palette"
        panel.allowedContentTypes = [UTType.xml]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let base = palettesDir { panel.directoryURL = base }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let loaded = try? loadSizePaletteXML(from: url) {
                palette = loaded
                selectedIndex = nil
            }
        }
    }

    private func ensurePalettesDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
