import AppKit
import SwiftUI

// MARK: - Zoom / scroll state

private final class WaveformState: ObservableObject {
    @Published var zoomLevel: CGFloat    = 1.0
    @Published var scrollFraction: Double = 0.0   // 0 = start, max = 1 − 1/zoom
    @Published var draggingMarkerID: UUID? = nil
    var scrubWasPlaying: Bool = false

    func clampScroll() {
        let max = Swift.max(0.0, 1.0 - 1.0 / Double(Swift.max(1, zoomLevel)))
        scrollFraction = Swift.max(0.0, Swift.min(max, scrollFraction))
    }

    func zoom(by factor: CGFloat, centreT: Double, duration: Double) {
        guard duration > 0 else { return }
        zoomLevel = Swift.max(1.0, Swift.min(50.0, zoomLevel * factor))
        let newVD = duration / Double(zoomLevel)
        scrollFraction = (centreT - newVD * 0.5) / duration
        clampScroll()
    }

    func pan(by fraction: Double) {
        scrollFraction += fraction
        clampScroll()
    }

    func reset() {
        zoomLevel = 1.0
        scrollFraction = 0.0
    }
}

// MARK: - NSView that handles all waveform input

private final class WaveformEventView: NSView {
    // Set by NSViewRepresentable on every update
    var state:     WaveformState?
    var audio:     AudioController?
    var fps:       Double  = 30
    var viewWidth: CGFloat = 1

    private var dragStartX: CGFloat?

    // Convert absolute time → pixel x given current zoom/scroll
    func timeToX(_ t: Double) -> CGFloat {
        guard let audio, audio.duration > 0, let state else { return 0 }
        let vDur   = audio.duration / Double(state.zoomLevel)
        let vStart = state.scrollFraction * audio.duration
        return CGFloat((t - vStart) / vDur) * viewWidth
    }

    // Convert pixel x → absolute time
    func xToTime(_ x: CGFloat) -> Double {
        guard let audio, audio.duration > 0, let state else { return 0 }
        let vDur   = audio.duration / Double(state.zoomLevel)
        let vStart = state.scrollFraction * audio.duration
        return min(audio.duration, max(0, vStart + Double(x / viewWidth) * vDur))
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Scroll wheel – vertical = zoom, horizontal = pan
    override func scrollWheel(with event: NSEvent) {
        guard let state, let audio else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if abs(dy) >= abs(dx) && abs(dy) > 0 {
            let cursorX = convert(event.locationInWindow, from: nil).x
            let cursorT = xToTime(cursorX)
            // scroll up (dy < 0) → zoom in
            let factor  = CGFloat(pow(1.1, Double(-dy) / 10.0))
            state.zoom(by: factor, centreT: cursorT, duration: audio.duration)
        } else if abs(dx) > 0 {
            let panFrac = Double(dx) / Double(viewWidth) / Double(state.zoomLevel)
            state.pan(by: panFrac)
        }
    }

    // MARK: Trackpad pinch – zoom toward cursor
    override func magnify(with event: NSEvent) {
        guard let state, let audio else { return }
        let cursorX = convert(event.locationInWindow, from: nil).x
        let cursorT = xToTime(cursorX)
        state.zoom(by: CGFloat(1.0 + event.magnification),
                   centreT: cursorT, duration: audio.duration)
    }

    // MARK: Mouse drag – seek / move marker
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStartX = convert(event.locationInWindow, from: nil).x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, let audio else { return }
        let loc = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.shift) {
            // Shift-drag: move nearest marker
            if state.draggingMarkerID == nil, let startX = dragStartX {
                state.draggingMarkerID = nearestMarker(to: startX, in: audio)
            }
            if let mid = state.draggingMarkerID {
                let t     = xToTime(loc.x)
                let frame = Int((t * fps).rounded())
                audio.moveMarker(id: mid, toFrame: frame)
            }
        } else {
            state.draggingMarkerID = nil
            audio.seek(to: xToTime(loc.x))
            if !audio.isPlaying && !state.scrubWasPlaying && audio.duration > 0 {
                audio.play()
                state.scrubWasPlaying = true
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state, let audio else { return }
        state.draggingMarkerID = nil
        if state.scrubWasPlaying {
            audio.pause()
            state.scrubWasPlaying = false
        }
        dragStartX = nil
    }

    private func nearestMarker(to x: CGFloat, in audio: AudioController) -> UUID? {
        guard audio.duration > 0 else { return nil }
        var best: (UUID, CGFloat)?
        for marker in audio.markers {
            let mx   = timeToX(Double(marker.frame) / fps)
            let dist = abs(mx - x)
            if dist < 12, best == nil || dist < best!.1 { best = (marker.id, dist) }
        }
        return best?.0
    }
}

// MARK: - NSViewRepresentable wrapper

private struct WaveformEventCapture: NSViewRepresentable {
    let state:     WaveformState
    let audio:     AudioController
    let fps:       Double
    let viewWidth: CGFloat

