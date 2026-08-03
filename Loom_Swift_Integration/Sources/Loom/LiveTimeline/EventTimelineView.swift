import AVFoundation
import SwiftUI
import LoomEngine

private enum EventSegmentEdge { case start, end }

/// One row in the flattened lane list drawn by `EventTimelineView` — built
/// fresh from `EventTimelineModel` on every body evaluation (see
/// `EventSegmentDerivation`'s doc comment on why that's cheap enough here).
/// `.spans`/`.points` are generic over `EventSpan`/`EventPoint` so drawing
/// and hit-testing don't need to switch on Visibility/Renderer/Transform/
/// Enabled separately — move/resize/delete mean the same thing for all of them.
private struct EventRow: Identifiable {
    enum Kind {
        case audio(AudioReference)
        case global([GlobalMarker])
        case instanceHeader
        case spans(color: Color, [any EventSpan])
        case points(color: Color, [any EventPoint])
        case automation(AutomationCurve)
    }
    let id: String
    let label: String
    let kind: Kind
}

/// The direct-manipulation timeline over a recorded Live session's event
/// log — a separate, self-contained view from the authored sprite
/// `Timeline/TimelinePanel.swift`, over a much simpler data source (a plain
/// `[RecordedEvent]` array, no `ProjectConfig`/undo). Drag to move a
/// segment's body or resize its edges, drag a point to retime it, Delete
/// key / right-click to remove the selected item — all of it just shifts or
/// removes the underlying recorded events (see `EventTimelineEditing`),
/// since a segment here is a derived view, not an authored object.
struct EventTimelineView: View {
    let projectURL: URL
    /// Project frame rate — needed only to convert the audio waveform's
    /// real-world duration into frame-widths for drawing; event frame
    /// numbers themselves need no fps conversion, they're already frames.
    let fps: Double
    @Binding var recordedEvents: [RecordedEvent]

    @State private var zoom: CGFloat = 4
    @State private var waveform: [Float] = []
    @State private var waveformDuration: Double = 0
    @State private var loadedWaveformFilename: String? = nil
    @State private var audioDragAnchor: (eventID: UUID, baseOffset: Int)? = nil

    // MARK: - Drag/selection state
    //
    // `dragAnchor` carries only identity (which event(s) to retime), never
    // frame values — every preview and commit reads the *current* frame off
    // the freshly-derived model and adds `dragDeltaFrames`, computed fresh
    // from the drag's cumulative `translation` every tick, never
    // incrementally from an evolving preview (that double-applies
    // `DragGesture.Value.translation` — a real bug hit twice building the
    // driver-segment timeline this same session).
    @State private var isDragInitialized = false
    @State private var dragAnchor: (itemID: UUID, primaryID: UUID, secondaryID: UUID?)? = nil
    @State private var dragDeltaFrames: Int = 0
    @State private var selectedItemID: UUID? = nil
    @State private var selectedDeleteIDs: Set<UUID> = []
    @State private var hoveredItemID: UUID? = nil
    @State private var hoveredDeleteIDs: Set<UUID> = []

    private static let rowHeight: CGFloat = 24
    private static let labelWidth: CGFloat = 190
    private static let edgeTolerance: CGFloat = 6

    private var model: EventTimelineModel {
        EventSegmentDerivation.derive(from: recordedEvents)
    }

    private var maxFrame: Int {
        max(recordedEvents.map(\.event.t).max() ?? 0, 1)
    }

