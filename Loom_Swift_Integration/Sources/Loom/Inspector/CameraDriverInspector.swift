import SwiftUI
import LoomEngine

/// Dedicated inspector for the camera, shown when the "Camera" row is
/// selected in the Sprites tab's list. Consolidates what used to be split
/// across GlobalInspector's minimal Camera section (Enabled/Perspective)
/// and the timeline-only keyframe editing of tracking/pan/zoom/rotation —
/// those four fields are already `VectorDriver`/`DoubleDriver` in
/// `CameraConfig`, so they get the same procedural (oscillator/jitter/noise)
/// and keyframe editing sprites already have, via the shared
/// `VectorDriverEditor`/`DoubleDriverEditor` components.
///
/// Also hosts Segments: named, time-bounded overrides of the four drivers
/// (`CameraConfig.segments`). With no segment selected, this shows the base
/// drivers exactly as before segments existed — segments are an additional,
/// optional layer, not a replacement for that default entry point.
struct CameraDriverInspector: View {
    @EnvironmentObject private var controller: AppController

    @State private var trackingCollapsed = true
    @State private var panCollapsed      = true
    @State private var zoomCollapsed     = true
    @State private var rotationCollapsed = true

    @State private var segTrackingCollapsed = true
    @State private var segPanCollapsed      = true
    @State private var segZoomCollapsed     = true
    @State private var segRotationCollapsed = true

    @State private var renamingSegmentID: UUID?  = nil
    @State private var renameText:        String = ""

    private var selectedLane: CameraLane? { controller.selectedCameraKF?.lane }

    private var segments: [CameraSegment] {
        controller.projectConfig?.globalConfig.camera.segments ?? []
    }

    private var selectedSegmentIndex: Int? {
        guard let id = controller.selectedCameraSegmentID else { return nil }
        return segments.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection("Camera") {
                InspectorField("Enabled") {
                    Toggle("", isOn: bind(\.camera.enabled)).labelsHidden()
                }
                .loomHelp("Activates perspective projection. When off, all sprites are rendered in flat 2D regardless of their Depth value.")
                InspectorField("Perspective") {
                    FloatEntryField(value: bind(\.camera.perspectiveStrength), width: 65, fractionDigits: 4)
                    Text("0=flat").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Strength of the perspective effect. 0 = flat orthographic; larger values increase depth distortion for sprites away from the focal plane.")
            }

            segmentsSection

            if let idx = selectedSegmentIndex {
                selectedSegmentDetail(idx)
            } else {
                baseDriversSection
            }
        }
    }

    // MARK: - Base drivers

    @ViewBuilder
    private var baseDriversSection: some View {
        VectorDriverEditor(label: "Tracking", driver: bind(\.camera.tracking), isCollapsed: $trackingCollapsed,
                           isHighlighted: selectedLane == .tracking)
        VectorDriverEditor(label: "Pan", driver: bind(\.camera.pan), isCollapsed: $panCollapsed,
                           isHighlighted: selectedLane == .pan)
        DoubleDriverEditor(label: "Zoom", driver: bind(\.camera.zoom), isCollapsed: $zoomCollapsed,
                           isHighlighted: selectedLane == .zoom)
        DoubleDriverEditor(label: "Rotation", driver: bind(\.camera.rotation), isCollapsed: $rotationCollapsed,
                           isHighlighted: selectedLane == .rotation)
    }

    // MARK: - Segments