    func makeNSView(context: Context) -> WaveformEventView {
        let v = WaveformEventView()
        v.state = state; v.audio = audio
        v.fps = fps; v.viewWidth = viewWidth
        return v
    }

    func updateNSView(_ v: WaveformEventView, context: Context) {
        v.fps = fps; v.viewWidth = viewWidth
    }
}

// MARK: - Main view

struct AudioWaveformView: View {
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var controller: AppController
    @StateObject private var ws = WaveformState()

    private var fps: Double { controller.projectConfig?.globalConfig.targetFPS ?? 30 }

    // Visible time window
    private var visibleDuration: Double { audio.duration / Double(max(1, ws.zoomLevel)) }
    private var visibleStart:    Double { ws.scrollFraction * audio.duration }

    private func timeToX(_ t: Double, width: CGFloat) -> CGFloat {
        guard visibleDuration > 0 else { return 0 }
        return CGFloat((t - visibleStart) / visibleDuration) * width
    }

    var body: some View {
        if audio.audioFilename == nil {
            noAudioPlaceholder
        } else {
            VStack(spacing: 0) {
                waveformArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
            }
        }
    }

    // MARK: - Placeholder

    private var noAudioPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Import an audio file in the Audio panel to see the waveform here")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Waveform area

    private var waveformArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .controlBackgroundColor)

