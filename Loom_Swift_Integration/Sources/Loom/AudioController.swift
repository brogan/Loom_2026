import AVFoundation
import Foundation
import SwiftUI

// MARK: - Data model

struct AudioAnalysis {
    var bpm: Double           = 0
    var beatOnsets: [Double]  = []  // seconds
    var lowFreqOnsets: [Double] = [] // seconds (kick proxy)
}

public struct AudioMarker: Identifiable {
    public var id: UUID    = UUID()
    public var frame: Int
    public var label: String = ""
    public var notes: String = ""

    public init(frame: Int) { self.frame = frame }
}

extension AudioMarker: Codable {
    private enum CodingKeys: String, CodingKey { case id, frame, label, notes }
    public init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decodeIfPresent(UUID.self,   forKey: .id)    ?? UUID()
        frame  = try c.decode(Int.self,              forKey: .frame)
        label  = try c.decodeIfPresent(String.self,  forKey: .label) ?? ""
        notes  = try c.decodeIfPresent(String.self,  forKey: .notes) ?? ""
    }
}

private struct AudioState: Codable {
    var audioFilename: String?
    var markers: [AudioMarker] = []
}

// MARK: - Controller

@MainActor
final class AudioController: ObservableObject {
    @Published var audioFilename: String?  = nil
    @Published var duration: Double        = 0
    @Published var currentTime: Double     = 0
    @Published var isPlaying: Bool         = false
    @Published var waveformData: [Float]   = []
    @Published var markers: [AudioMarker]  = []
    @Published var analysis: AudioAnalysis? = nil
    @Published var fileNotFound: Bool      = false

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var projectURL: URL?

    // MARK: - Project lifecycle

    func projectOpened(_ url: URL) {
        projectURL = url
        loadState(from: url)
    }

    func clear() {
        stop()
        player        = nil
        waveformData  = []
        analysis      = nil
        audioFilename = nil
        markers       = []
        duration      = 0
        currentTime   = 0
        fileNotFound  = false
        saveState()
    }

    // MARK: - Import

    func importAudio(from sourceURL: URL) {
        guard let projectURL else { return }
        let audioDir = projectURL.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let dest = audioDir.appendingPathComponent(sourceURL.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        audioFilename = sourceURL.lastPathComponent
        fileNotFound  = false
        loadPlayer(from: dest)
        computeWaveform(from: dest)
        computeAnalysis(from: dest)
        saveState()
    }

    // MARK: - Playback

    func play() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying   = false
        currentTime = 0
        stopTimer()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        let t = max(0, min(duration, time))
        player?.currentTime = t
        currentTime = t
    }

    // MARK: - Markers

