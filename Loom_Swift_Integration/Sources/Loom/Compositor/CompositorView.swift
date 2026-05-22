import SwiftUI
import LoomEngine

/// Sheet UI for defining a custom subdivision algorithm.
struct CompositorView: View {

    @State private var algorithm: CustomSubdivisionAlgorithm
    @State private var expandedPointID: UUID?
    @State private var expandedChildID: UUID?
    @State private var previewLevel: Int = 1

    let onSave: (CustomSubdivisionAlgorithm) -> Void
    @Environment(\.dismiss) private var dismiss

    init(algorithm: CustomSubdivisionAlgorithm,
         onSave: @escaping (CustomSubdivisionAlgorithm) -> Void) {
        self._algorithm = State(initialValue: algorithm)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                leftPanel
                    .frame(minWidth: 340, maxWidth: 400)
                previewPanel
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Custom Algorithm")
                .font(.system(size: 13, weight: .semibold))
            TextField("Name", text: $algorithm.name)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 12))
                .frame(maxWidth: 160)
            Spacer()
            HStack(spacing: 6) {
                Text("Preview level:").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $previewLevel) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            Button("Cancel") { dismiss() }
            Button("Save") {
                onSave(algorithm)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pointLibrarySection
                Divider().padding(.vertical, 4)
                edgeChildrenSection
                Divider().padding(.vertical, 4)
                globalChildSection
            }
            .padding(10)
        }
    }

    // MARK: - Point library

    private var pointLibrarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Point Library") {
                Button { addPoint() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Add a new named point")
            }

            // Built-in points (read-only)
            ForEach(["V.start", "V.end", "C"], id: \.self) { name in
                builtinPointRow(name)
            }

            // User-defined points
            ForEach($algorithm.points) { $pt in
                pointRow(pt: $pt)
            }
        }
    }

    private func builtinPointRow(_ name: String) -> some View {
        HStack {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(builtinDesc(name))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func builtinDesc(_ name: String) -> String {
        switch name {
        case "V.start": return "edge start vertex"
        case "V.end":   return "edge end vertex"
        case "C":       return "polygon centroid"
        default: return ""
        }
    }

    private func pointRow(pt: Binding<NamedPoint>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Expand/collapse chevron
                Button {
                    expandedPointID = expandedPointID == pt.id ? nil : pt.id.wrappedValue
                } label: {
                    Image(systemName: expandedPointID == pt.id.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                TextField("name", text: pt.name)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 80)
                    .onSubmit { sanitiseName(&pt.name.wrappedValue) }

                Text("=").foregroundStyle(.secondary).font(.system(size: 11))

                Picker("", selection: pt.primitive.kind) {
                    ForEach(PointPrimitive.Kind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: 110)

                Spacer()

                Button { removePoint(id: pt.id.wrappedValue) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(expandedPointID == pt.id.wrappedValue ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if expandedPointID == pt.id.wrappedValue {
                pointParamEditor(pt: pt)
                    .padding(.leading, 26)
                    .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func pointParamEditor(pt: Binding<NamedPoint>) -> some View {
        let kind = pt.primitive.kind.wrappedValue
        VStack(alignment: .leading, spacing: 3) {
            if kind.hasT {
                paramRow("t", description: "fraction along edge") {
                    ResettableSlider(value: pt.primitive.t, range: 0...1, defaultValue: 0.5)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.3f", pt.primitive.t.wrappedValue))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 46)
                }
            }
            if kind.hasD {
                paramRow("d", description: "inward offset") {
                    FloatEntryField(value: pt.primitive.d, width: 60, fractionDigits: 3)
                }
            }
            if kind.hasAngle {
                paramRow("°", description: "angle (degrees)") {
                    FloatEntryField(value: pt.primitive.angle, width: 60, fractionDigits: 1)
                }
            }
            if kind.hasS {
                paramRow("s", description: "0=midpoint → 1=centroid") {
                    ResettableSlider(value: pt.primitive.s, range: 0...1, defaultValue: 0.5)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.3f", pt.primitive.s.wrappedValue))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 46)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func paramRow<Content: View>(
        _ label: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 18, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Edge children

    private var edgeChildrenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Edge Children (repeated per edge)") {
                Button { addEdgeChild() } label: {
                    Image(systemName: "plus").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Add a child polygon definition")
            }

            if algorithm.edgeChildren.isEmpty {
                Text("No children — add one with +")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }

            ForEach($algorithm.edgeChildren) { $child in
                childRow(child: $child)
            }
        }
    }

    private func childRow(child: Binding<ChildPolygonDef>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    expandedChildID = expandedChildID == child.id ? nil : child.id.wrappedValue
                } label: {
                    Image(systemName: expandedChildID == child.id.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).frame(width: 12)
                }
                .buttonStyle(.plain)

                TextField("name", text: child.name)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 100)

                Text("[\(child.pointNames.wrappedValue.joined(separator: ", "))]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button { removeEdgeChild(id: child.id.wrappedValue) } label: {
                    Image(systemName: "minus").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(expandedChildID == child.id.wrappedValue ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if expandedChildID == child.id.wrappedValue {
                childPointEditor(child: child)
                    .padding(.leading, 26)
                    .padding(.bottom, 4)
            }
        }
    }

    private func childPointEditor(child: Binding<ChildPolygonDef>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ordered point sequence (click to remove):")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Point chips
            FlowLayout(spacing: 4) {
                ForEach(Array(child.pointNames.wrappedValue.enumerated()), id: \.offset) { idx, name in
                    Button {
                        child.pointNames.wrappedValue.remove(at: idx)
                    } label: {
                        HStack(spacing: 3) {
                            Text(name)
                                .font(.system(size: 10, design: .monospaced))
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(name) from sequence")
                }
            }

            // Add point ref picker
            HStack(spacing: 4) {
                Text("Add:").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("", selection: .constant("")) {
                    Text("—").tag("")
                    ForEach(algorithm.allPointRefs, id: \.self) { ref in
                        Text(ref).tag(ref)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: 140)
                .onChange(of: "") { _, _ in }  // placeholder — real selection below

                // We use a separate picker with proper selection
                PointRefPicker(refs: algorithm.allPointRefs) { ref in
                    child.pointNames.wrappedValue.append(ref)
                }
            }
        }
    }

    // MARK: - Global child

    private var globalChildSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Global Child (one vertex per edge)") { EmptyView() }

            Text("Pick one point — the engine collects that point from every edge iteration to form a single enclosing polygon.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Toggle("Enable", isOn: Binding(
                    get: { algorithm.globalChildPointName != nil },
                    set: { on in
                        algorithm.globalChildPointName = on ? algorithm.points.first?.name : nil
                    }
                ))
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

                if algorithm.globalChildPointName != nil {
                    Picker("Point:", selection: Binding(
                        get: { algorithm.globalChildPointName ?? "" },
                        set: { algorithm.globalChildPointName = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(algorithm.points.map(\.name), id: \.self) { n in
                            Text(n).tag(n)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11))
                    .frame(maxWidth: 120)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Preview panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview — Level \(previewLevel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            CompositorPreviewCanvas(algorithm: algorithm, levels: previewLevel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        }
    }

    // MARK: - Section header helper

    private func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Mutations

    private func addPoint() {
        let base = "p\(algorithm.points.count + 1)"
        algorithm.points.append(NamedPoint(
            name: base,
            primitive: PointPrimitive(kind: .edgeFrac, t: 0.5)
        ))
    }

    private func removePoint(id: UUID) {
        algorithm.points.removeAll { $0.id == id }
        if expandedPointID == id { expandedPointID = nil }
    }

    private func addEdgeChild() {
        algorithm.edgeChildren.append(ChildPolygonDef(
            name: "Child \(algorithm.edgeChildren.count + 1)",
            pointNames: ["V.start", "V.end", "C"]
        ))
    }

    private func removeEdgeChild(id: UUID) {
        algorithm.edgeChildren.removeAll { $0.id == id }
        if expandedChildID == id { expandedChildID = nil }
    }

    private func sanitiseName(_ name: inout String) {
        name = name
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Point ref picker (avoids the Picker onChange hack)

private struct PointRefPicker: View {
    let refs: [String]
    let onSelect: (String) -> Void

    @State private var selected: String = ""

    var body: some View {
        Picker("", selection: $selected) {
            Text("+ add").tag("")
            ForEach(refs, id: \.self) { ref in
                Text(ref).tag(ref)
            }
        }
        .labelsHidden()
        .font(.system(size: 11))
        .frame(maxWidth: 130)
        .onChange(of: selected) { _, newVal in
            guard !newVal.isEmpty else { return }
            onSelect(newVal)
            selected = ""
        }
    }
}

// MARK: - Flow layout (wrapping HStack for chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Preview canvas

struct CompositorPreviewCanvas: View {

    let algorithm: CustomSubdivisionAlgorithm
    let levels: Int

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 10, size.height > 10 else { return }
            let polys = buildPolygons(size: size)

            // Draw each child with a faint fill + visible stroke
            let fillShading  = GraphicsContext.Shading.color(Color(red: 0.3, green: 0.55, blue: 0.8, opacity: 0.08))
            let strokeShading = GraphicsContext.Shading.color(Color(red: 0.5, green: 0.75, blue: 1.0, opacity: 0.85))

            for poly in polys {
                guard poly.points.count >= 4, poly.points.count % 4 == 0 else { continue }
                var path = Path()
                let n = poly.points.count / 4
                path.move(to: cvt(poly.points[0], size: size))
                for i in 0..<n {
                    let b = i * 4
                    path.addCurve(
                        to:       cvt(poly.points[b + 3], size: size),
                        control1: cvt(poly.points[b + 1], size: size),
                        control2: cvt(poly.points[b + 2], size: size)
                    )
                }
                path.closeSubpath()
                ctx.fill(path, with: fillShading)
                ctx.stroke(path, with: strokeShading, lineWidth: 1.0)
            }

            // Empty-state message
            if polys.isEmpty {
                var text = AttributedString("No output — add an Edge Child and define its point sequence")
                text.foregroundColor = .init(white: 0.45)
                text.font = .system(size: 11)
                ctx.draw(Text(text), at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
    }

    private func buildPolygons(size: CGSize) -> [Polygon2D] {
        let margin = 0.1
        let s = min(size.width, size.height) * (1 - 2 * margin)
        let cx = size.width / 2
        let cy = size.height / 2
        let h  = s / 2

        // Unit square in spline format (4 segments × 4 points)
        let tl = Vector2D(x: cx - h, y: cy - h)
        let tr = Vector2D(x: cx + h, y: cy - h)
        let br = Vector2D(x: cx + h, y: cy + h)
        let bl = Vector2D(x: cx - h, y: cy + h)
        let seg = { (a: Vector2D, b: Vector2D) -> [Vector2D] in
            let t = 1.0 / 3.0
            let cp1 = Vector2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let cp2 = Vector2D(x: a.x + (b.x - a.x) * (1 - t), y: a.y + (b.y - a.y) * (1 - t))
            return [a, cp1, cp2, b]
        }
        let squarePts = seg(tl, tr) + seg(tr, br) + seg(br, bl) + seg(bl, tl)
        let square = Polygon2D(points: squarePts, type: .spline)

        var params = SubdivisionParams()
        params.subdivisionType = .custom
        params.customAlgorithm = algorithm

        var rng = SystemRandomNumberGenerator()
        var polys = [square]
        for _ in 0..<levels {
            polys = polys.flatMap { p in
                SubdivisionEngine.subdivide(polygon: p, params: params, rng: &rng)
            }
        }
        return polys
    }

    private func cvt(_ v: Vector2D, size: CGSize) -> CGPoint {
        CGPoint(x: v.x, y: size.height - v.y)
    }
}
