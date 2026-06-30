import AVFoundation
import Foundation
import SwiftUI

// MARK: - Data model

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
        guard let data  = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AudioState.self, from: data) else { return }
        markers = state.markers
        guard let filename = state.audioFilename else { return }
        audioFilename = filename
        let audioURL  = url.appendingPathComponent("audio").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: audioURL.path) {
            loadPlayer(from: audioURL)
            computeWaveform(from: audioURL)
        } else {
            fileNotFound = true
        }
    }

    private func saveState() {
        guard let projectURL else { return }
        let state = AudioState(audioFilename: audioFilename, markers: markers)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: projectURL.appendingPathComponent("audio.json"))
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