    private var rows: [EventRow] {
        var rows: [EventRow] = []
        if let audioReference = model.audioReference {
            rows.append(EventRow(id: "audio", label: "Audio", kind: .audio(audioReference)))
        }
        if !model.globalMarkers.isEmpty {
            rows.append(EventRow(id: "global", label: "Global", kind: .global(model.globalMarkers)))
        }
        for lane in model.instanceLanes {
            rows.append(EventRow(id: "\(lane.id)|header", label: lane.spriteLabel, kind: .instanceHeader))
            if !lane.visibilitySegments.isEmpty {
                rows.append(EventRow(id: "\(lane.id)|vis", label: "  Visible", kind: .spans(color: .teal, lane.visibilitySegments)))
            }
            if !lane.rendererSegments.isEmpty {
                rows.append(EventRow(id: "\(lane.id)|rend", label: "  Renderer", kind: .spans(color: .orange, lane.rendererSegments)))
            }
            if !lane.transformSegments.isEmpty {
                rows.append(EventRow(id: "\(lane.id)|xform", label: "  Transform", kind: .spans(color: .purple, lane.transformSegments)))
            }
            for (target, segments) in lane.enabledSegments.sorted(by: { $0.key.field < $1.key.field }) {
                rows.append(EventRow(id: "\(lane.id)|en|\(target.field)|\(target.entryName)", label: "  \(target.field) enabled", kind: .spans(color: .pink, segments)))
            }
            if !lane.poseMarkers.isEmpty {
                rows.append(EventRow(id: "\(lane.id)|pose", label: "  Pose", kind: .points(color: .mint, lane.poseMarkers)))
            }
            for curve in lane.automationCurves {
                rows.append(EventRow(id: curve.id, label: "  \(curve.target.field) \(curve.quantity)", kind: .automation(curve)))
            }
        }
        return rows
    }