    func hasAnalysisMarkers(prefix: String) -> Bool {
        markers.contains { m in
            m.label.hasPrefix(prefix) && m.label.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
    }

    func toggleAnalysisMarkers(times: [Double], fps: Double, prefix: String) {
        if hasAnalysisMarkers(prefix: prefix) {
            markers.removeAll { m in
                m.label.hasPrefix(prefix) && m.label.dropFirst(prefix.count).allSatisfy(\.isNumber)
            }
        } else {
            for t in times {
                let frame = Int((t * fps).rounded())
                var m = AudioMarker(frame: frame)
                m.label = "\(prefix)\(frame)"
                markers.append(m)
            }
            markers.sort { $0.frame < $1.frame }
        }
        saveState()
    }

    func dropMarker(fps: Double) {
        let frame = Int((currentTime * fps).rounded())
        let secs  = Int(currentTime)
        let label = String(format: "%d:%02d", secs / 60, secs % 60)
        var m = AudioMarker(frame: frame)
        m.label = label
        markers.append(m)
        markers.sort { $0.frame < $1.frame }
        saveState()
    }

    func removeMarker(id: UUID) {
        markers.removeAll { $0.id == id }
        saveState()
    }

    func updateMarkerLabel(id: UUID, label: String) {
        guard let idx = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[idx].label = label
        saveState()
    }

    func updateMarkerNotes(id: UUID, notes: String) {
        guard let idx = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[idx].notes = notes
        saveState()
    }

    // Move marker to a new frame, constrained between its neighbours (1-frame gap).
    func moveMarker(id: UUID, toFrame target: Int) {
        guard let idx = markers.firstIndex(where: { $0.id == id }) else { return }
        let minFrame = idx > 0 ? markers[idx - 1].frame + 1 : 0
        let maxFrame = idx < markers.count - 1 ? markers[idx + 1].frame - 1 : Int.max
        markers[idx].frame = max(minFrame, min(maxFrame, target))
        saveState()
    }

    // MARK: - Private helpers

    private func loadPlayer(from url: URL) {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.prepareToPlay()
        player      = p
        duration    = p.duration
        currentTime = 0
    }

    private func computeWaveform(from url: URL) {
        Task.detached(priority: .userInitiated) {
            let data = await Self.buildWaveform(url: url)
            await MainActor.run { [weak self] in self?.waveformData = data }
        }
    }

    private func computeAnalysis(from url: URL) {
        Task.detached(priority: .background) {
            let result = await Self.buildAnalysis(url: url)
            await MainActor.run { [weak self] in self?.analysis = result }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let p = self.player else { return }
                self.currentTime = p.currentTime
                if !p.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Persistence

    private func loadState(from url: URL) {
        let stateURL = url.appendingPathComponent("audio.json")
        if let data  = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(AudioState.self, from: data) {
            markers = state.markers
            if let filename = state.audioFilename {
                audioFilename = filename
                let audioURL = url.appendingPathComponent("audio").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    loadPlayer(from: audioURL)
                    computeWaveform(from: audioURL)
                    computeAnalysis(from: audioURL)
                } else {
                    fileNotFound = true
                }
            }
            return
        }
        // No audio.json: scan the audio/ directory and pick the first supported file.
        let audioDir = url.appendingPathComponent("audio", isDirectory: true)
        autoDetectAudio(in: audioDir)
    }

    private static let supportedExtensions: Set<String> = [
        "wav", "aiff", "aif", "mp3", "m4a", "caf", "flac", "aac"
    ]

    private func autoDetectAudio(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        guard let found = files.first(where: {
            Self.supportedExtensions.contains($0.pathExtension.lowercased())
        }) else { return }
        audioFilename = found.lastPathComponent
        fileNotFound  = false
        loadPlayer(from: found)
        computeWaveform(from: found)
        computeAnalysis(from: found)
        saveState()
    }

    private func saveState() {
        guard let projectURL else { return }
        let state = AudioState(audioFilename: audioFilename, markers: markers)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: projectURL.appendingPathComponent("audio.json"))
    }

    // MARK: - Audio analysis (background)

    private static func buildAnalysis(url: URL) async -> AudioAnalysis {
        guard let file = try? AVAudioFile(forReading: url) else { return AudioAnalysis() }
        let format  = file.processingFormat
        let sr      = format.sampleRate
        let ch      = Int(format.channelCount)
        let maxRead = Int(sr * 300)  // cap at 5 min for analysis
        let nFrames = min(Int(file.length), maxRead)
        guard sr > 0, ch > 0, nFrames > 16 else { return AudioAnalysis() }

        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(nFrames)),
              (try? file.read(into: buf)) != nil,
              let chData = buf.floatChannelData else { return AudioAnalysis() }

        let len = Int(buf.frameLength)

        // Mono mix
        var mono = [Float](repeating: 0, count: len)
        for c in 0..<ch { for f in 0..<len { mono[f] += chData[c][f] } }
        if ch > 1 { let inv = 1.0 / Float(ch); for f in 0..<len { mono[f] *= inv } }

        // Two-pass IIR lowpass ~80 Hz for kick proxy (steeper roll-off)
        var low = mono
        let alpha = Float(1.0 / (sr / (2.0 * .pi * 80.0) + 1.0))
        for i in 1..<len { low[i] = alpha * low[i] + (1 - alpha) * low[i-1] }
        for i in 1..<len { low[i] = alpha * low[i] + (1 - alpha) * low[i-1] }

        // 10ms hop energy
        let hop = max(1, Int(sr * 0.01))
        let hops = len / hop
        let hopSec = Double(hop) / sr
        guard hops > 8 else { return AudioAnalysis() }

        func hopEnergy(_ sig: [Float]) -> [Float] {
            var e = [Float](repeating: 0, count: hops)
            for h in 0..<hops {
                let s = h * hop, end = min(s + hop, len)
                var v: Float = 0
                for i in s..<end { v += sig[i] * sig[i] }
                e[h] = v / Float(end - s)
            }
            return e
        }

        func onsetStrength(_ e: [Float]) -> [Float] {
            var o = [Float](repeating: 0, count: e.count)
            for i in 1..<e.count {
                o[i] = max(0, log(max(e[i], 1e-10)) - log(max(e[i-1], 1e-10)))
            }
            return o
        }

        let fullOnset = onsetStrength(hopEnergy(mono))
        let lowOnset  = onsetStrength(hopEnergy(low))

        // BPM via autocorrelation (40–200 BPM)
        let lagMin = max(1, Int((60.0 / 200.0) / hopSec))
        let lagMax = min(hops - 1, Int((60.0 / 40.0) / hopSec))
        var bestLag = lagMin; var bestScore: Float = -1
        for lag in lagMin...lagMax {
            var score: Float = 0
            let n = hops - lag
            for i in 0..<n { score += fullOnset[i] * fullOnset[i + lag] }
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        let bpm = bestScore > 0 ? 60.0 / (Double(bestLag) * hopSec) : 0
        let beatPeriod = bpm > 0 ? 60.0 / bpm : 0.5

        // Peak pick using adaptive local-mean threshold over a ±500ms window.
        // multiplier: how many times the local mean a peak must exceed to count.
        func pickPeaks(_ onset: [Float], minGapSec: Double, multiplier: Float) -> [Double] {
            guard onset.count > 2 else { return [] }
            let halfWin = max(5, Int(0.5 / hopSec))
            var localMean = [Float](repeating: 0, count: onset.count)
            for i in 0..<onset.count {
                let lo = max(0, i - halfWin), hi = min(onset.count - 1, i + halfWin)
                var sum: Float = 0
                for j in lo...hi { sum += onset[j] }
                localMean[i] = sum / Float(hi - lo + 1)
            }
            let minGap = max(1, Int(minGapSec / hopSec))
            var out: [Double] = []; var last = -minGap
            for i in 1..<(onset.count - 1) {
                let thresh = localMean[i] * multiplier
                guard onset[i] > thresh, onset[i] > onset[i-1], onset[i] >= onset[i+1] else { continue }
                guard (i - last) >= minGap else { continue }
                out.append(Double(i) * hopSec); last = i
            }
            return out
        }

        // beats: must be 2.5× local mean, spaced ≥ half a beat period
        // kicks: must be 4× local mean (very selective), spaced ≥ 250 ms
        let beatOnsets    = pickPeaks(fullOnset, minGapSec: beatPeriod * 0.5, multiplier: 2.5)
        let lowFreqOnsets = pickPeaks(lowOnset,  minGapSec: 0.25,             multiplier: 4.0)

        return AudioAnalysis(bpm: bpm, beatOnsets: beatOnsets, lowFreqOnsets: lowFreqOnsets)
    }

    // MARK: - Waveform computation (background)

    private static func buildWaveform(url: URL, buckets: Int = 2000) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format      = file.processingFormat
        let totalFrames = Int(file.length)
        let channels    = Int(format.channelCount)
        guard totalFrames > 0, channels > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
              ),
              let _ = try? file.read(into: buffer),
              let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let bucketSize  = max(1, frameLength / buckets)
        var result      = [Float]()
        result.reserveCapacity(buckets)
        var globalPeak: Float = 0

        for b in 0..<buckets {
            let start = b * bucketSize
            let end   = min(start + bucketSize, frameLength)
            var peak: Float = 0
            for f in start..<end {
                var s: Float = 0
                for ch in 0..<channels { s += abs(channelData[ch][f]) }
                peak = max(peak, s / Float(channels))
            }
            result.append(peak)
            globalPeak = max(globalPeak, peak)
        }
        if globalPeak > 0 {
            let scale = 1.0 / globalPeak
            for i in result.indices { result[i] *= scale }
        }
        return result
    }
}
