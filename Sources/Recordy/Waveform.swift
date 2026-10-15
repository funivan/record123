import SwiftUI
import AVFoundation

actor WaveformStore {
    static let shared = WaveformStore()
    static let rate = 100.0
    private var cache: [URL: [Float]] = [:]

    func peaks(for url: URL) async -> [Float] {
        if let c = cache[url] { return c }
        let p = await Self.read(url)
        cache[url] = p
        return p
    }

    private static func read(_ url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 8000,
        ])
        reader.add(out)
        guard reader.startReading() else { return [] }
        let window = Int(8000 / rate)
        var peaks: [Float] = []
        var peak: Int32 = 0
        var n = 0
        while let sb = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0
            var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let ptr else { continue }
            let count = length / 2
            ptr.withMemoryRebound(to: Int16.self, capacity: count) { p in
                for i in 0..<count {
                    peak = max(peak, abs(Int32(p[i])))
                    n += 1
                    if n == window {
                        peaks.append(Float(peak) / 32768)
                        peak = 0
                        n = 0
                    }
                }
            }
        }
        return peaks
    }
}

struct WaveformView: View {
    let url: URL
    let srcStart: Double
    let duration: Double
    let color: Color
    @State private var peaks: [Float] = []

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty, size.width > 2 else { return }
            let step: CGFloat = 2
            let cols = max(Int(size.width / step), 1)
            var path = Path()
            for i in 0..<cols {
                let a = Int((srcStart + duration * Double(i) / Double(cols)) * WaveformStore.rate)
                let b = max(a + 1, Int((srcStart + duration * Double(i + 1) / Double(cols)) * WaveformStore.rate))
                guard a < peaks.count else { break }
                var m: Float = 0
                for j in a..<min(b, peaks.count) { m = max(m, peaks[j]) }
                let h = max(1.5, CGFloat(m.squareRoot()) * size.height * 0.9)
                path.addRect(CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: step - 0.6, height: h))
            }
            ctx.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
        .task(id: url) { peaks = await WaveformStore.shared.peaks(for: url) }
    }
}
