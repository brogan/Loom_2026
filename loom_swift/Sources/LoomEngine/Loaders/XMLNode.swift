import Foundation

// MARK: - XMLNode

/// Lightweight DOM node built by `parseXML(data:)`.
///
/// Used internally by all Loom XML loaders.  Not part of the public API.
final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text: String = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    // MARK: - Navigation

    func child(named n: String) -> XMLNode? {
        children.first { $0.name == n }
    }

    func children(named n: String) -> [XMLNode] {
        children.filter { $0.name == n }
    }

    // MARK: - Attribute access (with defaults)

    func attr(_ key: String) -> String? { attributes[key] }

    func intAttr(_ key: String, default d: Int = 0) -> Int {
        guard let s = attributes[key] else { return d }
        return Int(s) ?? d
    }

    func doubleAttr(_ key: String, default d: Double = 0) -> Double {
        guard let s = attributes[key] else { return d }
        return Double(s) ?? d
    }

    func boolAttr(_ key: String, default d: Bool = false) -> Bool {
        guard let s = attributes[key] else { return d }
        switch s.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return d
        }
    }

    // MARK: - Child text/value access (with defaults)

    func childText(_ n: String, default d: String = "") -> String {
        child(named: n).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? d
    }

    func childInt(_ n: String, default d: Int = 0) -> Int {
        guard let s = child(named: n)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              let v = Int(s) else { return d }
        return v
    }

    func childDouble(_ n: String, default d: Double = 0) -> Double {
        guard let s = child(named: n)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              let v = Double(s) else { return d }
        return v
    }

    func childBool(_ n: String, default d: Bool = false) -> Bool {
        guard let s = child(named: n)?.text.trimmingCharacters(in: .whitespacesAndNewlines) else { return d }
        switch s.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return d
        }
    }

    /// Read an RGBA color from a child element whose `r`/`g`/`b`/`a` are attributes.
    func childColor(_ n: String, default d: LoomColor = .black) -> LoomColor {
        guard let node = child(named: n) else { return d }
        return LoomColor(
            r: node.intAttr("r", default: 0),
            g: node.intAttr("g", default: 0),
            b: node.intAttr("b", default: 0),
            a: node.intAttr("a", default: 255)
        )
    }

    /// Read a `Vector2D` from a child element with `x`/`y` attributes.
    func childVec2(_ n: String, default d: Vector2D = .zero) -> Vector2D {
        guard let node = child(named: n) else { return d }
        return Vector2D(
            x: node.doubleAttr("x", default: d.x),
            y: node.doubleAttr("y", default: d.y)
        )
    }
}

// MARK: - Parser

enum XMLParseError: Error {
    case invalidData
    case noRootElement
}

/// Parse XML data into a simple `XMLNode` tree.
func parseXML(data: Data) throws -> XMLNode {
    let delegate = XMLTreeBuilder()
    let parser   = XMLParser(data: data)
    parser.delegate            = delegate
    parser.shouldResolveExternalEntities = false
    parser.parse()
    if let err = delegate.error { throw err }
    guard let root = delegate.root else { throw XMLParseError.noRootElement }
    return root
}

// MARK: - Private delegate

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    var error: Error?
    private var stack: [XMLNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}