    private var contentWidth: CGFloat { CGFloat(maxFrame + 30) * zoom }
    private var contentHeight: CGFloat { CGFloat(rows.count) * Self.rowHeight }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    labelColumn
                    ScrollView(.horizontal) {
                        canvas
                            .frame(width: max(contentWidth, 1), height: max(contentHeight, 1))
                    }
                }
            }
        }
        .task(id: model.audioReference?.filename) {
            await loadWaveformIfNeeded()
        }
        .background(
            Button("Delete") { deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedItemID == nil)
                .opacity(0)
        )
    }

    private var canvas: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onDragChanged(v) }
                    .onEnded { v in onDragEnded(v) }
            )
            .onContinuousHover { phase in
                if case .active(let loc) = phase, let hit = hitTest(at: loc) {
                    hoveredItemID = hit.itemID
                    hoveredDeleteIDs = hit.deleteIDs
                } else {
                    hoveredItemID = nil
                    hoveredDeleteIDs = []
                }
            }
            .contextMenu {
                if let hoveredItemID {
                    Button("Delete") {
                        EventTimelineEditing.delete(hoveredDeleteIDs, in: &recordedEvents)
                        if selectedItemID == hoveredItemID { selectedItemID = nil }
                    }
                }
            }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Zoom").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: $zoom, in: 1...20).frame(width: 140)
            Spacer()
            if selectedItemID != nil {
                Button("Delete Selected") { deleteSelection() }
                    .font(.system(size: 10))
            }
            Text("\(recordedEvents.count) events").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                Text(row.label)
                    .font(.system(size: 10, weight: isHeaderRow(row) ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(width: Self.labelWidth, height: Self.rowHeight, alignment: .leading)
                    .padding(.leading, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    private func isHeaderRow(_ row: EventRow) -> Bool {
        if case .instanceHeader = row.kind { return true }
        if case .global = row.kind { return true }
        return false
    }

    /// Loads the waveform for the session's recorded audio reference, if
    /// any — reuses `AudioController.buildWaveform` rather than duplicating
    /// waveform computation. `.task(id:)` above cancels/restarts this
    /// automatically if the referenced filename changes (e.g. undone via
    /// editing) and skips re-running for the same filename already loaded.
    private func loadWaveformIfNeeded() async {
        guard let filename = model.audioReference?.filename, filename != loadedWaveformFilename else { return }
        let url = projectURL.appendingPathComponent("sessions/audio").appendingPathComponent(filename)
        async let waveformTask = AudioController.buildWaveform(url: url)
        async let durationTask: Double = {
            (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
        }()
        let (data, duration) = await (waveformTask, durationTask)
        guard !Task.isCancelled else { return }
        waveform = data
        waveformDuration = duration
        loadedWaveformFilename = filename
    }

    private func deleteSelection() {
        guard selectedItemID != nil else { return }
        EventTimelineEditing.delete(selectedDeleteIDs, in: &recordedEvents)
        selectedItemID = nil
        selectedDeleteIDs = []
    }

    // MARK: - Hit-testing

    private struct Hit {
        let itemID: UUID
        let deleteIDs: Set<UUID>
        let spanEdge: (span: any EventSpan, edge: EventSegmentEdge?)?
        let point: (any EventPoint)?
    }

    private func rowIndex(at y: CGFloat) -> Int? {
        let all = rows
        let idx = Int(y / Self.rowHeight)
        return (idx >= 0 && idx < all.count) ? idx : nil
    }

    private func hitTest(at point: CGPoint) -> Hit? {
        guard let idx = rowIndex(at: point.y) else { return nil }
        switch rows[idx].kind {
        case .spans(_, let spans):
            for span in spans {
                let startX = CGFloat(span.startFrame) * zoom
                let endX = CGFloat(span.endFrame ?? maxFrame + 20) * zoom
                guard point.x >= startX - Self.edgeTolerance, point.x <= endX + Self.edgeTolerance else { continue }
                if abs(point.x - startX) <= Self.edgeTolerance {
                    var ids: Set<UUID> = [span.startEventID]
                    if let e = span.endEventID { ids.insert(e) }
                    return Hit(itemID: span.id, deleteIDs: ids, spanEdge: (span, .start), point: nil)
                }
                if span.endFrame != nil, abs(point.x - endX) <= Self.edgeTolerance {
                    var ids: Set<UUID> = [span.startEventID]
                    if let e = span.endEventID { ids.insert(e) }
                    return Hit(itemID: span.id, deleteIDs: ids, spanEdge: (span, .end), point: nil)
                }
                if point.x > startX, point.x < endX {
                    var ids: Set<UUID> = [span.startEventID]
                    if let e = span.endEventID { ids.insert(e) }
                    return Hit(itemID: span.id, deleteIDs: ids, spanEdge: (span, nil), point: nil)
                }
            }
            return nil
        case .points(_, let points):
            for p in points {
                let x = CGFloat(p.frame) * zoom
                guard abs(point.x - x) <= Self.edgeTolerance else { continue }
                var ids: Set<UUID> = [p.id]
                if let paired = p.pairedID { ids.insert(paired) }
                return Hit(itemID: p.id, deleteIDs: ids, spanEdge: nil, point: p)
            }
            return nil
        case .automation(let curve):
            for p in curve.points {
                let x = CGFloat(p.frame) * zoom
                guard abs(point.x - x) <= Self.edgeTolerance else { continue }
                var ids: Set<UUID> = [p.id]
                if let paired = p.pairedID { ids.insert(paired) }
                return Hit(itemID: p.id, deleteIDs: ids, spanEdge: nil, point: p)
            }
            return nil
        case .audio, .global, .instanceHeader:
            return nil // handled separately in onDragChanged, before this generic hit-test runs
        }
    }

    // MARK: - Gesture

    private func onDragChanged(_ v: DragGesture.Value) {
        if !isDragInitialized {
            isDragInitialized = true
            dragDeltaFrames = 0
            dragAnchor = nil
            audioDragAnchor = nil
            // Audio row: drag anywhere in its Y-range (not bounded to the
            // waveform's own X-extent) to offset it — mirrors
            // `TimelinePanel`'s `isAudioLaneArea`/`.audioOffset` behavior,
            // where the whole lane is draggable, not just the visible clip.
            if let idx = rowIndex(at: v.startLocation.y), case .audio(let ref) = rows[idx].kind {
                selectedItemID = ref.eventID
                selectedDeleteIDs = [ref.eventID]
                audioDragAnchor = (ref.eventID, ref.offsetFrames)
            } else if let hit = hitTest(at: v.startLocation) {
                selectedItemID = hit.itemID
                selectedDeleteIDs = hit.deleteIDs
                if let (span, edge) = hit.spanEdge {
                    switch edge {
                    case .start:
                        dragAnchor = (span.id, span.startEventID, nil)
                    case .end:
                        if let endID = span.endEventID { dragAnchor = (span.id, endID, nil) }
                    case nil:
                        dragAnchor = (span.id, span.startEventID, span.endEventID)
                    }
                } else if let p = hit.point {
                    dragAnchor = (p.id, p.id, p.pairedID)
                }
            } else {
                selectedItemID = nil
                selectedDeleteIDs = []
            }
        }
        guard dragAnchor != nil || audioDragAnchor != nil else { return }
        dragDeltaFrames = Int((v.translation.width / zoom).rounded())
    }

    private func onDragEnded(_ v: DragGesture.Value) {
        defer {
            isDragInitialized = false
            dragAnchor = nil
            audioDragAnchor = nil
            dragDeltaFrames = 0
        }
        let isTap = abs(v.translation.width) < 3 && abs(v.translation.height) < 3
        guard !isTap, dragDeltaFrames != 0 else { return }
        if let anchor = dragAnchor {
            EventTimelineEditing.retimePair(anchor.primaryID, anchor.secondaryID, byDelta: dragDeltaFrames, in: &recordedEvents)
        } else if let audioAnchor = audioDragAnchor {
            EventTimelineEditing.updateAudioOffset(audioAnchor.eventID, to: audioAnchor.baseOffset + dragDeltaFrames, in: &recordedEvents)
        }
    }

    // MARK: - Preview (live values while dragging)

    private func previewFrames(for span: any EventSpan) -> (start: Int, end: Int?) {
        guard let anchor = dragAnchor, anchor.itemID == span.id else { return (span.startFrame, span.endFrame) }
        if anchor.secondaryID != nil {
            return (span.startFrame + dragDeltaFrames, span.endFrame.map { $0 + dragDeltaFrames })
        } else if anchor.primaryID == span.startEventID {
            return (span.startFrame + dragDeltaFrames, span.endFrame)
        } else {
            return (span.startFrame, span.endFrame.map { $0 + dragDeltaFrames })
        }
    }

    private func previewFrame(for point: any EventPoint) -> Int {
        guard let anchor = dragAnchor, anchor.itemID == point.id else { return point.frame }
        return point.frame + dragDeltaFrames
    }

    // MARK: - Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        drawGrid(&ctx, size: size)
        for (i, row) in rows.enumerated() {
            let rowTop = CGFloat(i) * Self.rowHeight
            let midY = rowTop + Self.rowHeight / 2
            switch row.kind {
            case .audio(let ref):
                drawAudioRow(&ctx, ref, top: rowTop, height: Self.rowHeight)
            case .global(let markers):
                for m in markers { drawGlobalMarker(&ctx, m, y: midY) }
            case .instanceHeader:
                break
            case .spans(let color, let spans):
                for s in spans {
                    let (start, end) = previewFrames(for: s)
                    let isSelected = selectedItemID == s.id
                    drawSpan(&ctx, start: start, end: end, top: rowTop, color: color, label: s.displayLabel, isSelected: isSelected)
                }
            case .points(let color, let points):
                for p in points {
                    let isSelected = selectedItemID == p.id
                    drawDiamond(&ctx, x: CGFloat(previewFrame(for: p)) * zoom, y: midY, color: color, isSelected: isSelected)
                }
            case .automation(let curve):
                drawCurve(&ctx, curve, midY: midY)
            }
        }
    }

    private func drawGrid(_ ctx: inout GraphicsContext, size: CGSize) {
        let step = 30
        var f = 0
        while CGFloat(f) * zoom < size.width {
            let x = CGFloat(f) * zoom
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: .color(Color.secondary.opacity(0.12)), lineWidth: 1)
            f += step
        }
    }

    private func drawSpan(_ ctx: inout GraphicsContext, start: Int, end: Int?, top: CGFloat, color: Color, label: String?, isSelected: Bool) {
        let startX = CGFloat(start) * zoom
        let endX = CGFloat(end ?? maxFrame + 20) * zoom
        guard endX > startX else { return }
        let rect = CGRect(x: startX, y: top + 2, width: endX - startX, height: Self.rowHeight - 4)
        let path = Path(roundedRect: rect, cornerRadius: 3)
        ctx.fill(path, with: .color(color.opacity(isSelected ? 0.55 : 0.35)))
        ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: isSelected ? 2 : 1)
        if let label, !label.isEmpty, rect.width > 24 {
            ctx.draw(
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white),
                at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading
            )
        }
    }

    private func drawDiamond(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, color: Color, isSelected: Bool = false) {
        let size: CGFloat = isSelected ? 5.5 : 4
        let path = Path { p in
            p.move(to: CGPoint(x: x, y: y - size))
            p.addLine(to: CGPoint(x: x + size, y: y))
            p.addLine(to: CGPoint(x: x, y: y + size))
            p.addLine(to: CGPoint(x: x - size, y: y))
            p.closeSubpath()
        }
        ctx.fill(path, with: .color(color))
        if isSelected {
            ctx.stroke(path, with: .color(.white), lineWidth: 1.5)
        }
    }

    private func drawCurve(_ ctx: inout GraphicsContext, _ curve: AutomationCurve, midY: CGFloat) {
        let points = curve.points.sorted { $0.frame < $1.frame }
        guard !points.isEmpty else { return }
        var linePath = Path()
        for (i, pt) in points.enumerated() {
            let x = CGFloat(previewFrame(for: pt)) * zoom
            if i == 0 { linePath.move(to: CGPoint(x: x, y: midY)) } else { linePath.addLine(to: CGPoint(x: x, y: midY)) }
        }
        ctx.stroke(linePath, with: .color(Color.yellow.opacity(0.7)), lineWidth: 1)
        for pt in points {
            let isSelected = selectedItemID == pt.id
            drawDiamond(&ctx, x: CGFloat(previewFrame(for: pt)) * zoom, y: midY, color: .yellow, isSelected: isSelected)
        }
    }

    /// Renders the recorded audio's waveform — same fill+outline shape as
    /// `TimelinePanel.drawAudioLane`, positioned at the (possibly currently-
    /// dragged) offset. Draws an empty placeholder band while the waveform
    /// is still loading, so the row's Y-range is always there to grab.
    private func drawAudioRow(_ ctx: inout GraphicsContext, _ ref: AudioReference, top: CGFloat, height: CGFloat) {
        let isDragging = audioDragAnchor?.eventID == ref.eventID
        let offsetFrames = isDragging ? (audioDragAnchor!.baseOffset + dragDeltaFrames) : ref.offsetFrames
        let midY = top + height / 2

        guard !waveform.isEmpty, waveformDuration > 0, fps > 0 else {
            ctx.fill(Path(CGRect(x: 0, y: top + 2, width: 40, height: height - 4)),
                      with: .color(Color.secondary.opacity(0.15)))
            return
        }

        let durationFrames = waveformDuration * fps
        let bucketCount = waveform.count
        let framesPerBucket = durationFrames / Double(bucketCount)
        guard framesPerBucket > 0 else { return }

        func x(for bucket: Int) -> CGFloat {
            CGFloat(Double(offsetFrames) + Double(bucket) * framesPerBucket) * zoom
        }

        let halfH = (height - 4) * 0.42
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: x(for: 0), y: midY))
        for b in 0..<bucketCount {
            fillPath.addLine(to: CGPoint(x: x(for: b), y: midY - CGFloat(waveform[b]) * halfH))
        }
        fillPath.addLine(to: CGPoint(x: x(for: bucketCount - 1), y: midY))
        for b in (0..<bucketCount).reversed() {
            fillPath.addLine(to: CGPoint(x: x(for: b), y: midY + CGFloat(waveform[b]) * halfH))
        }
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(Color.accentColor.opacity(isDragging ? 0.4 : 0.28)))

        var outline = Path()
        outline.move(to: CGPoint(x: x(for: 0), y: midY - CGFloat(waveform[0]) * halfH))
        for b in 1..<bucketCount {
            outline.addLine(to: CGPoint(x: x(for: b), y: midY - CGFloat(waveform[b]) * halfH))
        }
        ctx.stroke(outline, with: .color(Color.accentColor.opacity(isDragging ? 0.85 : 0.55)), lineWidth: 1)
    }

    private func drawGlobalMarker(_ ctx: inout GraphicsContext, _ marker: GlobalMarker, y: CGFloat) {
        let x = CGFloat(marker.frame) * zoom
        ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: y - 8)); p.addLine(to: CGPoint(x: x, y: y + 8)) },
                   with: .color(Color.red.opacity(0.7)), lineWidth: 1.5)
        let label: String
        switch marker.kind {
        case .bpmSet(let bpm, let beatsPerBar): label = "\(Int(bpm)) BPM / \(beatsPerBar)"
        case .tapSync: label = "Tap"
        }
        ctx.draw(Text(label).font(.system(size: 8)).foregroundStyle(.red), at: CGPoint(x: x + 4, y: y), anchor: .leading)
    }
}
