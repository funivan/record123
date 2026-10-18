import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit

func hostSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "recordy.screen")
    private(set) var firstPTS: Double?
    private var lastVideoPTS = CMTime.zero
    private var firstFrameWaiters: [CheckedContinuation<Double?, Never>] = []
    private(set) var pixelSize = CGSize.zero
    var onStreamError: ((Error) -> Void)?
    var writerError: Error? { writer?.status == .failed ? writer?.error : nil }

    func start(display: SCDisplay, region: CGRect?, excludingWindowIDs: [CGWindowID], url: URL, scale: CGFloat) async throws {
        queue.sync {
            firstPTS = nil
            lastVideoPTS = .zero
            audioInput = nil
            videoInput = nil
            self.writer = nil
        }
        let content = try await SCShareableContent.current
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let cfg = SCStreamConfiguration()
        let source = region ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        if region != nil { cfg.sourceRect = source }
        let w = Int(source.width * scale) & ~1, h = Int(source.height * scale) & ~1
        cfg.width = w; cfg.height = h
        let fps = UserDefaults.standard.object(forKey: "fps") as? Int ?? 60
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = UserDefaults.standard.object(forKey: "showCursor") as? Bool ?? true
        cfg.queueDepth = 6
        cfg.capturesAudio = true
        cfg.sampleRate = 48000
        cfg.channelCount = 2
        cfg.excludesCurrentProcessAudio = true
        pixelSize = CGSize(width: w, height: h)

        let writer = try AVAssetWriter(url: url, fileType: .mov)
        let bitrate = max(8_000_000, w * h * 4)
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: fps],
        ])
        vi.expectsMediaDataInRealTime = true
        writer.add(vi)
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48000, AVEncoderBitRateKey: 160_000,
        ])
        ai.expectsMediaDataInRealTime = true
        writer.add(ai)
        audioInput = ai
        writer.movieFragmentInterval = CMTime(seconds: 4, preferredTimescale: 600)
        writer.startWriting()
        self.writer = writer
        videoInput = vi

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid, let writer, writer.status == .writing else { return }
        switch type {
        case .screen:
            guard let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            if firstPTS == nil {
                firstPTS = sb.presentationTimeStamp.seconds
                writer.startSession(atSourceTime: sb.presentationTimeStamp)
                resumeFirstFrameWaiters()
            }
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sb)
                lastVideoPTS = sb.presentationTimeStamp
            }
        case .audio:
            guard let first = firstPTS, sb.presentationTimeStamp.seconds >= first else { return }
            if audioInput?.isReadyForMoreMediaData == true { audioInput?.append(sb) }
        default: break
        }
    }

    func waitForFirstFrame(timeout: Double) async -> Double? {
        await withCheckedContinuation { (c: CheckedContinuation<Double?, Never>) in
            queue.async {
                if let first = self.firstPTS { c.resume(returning: first); return }
                self.firstFrameWaiters.append(c)
                self.queue.asyncAfter(deadline: .now() + timeout) { self.resumeFirstFrameWaiters() }
            }
        }
    }

    private func resumeFirstFrameWaiters() {
        let waiters = firstFrameWaiters
        firstFrameWaiters = []
        waiters.forEach { $0.resume(returning: firstPTS) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStreamError?(error) }
    }

    func stop(endHostTime: Double) async {
        try? await stream?.stopCapture()
        stream = nil
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.resumeFirstFrameWaiters()
                guard let writer = self.writer, writer.status == .writing else { c.resume(); return }
                guard self.firstPTS != nil else { writer.cancelWriting(); c.resume(); return }
                let end = CMTime(seconds: max(endHostTime, self.lastVideoPTS.seconds), preferredTimescale: 600)
                writer.endSession(atSourceTime: end)
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting { c.resume() }
            }
        }
    }
}

final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "recordy.camera")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var url: URL?
    private var writing = false
    private(set) var firstPTS: Double?
    private var lastPTS = CMTime.zero

    func configure(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw NSError(domain: "recordy", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot use camera"]) }
        session.addInput(input)
        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = false
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
    }

    private let sessionQueue = DispatchQueue(label: "recordy.camera.session")

    func startRunning() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stopRunning() { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func beginWriting(to url: URL) {
        queue.sync {
            self.url = url
            self.firstPTS = nil
            self.writer = nil
            self.writing = true
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pb = CMSampleBufferGetImageBuffer(sb) { BlurredPreview.shared.submit(pb) }
        guard writing, let url else { return }
        if writer == nil {
            guard let fd = CMSampleBufferGetFormatDescription(sb) else { return }
            let dims = CMVideoFormatDescriptionGetDimensions(fd)
            guard let w = try? AVAssetWriter(url: url, fileType: .mov) else { return }
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dims.width), AVVideoHeightKey: Int(dims.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
            ])
            i.expectsMediaDataInRealTime = true
            w.add(i)
            w.movieFragmentInterval = CMTime(seconds: 4, preferredTimescale: 600)
            w.startWriting()
            w.startSession(atSourceTime: sb.presentationTimeStamp)
            firstPTS = sb.presentationTimeStamp.seconds
            writer = w; input = i
        }
        if input?.isReadyForMoreMediaData == true {
            input?.append(sb)
            lastPTS = sb.presentationTimeStamp
        }
    }

    func finish(endHostTime: Double) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.writing = false
                guard let w = self.writer, w.status == .writing else { c.resume(); return }
                w.endSession(atSourceTime: CMTime(seconds: max(endHostTime, self.lastPTS.seconds), preferredTimescale: 600))
                self.input?.markAsFinished()
                w.finishWriting { c.resume() }
                self.writer = nil
            }
        }
    }
}

