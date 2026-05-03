import Foundation
import LoomEngine

// Palette files live in <project>/palettes/.
// Color palette: <name>_colors.xml   Size palette: <name>_sizes.xml
// Format matches the Python ColorPaletteIO / SizePaletteIO round-trip.

// MARK: - Color palette

func saveColorPaletteXML(_ colors: [LoomColor], to url: URL) throws {
    let name = paletteNameFromURL(url, suffix: "_colors")
    let root = XMLElement(name: "ColorPalette")
    addAttr("name", name, to: root)
    for c in colors {
        let el = XMLElement(name: "PaletteColor")
        addAttr("r", "\(c.r)", to: el)
        addAttr("g", "\(c.g)", to: el)
        addAttr("b", "\(c.b)", to: el)
        addAttr("a", "\(c.a)", to: el)
        root.addChild(el)
    }
    try makeDoc(root: root).xmlData(options: .nodePrettyPrint).write(to: url)
}

func loadColorPaletteXML(from url: URL) throws -> [LoomColor] {
    let doc = try XMLDocument(contentsOf: url)
    guard let root = doc.rootElement() else { throw PaletteIOError.invalidFormat }
    return root.elements(forName: "PaletteColor").compactMap { el -> LoomColor? in
        guard let r = intAttr("r", el), let g = intAttr("g", el),
              let b = intAttr("b", el), let a = intAttr("a", el)
        else { return nil }
        return LoomColor(r: r, g: g, b: b, a: a)
    }
}

// MARK: - Size palette

func saveSizePaletteXML(_ sizes: [Double], to url: URL) throws {
    let name = paletteNameFromURL(url, suffix: "_sizes")
    let root = XMLElement(name: "SizePalette")
    addAttr("name", name, to: root)
    for s in sizes {
        let el = XMLElement(name: "PaletteEntry")
        el.stringValue = String(format: "%.6g", s)
        root.addChild(el)
    }
    try makeDoc(root: root).xmlData(options: .nodePrettyPrint).write(to: url)
}

func loadSizePaletteXML(from url: URL) throws -> [Double] {
    let doc = try XMLDocument(contentsOf: url)
    guard let root = doc.rootElement() else { throw PaletteIOError.invalidFormat }
    return root.elements(forName: "PaletteEntry").compactMap { Double($0.stringValue ?? "") }
}

// MARK: - Helpers

enum PaletteIOError: LocalizedError {
    case invalidFormat
    var errorDescription: String? { "Palette file has unrecognised format." }
}

private func makeDoc(root: XMLElement) -> XMLDocument {
    let doc = XMLDocument(rootElement: root)
    doc.version = "1.0"
    doc.characterEncoding = "UTF-8"
    return doc
}

private func addAttr(_ name: String, _ value: String, to el: XMLElement) {
    if let attr = XMLNode.attribute(withName: name, stringValue: value) as? XMLNode {
        el.addAttribute(attr)
    }
}

private func intAttr(_ name: String, _ el: XMLElement) -> Int? {
    el.attribute(forName: name)?.stringValue.flatMap(Int.init)
}

/// Strips the suffix + ".xml" to produce the palette display name.
private func paletteNameFromURL(_ url: URL, suffix: String) -> String {
    var s = url.deletingPathExtension().lastPathComponent
    if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
    return s.isEmpty ? "palette" : s
}