    @ViewBuilder
    private var segmentsSection: some View {
        InspectorSection("Segments") {
            if segments.isEmpty {
                Text("No segments — the drivers below apply to the whole timeline. Add a segment to override them for a specific frame range.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(segments) { segment in
                    segmentRow(segment)
                    Divider().padding(.leading, 12)
                }
            }
            Button {
                addSegment()
            } label: {
                Label("Add Segment", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func segmentRow(_ segment: CameraSegment) -> some View {
        let isSelected = controller.selectedCameraSegmentID == segment.id
        // A real foreground Button wrapping the whole row, not a background
        // one — a background Button with Color.clear as its label was
        // confirmed (via logging on the sprite-segment equivalent of this
        // row) to not reliably receive clicks on macOS/SwiftUI. Nested
        // Buttons/TextFields inside a Button's label still route clicks to
        // the more specific inner control on macOS.
        return Button {
            controller.selectedCameraSegmentID = segment.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if renamingSegmentID == segment.id {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { commitRename(segment.id) }
                    } else {
                        Text(segment.name.isEmpty ? "Segment" : segment.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                renameText        = segment.name
                                renamingSegmentID = segment.id
                            }
                    }
                    Spacer()
                    Button { duplicateSegment(segment) } label: {
                        Image(systemName: "plus.square.on.square").font(.system(size: 10)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Duplicate segment"))
                    Button { deleteSegment(segment) } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Delete segment"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .modifier(LoomHoverHelp("Click to edit this segment's own drivers"))
                }
                HStack(spacing: 4) {
                    Text("Start").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: startFrameBinding(for: segment.id), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                    Text("End").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: endFrameBinding(for: segment.id), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedSegmentDetail(_ idx: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                controller.selectedCameraSegmentID = nil
            } label: {
                Label("Camera", systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Spacer()
            Text(segments[idx].name.isEmpty ? "Segment" : segments[idx].name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        Divider()

        VectorDriverEditor(label: "Tracking", driver: bindSegment(idx, \.tracking), isCollapsed: $segTrackingCollapsed)
        VectorDriverEditor(label: "Pan", driver: bindSegment(idx, \.pan), isCollapsed: $segPanCollapsed)
        DoubleDriverEditor(label: "Zoom", driver: bindSegment(idx, \.zoom), isCollapsed: $segZoomCollapsed)
        DoubleDriverEditor(label: "Rotation", driver: bindSegment(idx, \.rotation), isCollapsed: $segRotationCollapsed)
    }

    // MARK: - Segment actions

    private func addSegment() {
        let frame = controller.currentTimelineFrame
        let defaultLength = 120
        let newSegment = CameraSegment(
            name: "Segment \(segments.count + 1)",
            startFrame: frame,
            endFrame: frame + defaultLength
        )
        controller.updateProjectConfig { cfg in
            cfg.globalConfig.camera.segments.append(newSegment)
        }
        controller.selectedCameraSegmentID = newSegment.id
    }

    private func duplicateSegment(_ segment: CameraSegment) {
        var copy = segment
        copy.id = UUID()
        let length = max(1, segment.endFrame - segment.startFrame)
        copy.startFrame = segment.endFrame
        copy.endFrame   = segment.endFrame + length
        copy.name       = segment.name.isEmpty ? "Segment" : "\(segment.name) copy"
        controller.updateProjectConfig { cfg in
            cfg.globalConfig.camera.segments.append(copy)
        }
        controller.selectedCameraSegmentID = copy.id
    }

    private func deleteSegment(_ segment: CameraSegment) {
        controller.updateProjectConfig { cfg in
            cfg.globalConfig.camera.segments.removeAll { $0.id == segment.id }
        }
        if controller.selectedCameraSegmentID == segment.id {
            controller.selectedCameraSegmentID = nil
        }
    }

    private func commitRename(_ id: UUID) {
        controller.updateProjectConfig { cfg in
            guard let idx = cfg.globalConfig.camera.segments.firstIndex(where: { $0.id == id }) else { return }
            cfg.globalConfig.camera.segments[idx].name = renameText
        }
        renamingSegmentID = nil
    }

    // MARK: - Binding helpers

    private func bind<T>(_ kp: WritableKeyPath<GlobalConfig, T>) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig[keyPath: kp] ?? GlobalConfig.default[keyPath: kp] },
            set: { v in ctl.updateProjectConfig { $0.globalConfig[keyPath: kp] = v } }
        )
    }

    private func bindSegment<T>(_ idx: Int, _ kp: WritableKeyPath<CameraSegment, T>) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                let segs = ctl.projectConfig?.globalConfig.camera.segments ?? []
                guard idx < segs.count else { return CameraSegment(startFrame: 0, endFrame: 0)[keyPath: kp] }
                return segs[idx][keyPath: kp]
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard idx < cfg.globalConfig.camera.segments.count else { return }
                    cfg.globalConfig.camera.segments[idx][keyPath: kp] = v
                }
            }
        )
    }

    private func startFrameBinding(for id: UUID) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.segments.first { $0.id == id }?.startFrame ?? 0 },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard let idx = cfg.globalConfig.camera.segments.firstIndex(where: { $0.id == id }) else { return }
                    cfg.globalConfig.camera.segments[idx].startFrame = max(0, v)
                }
            }
        )
    }

    private func endFrameBinding(for id: UUID) -> Binding<Int> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig.camera.segments.first { $0.id == id }?.endFrame ?? 0 },
            set: { v in
                // No startFrame-relative clamp here: TextField(value:format:)
                // commits on every keystroke, so clamping against the current
                // startFrame live would snap the field back mid-typing
                // whenever a partial digit sequence dipped below it. An
                // endFrame <= startFrame is harmless — the engine's
                // active-segment range check is simply never true for it,
                // not a crash — so there's nothing to defend against here.
                ctl.updateProjectConfig { cfg in
                    guard let idx = cfg.globalConfig.camera.segments.firstIndex(where: { $0.id == id }) else { return }
                    cfg.globalConfig.camera.segments[idx].endFrame = max(0, v)
                }
            }
        )
    }
}
