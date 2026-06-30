import SwiftUI

struct AudioWaveformView: View {
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var controller: AppController

    private var fps: Double {
        controller.projectConfig?.globalConfig.targetFPS ?? 30
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
                        drawMarkers(ctx: ctx, size: size)
                        drawTimeScale(ctx: ctx, size: size)
                        drawPlayhead(ctx: ctx, size: size)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = v.location.x / geo.size.width
                        audio.seek(to: frac * audio.duration)
                    }
            )
        }
    }

    // MARK: - Drawing

    private func drawWaveform(ctx: GraphicsContext, size: CGSize) {
        let samples  = audio.waveformData
        guard !samples.isEmpty else { return }
        let midY     = size.height / 2
        let xScale   = size.width / CGFloat(samples.count)
        let halfH    = midY * 0.88

        // Filled symmetric shape
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        for (i, s) in samples.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(i) * xScale, y: midY - CGFloat(s) * halfH))
        }
        path.addLine(to: CGPoint(x: size.width, y: midY))
        for (i, s) in samples.enumerated().reversed() {
            path.addLine(to: CGPoint(x: CGFloat(i) * xScale, y: midY + CGFloat(s) * halfH))
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(Color.accentColor.opacity(0.28)))

        // Outline top edge only
        var outline = Path()
        for (i, s) in samples.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * xScale, y: midY - CGFloat(s) * halfH)
            if i == 0 { outline.move(to: pt) } else { outline.addLine(to: pt) }
        }
        ctx.stroke(outline, with: .color(Color.accentColor.opacity(0.55)), lineWidth: 1)
    }

    private func drawMarkers(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        for marker in audio.markers {
            let frac = (Double(marker.frame) / fps) / audio.duration
            let x    = CGFloat(frac) * size.width

            var tick = Path()
            tick.move(to:    CGPoint(x: x, y: 0))
            tick.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(tick, with: .color(Color.orange.opacity(0.8)), lineWidth: 1.5)

            // Label
            let label    = marker.label.isEmpty ? "f\(marker.frame)" : marker.label
            let textSize = CGSize(width: 80, height: 14)
            let textOrigin = CGPoint(x: min(x + 3, size.width - textSize.width - 2), y: 4)
            ctx.draw(
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.orange),
                at: textOrigin,
                anchor: .topLeading
            )
        }
    }

    private func drawTimeScale(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        let interval = niceInterval(for: audio.duration, targetTicks: 14)
        var t = interval
        while t <= audio.duration {
            let x  = CGFloat(t / audio.duration) * size.width
            var ln = Path()
            ln.move(to:    CGPoint(x: x, y: size.height - 18))
            ln.addLine(to: CGPoint(x: x, y: size.height - 4))
            ctx.stroke(ln, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

            let mins = Int(t) / 60
            let secs = Int(t) % 60
            let lbl  = mins > 0 ? String(format: "%d:%02d", mins, secs) : String(format: "0:%02d", secs)
            ctx.draw(
                Text(lbl)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.7)),
                at: CGPoint(x: x + 3, y: size.height - 17),
                anchor: .topLeading
            )
            t += interval
        }
    }

    private func drawPlayhead(ctx: GraphicsContext, size: CGSize) {
        guard audio.duration > 0 else { return }
        let x = CGFloat(audio.currentTime / audio.duration) * size.width
        var line = Path()
        line.move(to:    CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 1.5)

        // Small triangle handle at top
        var handle = Path()
        handle.move(to:    CGPoint(x: x,     y: 0))
        handle.addLine(to: CGPoint(x: x - 5, y: 8))
        handle.addLine(to: CGPoint(x: x + 5, y: 8))
        handle.closeSubpath()
        ctx.fill(handle, with: .color(.white.opacity(0.9)))
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
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func niceInterval(for duration: Double, targetTicks: Int) -> Double {
        let raw = duration / Double(targetTicks)
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 20, 30, 60, 120, 300]
        return candidates.first { $0 >= raw } ?? 300
    }
}