final class MicRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "recordy.mic")
    private let sessionQueue = DispatchQueue(label: "recordy.mic.session")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var url: URL?
    private(set) var firstPTS: Double?

    func start(device: AVCaptureDevice, url: URL) throws {
        let input = try AVCaptureDeviceInput(device: device)
        queue.sync {
            self.url = url
            self.firstPTS = nil
            self.writer = nil
            self.input = nil
        }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "recordy", code: 11, userInfo: [NSLocalizedDescriptionKey: "Cannot use microphone"])
        }
        session.addInput(input)
        if !session.outputs.contains(output) {
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
        sessionQueue.async { self.session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let url else { return }
        if writer == nil {
            guard let fd = CMSampleBufferGetFormatDescription(sb),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
                  let w = try? AVAssetWriter(url: url, fileType: .m4a) else { return }
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: Int(min(max(asbd.mChannelsPerFrame, 1), 2)),
                AVSampleRateKey: min(asbd.mSampleRate, 48000),
                AVEncoderBitRateKey: 128_000,
            ])
            i.expectsMediaDataInRealTime = true
            w.add(i)
            w.startWriting()
            w.startSession(atSourceTime: sb.presentationTimeStamp)
            firstPTS = sb.presentationTimeStamp.seconds
            writer = w; input = i
        }
        if input?.isReadyForMoreMediaData == true { input?.append(sb) }
    }

    func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                self.queue.async {
                    self.url = nil
                    let w = self.writer
                    self.writer = nil
                    guard let w, w.status == .writing else { c.resume(); return }
                    self.input?.markAsFinished()
                    w.finishWriting { c.resume() }
                }
            }
        }
    }
}

final class CursorTracker {
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var samples: [CursorSample] = []
    private var last = CGPoint(x: -1, y: -1)

    func start(frame: CGRect, t0: Double) {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "recordy.cursor"))
        t.schedule(deadline: .now(), repeating: .milliseconds(8))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            let nx = (p.x - frame.minX) / frame.width
            let ny = 1 - (p.y - frame.minY) / frame.height
            let pt = CGPoint(x: nx, y: ny)
            let now = hostSeconds() - t0
            self.lock.lock()
            if pt != self.last || (self.samples.last.map { now - $0.t > 0.25 } ?? true) {
                self.samples.append(CursorSample(t: now, x: min(max(nx, 0), 1), y: min(max(ny, 0), 1)))
                self.last = pt
            }
            self.lock.unlock()
        }
        t.resume()
        timer = t
    }

    func snapshot() -> [CursorSample] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func stop() -> [CursorSample] {
        timer?.cancel()
        timer = nil
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}

enum Devices {
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified).devices
    }
    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }
}

final class LevelMeter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "recordy.level")
    private let sessionQueue = DispatchQueue(label: "recordy.level.session")
    var onLevel: ((Float) -> Void)?

    func start(device: AVCaptureDevice) throws {
        stop()
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) { session.addInput(input) }
        if !session.outputs.contains(output) {
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
        sessionQueue.async { self.session.startRunning() }
    }

    func stop() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              let block = CMSampleBufferGetDataBuffer(sb) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let ptr else { return }
        var sum: Double = 0
        var n = 0
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            n = length / 4
            ptr.withMemoryRebound(to: Float.self, capacity: n) { p in for i in 0..<n { sum += Double(p[i] * p[i]) } }
        } else {
            n = length / 2
            ptr.withMemoryRebound(to: Int16.self, capacity: n) { p in for i in 0..<n { let v = Double(p[i]) / 32768; sum += v * v } }
        }
        guard n > 0 else { return }
        let rms = sqrt(sum / Double(n))
        let db = 20 * log10(max(rms, 1e-6))
        let level = Float(min(max((db + 55) / 55, 0), 1))
        DispatchQueue.main.async { self.onLevel?(level) }
    }
}
