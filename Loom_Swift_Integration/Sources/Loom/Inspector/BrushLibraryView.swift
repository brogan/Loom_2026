import AppKit
import SwiftUI

/// Inline inspector widget showing a thumbnail list of brushes or stamps assigned
/// to one renderer.  Replaces the plain `brushNames`/`stampNames` TextFields.
///
/// - dir: "brushes" or "stamps" — subfolder of the project directory
/// - names: filenames currently assigned to this renderer
/// - enabled: per-name enable flags (parallel array; missing entries = true)
struct BrushLibraryView: View {
    @EnvironmentObject private var controller: AppController

    let dir: String
    @Binding var names: [String]
    @Binding var enabled: [Bool]

    @State private var selectedIndex: Int? = nil
    @State private var thumbnails: [String: NSImage] = [:]

    private var assetDir: URL? {
        controller.projectURL?.appendingPathComponent(dir)
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryList
            Divider()
            libraryToolbar
        }
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onAppear { refreshThumbnails() }
        .onChange(of: names) { _, _ in refreshThumbnails() }
    }

    // MARK: - List

    private var libraryList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(names.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        thumbnail(for: names[i])
                        Toggle("", isOn: enabledBinding(i))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .scaleEffect(0.85)
                        Text(names[i])
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selectedIndex == i
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedIndex = i }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 52, maxHeight: 144)
    }

    @ViewBuilder
    private func thumbnail(for name: String) -> some View {
        if let img = thumbnails[name] {
            Image(nsImage: img)
                .resizable()
                .interpolation(.none)
                .frame(width: 24, height: 24)
                .background(Color.black)
                .cornerRadius(2)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.18))
                .frame(width: 24, height: 24)
        }
    }

    // MARK: - Toolbar

    private var libraryToolbar: some View {
        HStack(spacing: 4) {
            Button("↺") { refreshThumbnails() }
                .help("Reload thumbnails from disk")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
                .frame(width: 20)
            Divider().frame(height: 14)
            Button("Import…") { importAsset() }
                .controlSize(.mini)
            Button("Create…") { createAsset() }
                .controlSize(.mini)
            Button("Edit…") { editAsset() }
                .controlSize(.mini)
                .disabled(selectedIndex == nil)
            Spacer()
            Button {
                removeSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedIndex == nil ? Color.secondary : Color.primary)
            .disabled(selectedIndex == nil)
            .help("Remove from list (does not delete the file)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Enabled binding

    private func enabledBinding(_ i: Int) -> Binding<Bool> {
        Binding(
            get: { i < enabled.count ? enabled[i] : true },
            set: { v in
                var e = enabled
                while e.count <= i { e.append(true) }
                e[i] = v
                enabled = e
            }
        )
    }

    // MARK: - Thumbnail loading

    private func refreshThumbnails() {
        guard let base = assetDir else { return }
        for name in names {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let img = NSImage(contentsOf: url)
            else { continue }
            thumbnails[name] = scaledThumbnail(img)
        }
    }

    private func scaledThumbnail(_ img: NSImage) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        return thumb
    }

    // MARK: - Actions

    private func importAsset() {
        guard let base = assetDir else { return }
        ensureDir(base)
        let panel = NSOpenPanel()
        panel.title = "Import \(dir.capitalized)"
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            var newNames = names
            for url in panel.urls {
                let dest = base.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
                let name = url.lastPathComponent
                if !newNames.contains(name) { newNames.append(name) }
            }
            names = newNames
            refreshThumbnails()
        }
    }

    private func createAsset() {
        guard let base = assetDir else { return }
        ensureDir(base)
        if dir == "stamps" {
            controller.openStampEditor(stampsDir: base) { savedName in
                if !names.contains(savedName) { names.append(savedName) }
                refreshThumbnails()
            }
        } else {
            controller.openBrushEditor(brushesDir: base) { savedName in
                if !names.contains(savedName) { names.append(savedName) }
                refreshThumbnails()
            }
        }
    }

    private func editAsset() {
        guard let i = selectedIndex, i < names.count, let base = assetDir else { return }
        let file = base.appendingPathComponent(names[i])
        if dir == "stamps" {
            controller.openStampEditor(file: file, stampsDir: base) { _ in
                refreshThumbnails()
            }
        } else {
            controller.openBrushEditor(file: file, brushesDir: base) { _ in
                refreshThumbnails()
            }
        }
    }

    private func removeSelected() {
        guard let i = selectedIndex, i < names.count else { return }
        let removedName = names[i]
        names.remove(at: i)
        var e = enabled
        if i < e.count { e.remove(at: i) }
        enabled = e
        thumbnails.removeValue(forKey: removedName)
        selectedIndex = nil
    }

    private func ensureDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