                if audio.waveformData.isEmpty {
                    ProgressView("Computing waveform…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Canvas { ctx, size in
                        drawWaveform(ctx: ctx, size: size)
                        if let a = audio.analysis { drawBeatTicks(ctx: ctx, size: size, analysis: a) }
                        drawMarkers(ctx: ctx, size: size)
                        drawTimeScale(ctx: ctx, size: size)
                        drawPlayhead(ctx: ctx, size: size)
                        if ws.zoomLevel > 1.01 { drawOverview(ctx: ctx, size: size) }
                    }

                    // Full-area input capture: handles scroll wheel, pinch, and drag
                    WaveformEventCapture(
                        state: ws, audio: audio,
                        fps: fps, viewWidth: geo.size.width
                    )
                }
            }
        }
    }

    // MARK: - Drawing

    private func drawWaveform(ctx: GraphicsContext, size: CGSize) {
        let samples = audio.waveformData
        guard !samples.isEmpty, audio.duration > 0 else { return }

        let startFrac = visibleStart / audio.duration
        let endFrac   = min(1.0, startFrac + 1.0 / Double(max(1, ws.zoomLevel)))
        let si = max(0, Int(startFrac * Double(samples.count)))
        let ei = min(samples.count, Int(endFrac * Double(samples.count)) + 2)
        let vis = samples[si..<ei]
        guard !vis.isEmpty else { return }

        let midY   = size.height / 2
        let halfH  = midY * 0.88
        let xScale = size.width / CGFloat(vis.count)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        for (i, s) in vis.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(i) * xScale, y: midY - CGFloat(s) * halfH))
        }
        path.addLine(to: CGPoint(x: size.width, y: midY))
        for (i, s) in vis.enumerated().reversed() {
            path.addLine(to: CGPoint(x: CGFloat(i) * xScale, y: midY + CGFloat(s) * halfH))
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(Color.accentColor.opacity(0.28)))

        var outline = Path()
        for (i, s) in vis.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * xScale, y: midY - CGFloat(s) * halfH)
            if i == 0 { outline.move(to: pt) } else { outline.addLine(to: pt) }
        }
        ctx.stroke(outline, with: .color(Color.accentColor.opacity(0.55)), lineWidth: 1)
    }

    private func drawBeatTicks(ctx: GraphicsContext, size: CGSize, analysis: AudioAnalysis) {
        guard audio.duration > 0 else { return }
        let vEnd = visibleStart + visibleDuration
        for t in analysis.beatOnsets {
            guard t >= visibleStart, t <= vEnd else { continue }
            let x = timeToX(t, width: size.width)
            var p = Path(); p.move(to: CGPoint(x: x, y: size.height - 34))
            p.addLine(to: CGPoint(x: x, y: size.height - 24))
            ctx.stroke(p, with: .color(Color.cyan.opacity(0.65)), lineWidth: 1)
        }
        for t in analysis.lowFreqOnsets {
            guard t >= visibleStart, t <= vEnd else { continue }
            let x = timeToX(t, width: size.width)
            var p = Path(); p.move(to: CGPoint(x: x, y: size.height - 22))
            p.addLine(to: CGPoint(x: x, y: size.height - 14))
            ctx.stroke(p, with: .color(Color.green.opacity(0.65)), lineWidth: 1)
        }
    }

    private func drawMarkers(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        let vEnd = visibleStart + visibleDuration
        for marker in audio.markers {
            let t = Double(marker.frame) / fps
            guard t >= visibleStart - 0.1, t <= vEnd + 0.1 else { continue }
            let x          = timeToX(t, width: size.width)
            let isDragging = marker.id == ws.draggingMarkerID
            let color      = isDragging ? Color.yellow : Color.orange
            let lw: CGFloat = isDragging ? 2.5 : 1.5

            var tick = Path()
            tick.move(to: CGPoint(x: x, y: 0)); tick.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(tick, with: .color(color.opacity(isDragging ? 1.0 : 0.8)), lineWidth: lw)

            if isDragging {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: 0, width: 10, height: 10)),
                         with: .color(color))
            }
            let label = marker.label.isEmpty ? "f\(marker.frame)" : marker.label
            ctx.draw(
                Text(label).font(.system(size: 9, weight: isDragging ? .semibold : .medium))
                           .foregroundStyle(color),
                at: CGPoint(x: min(x + 3, size.width - 82), y: isDragging ? 12 : 4),
                anchor: .topLeading
            )
        }
    }

    private func drawTimeScale(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        let interval = niceInterval(for: visibleDuration, targetTicks: 14)
        let tFirst   = (floor(visibleStart / interval) + 1) * interval
        var t = tFirst
        while t <= visibleStart + visibleDuration {
            let x = timeToX(t, width: size.width)
            guard x >= 0, x <= size.width else { t += interval; continue }
            var ln = Path()
            ln.move(to: CGPoint(x: x, y: size.height - 18))
            ln.addLine(to: CGPoint(x: x, y: size.height - 4))
            ctx.stroke(ln, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            let m = Int(t) / 60, s = Int(t) % 60
            let lbl = m > 0 ? String(format: "%d:%02d", m, s) : String(format: "0:%02d", s)
            ctx.draw(Text(lbl).font(.system(size: 9, design: .monospaced))
                              .foregroundStyle(Color.secondary.opacity(0.7)),
                     at: CGPoint(x: x + 3, y: size.height - 17), anchor: .topLeading)
            t += interval
        }
    }

    private func drawPlayhead(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        let x = timeToX(audio.currentTime, width: size.width)
        guard x >= -2, x <= size.width + 2 else { return }
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        var handle = Path()
        handle.move(to: CGPoint(x: x, y: 0))
        handle.addLine(to: CGPoint(x: x - 5, y: 8)); handle.addLine(to: CGPoint(x: x + 5, y: 8))
        handle.closeSubpath()
        ctx.fill(handle, with: .color(.white.opacity(0.9)))
    }

    private func drawOverview(ctx: GraphicsContext, size: CGSize) {
        let h: CGFloat = 10, y: CGFloat = 4
        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: h)),
                 with: .color(Color.black.opacity(0.4)))
        let samples = audio.waveformData
        if samples.count > 1 {
            let midY = y + h / 2, halfH = h / 2 * 0.85
            var mini = Path()
            for (i, s) in samples.enumerated() {
                let x = CGFloat(i) / CGFloat(samples.count - 1) * size.width
                mini.move(to: CGPoint(x: x, y: midY - CGFloat(s) * halfH))
                mini.addLine(to: CGPoint(x: x, y: midY + CGFloat(s) * halfH))
            }
            ctx.stroke(mini, with: .color(Color.accentColor.opacity(0.45)), lineWidth: 1)
        }
        let winX = CGFloat(ws.scrollFraction) * size.width
        let winW = max(4, size.width / ws.zoomLevel)
        let wr   = CGRect(x: winX, y: y, width: winW, height: h)
        ctx.fill(Path(wr), with: .color(Color.white.opacity(0.18)))
        ctx.stroke(Path(wr), with: .color(Color.white.opacity(0.7)), lineWidth: 1)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(formatTimecode(audio.currentTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("frame \(Int((audio.currentTime * fps).rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            if ws.zoomLevel > 1.01 {
                HStack(spacing: 8) {
                    Text(String(format: "%.1f×", ws.zoomLevel))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Button("Reset") { ws.reset() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .modifier(LoomHoverHelp("Reset zoom to full view"))
                }
            }
            if !audio.waveformData.isEmpty {
                Text(formatTimecode(audio.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func formatTimecode(_ t: Double) -> String {
        let i = Int(t); return String(format: "%d:%02d", i / 60, i % 60)
    }

    private func niceInterval(for duration: Double, targetTicks: Int) -> Double {
        let raw = duration / Double(max(1, targetTicks))
        return [0.25, 0.5, 1, 2, 5, 10, 15, 20, 30, 60, 120, 300].first { $0 >= raw } ?? 300
    }
}
