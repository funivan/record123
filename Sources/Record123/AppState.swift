import Foundation
import SwiftUI
import Combine
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreAudio

enum RecPhase: Equatable { case idle, countdown(Int), recording, saving }

@MainActor
final class AppState: ObservableObject {
    @Published var phase = RecPhase.idle
    @Published var displays: [SCDisplay] = []
    @Published var cameras: [AVCaptureDevice] = []
    @Published var mics: [AVCaptureDevice] = []
    @Published var selectedDisplay: CGDirectDisplayID = CGMainDisplayID() { didSet { syncRegionFrame() } }
    @Published var selectedCamera: String { didSet { if !applyingDefaults, !Self.accessDenied(.video) { UserDefaults.standard.set(selectedCamera, forKey: "camera") } } }
    @Published var selectedMic: String { didSet { if !applyingDefaults, !Self.accessDenied(.audio) { UserDefaults.standard.set(selectedMic, forKey: "mic") } } }
    @Published var captureArea: Bool {
        didSet { syncRegionFrame() }
    }
    @Published var region: CaptureRegion? {
        didSet {
            if let region, let d = try? JSONEncoder().encode(region) {
                UserDefaults.standard.set(d, forKey: "captureRegion")
            } else {
                UserDefaults.standard.removeObject(forKey: "captureRegion")
            }
        }
    }
    @Published var cameraBlur: Bool {
        didSet {
            BlurredPreview.shared.enabled = cameraBlur
            var s = DefaultStyle.load()
            guard s.cameraBlur != cameraBlur else { return }
            s.cameraBlur = cameraBlur
            DefaultStyle.save(s)
        }
    }
    @Published var startCorner = CameraCorner.bottomRight
    @Published var startShape = CameraShape.circle
    @Published var projects: [ProjectRef] = []
    var draggingRecording: ProjectRef?
    @Published var editor: EditorModel? { didSet { syncRegionFrame() } }
    private var openCancellable: AnyCancellable?
    @Published var error: String?
    @Published var elapsed = 0.0
    @Published var testing = false
    @Published var micLevel: Float = 0
    private let meter = LevelMeter()
    var previewSession: AVCaptureSession { camRec.session }
    @Published var testHasCamera = false

    private let screenRec = ScreenRecorder()
    private let camRec = CameraRecorder()
    private let micRec = MicRecorder()
    private let cursor = CursorTracker()
    private let overlay = CameraOverlay()
    private let regionFrame = RegionFrame()
    private var t0 = 0.0
    private var dir: URL?
    private var zoomKeys: [ZoomKey] = []
    private var cameraKeys: [CameraKey] = []
    private var cameraVisible = true
    private var style = DefaultStyle.load()
    private var ticker: Timer?
    private var usingCamera = false
    private var usingMic = false
    private var hiddenWindows: [NSWindow] = []
    private var lastDraftSave = 0.0
    private var applyingDefaults = false

    init() {
        selectedCamera = UserDefaults.standard.string(forKey: "camera") ?? ""
        selectedMic = UserDefaults.standard.string(forKey: "mic") ?? ""
        captureArea = false
        cameraBlur = DefaultStyle.load().cameraBlur
        BlurredPreview.shared.enabled = cameraBlur
        region = UserDefaults.standard.data(forKey: "captureRegion").flatMap { try? JSONDecoder().decode(CaptureRegion.self, from: $0) }
        AppDelegate.state = self
        HotkeyCenter.shared.handler = { [weak self] a in self?.handle(a) }
        HotkeyCenter.shared.register()
        projects = ProjectRef.loadAll()
        refreshDevices()
        screenRec.onStreamError = { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, self.phase == .recording else { return }
                Task {
                    await self.stop()
                    self.error = "Recording stopped: \(e.localizedDescription)"
                }
            }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            }
        }
        Task { await recoverProjects() }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let w = n.object as? NSWindow, !(w is NSPanel) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.syncRegionFrame() } }
            }
        }
        syncRegionFrame()
    }

    var isBusy: Bool { phase != .idle }

    func refreshDevices() {
        cameras = Self.builtInFirst(Devices.cameras())
        mics = Self.builtInFirst(Devices.microphones())
        let camera = DeviceDefaults.selection(
            stored: UserDefaults.standard.string(forKey: "camera"),
            available: cameras.map(Self.option),
            systemDefault: AVCaptureDevice.default(for: .video)?.uniqueID,
            accessDenied: Self.accessDenied(.video))
        applyingDefaults = true
        defer { applyingDefaults = false }
        if camera != selectedCamera { selectedCamera = camera }
        let mic = DeviceDefaults.selection(
            stored: UserDefaults.standard.string(forKey: "mic"),
            available: mics.map(Self.option),
            systemDefault: AVCaptureDevice.default(for: .audio)?.uniqueID,
            accessDenied: Self.accessDenied(.audio))
        if mic != selectedMic { selectedMic = mic }
        guard CGPreflightScreenCaptureAccess() else { return }
        Task {
            if let c = try? await SCShareableContent.current {
                displays = c.displays
                if let id = DeviceDefaults.display(current: selectedDisplay, available: displays.map(\.displayID), main: CGMainDisplayID()), id != selectedDisplay { selectedDisplay = id }
            }
        }
    }

    private static func builtInFirst(_ devices: [AVCaptureDevice]) -> [AVCaptureDevice] {
        devices.filter { option($0).builtIn } + devices.filter { !option($0).builtIn }
    }

    private static func option(_ d: AVCaptureDevice) -> DeviceOption {
        DeviceOption(id: d.uniqueID, builtIn: d.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn))
    }

    private func selectedOrMainDisplay() -> SCDisplay? {
        guard let id = DeviceDefaults.display(current: selectedDisplay, available: displays.map(\.displayID), main: CGMainDisplayID()) else { return nil }
        return displays.first(where: { $0.displayID == id })
    }

    private static func accessDenied(_ type: AVMediaType) -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: type)
        return status == .denied || status == .restricted
    }

    func activeRegion(for displayID: CGDirectDisplayID) -> CGRect? {
        guard captureArea, let region, region.displayID == displayID else { return nil }
        return region.rect
    }

    nonisolated static func shouldShowRegionFrame(phase: RecPhase, editorOpen: Bool, mainWindowVisible: Bool, hasActiveRegion: Bool) -> Bool {
        phase == .idle && !editorOpen && mainWindowVisible && hasActiveRegion
    }

    private var mainWindowVisible: Bool {
        NSApp.windows.contains { !($0 is NSPanel) && $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized }
    }

    private func syncRegionFrame() {
        let rect = activeRegion(for: selectedDisplay)
        guard Self.shouldShowRegionFrame(phase: phase, editorOpen: editor != nil || openCancellable != nil, mainWindowVisible: mainWindowVisible, hasActiveRegion: rect != nil),
              let rect, let screen = nsScreen(selectedDisplay) else {
            regionFrame.hide()
            return
        }
        regionFrame.show(on: screen, rect: rect)
    }

    func chooseArea() {
        Task {
            guard let display = selectedOrMainDisplay(),
                  let screen = nsScreen(display.displayID) else { error = "No display available"; return }
            let initial = region?.displayID == display.displayID ? region?.rect : nil
            regionFrame.hide()
            let picked = await RegionPicker.pick(on: screen, initial: initial)
            if let picked {
                error = nil
                region = CaptureRegion(displayID: display.displayID, rect: picked.integral)
                captureArea = true
            }
            syncRegionFrame()
        }
    }

    func displayName(_ d: SCDisplay) -> String {
        let s = nsScreen(d.displayID)
        return "\(s?.localizedName ?? "Display \(d.displayID)") — \(d.width)×\(d.height)"
    }

    private func nsScreen(_ id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
    }

    func toggleRecording() {
        switch phase {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        case .countdown: cancelCountdown()
        case .saving: break
        }
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        phase = .idle
        overlay.hide()
        camRec.stopRunning()
        syncRegionFrame()
    }

    func handle(_ a: HotkeyAction) {
        switch a {
        case .toggleRecording: toggleRecording()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .cameraMove: cameraChange { $0.corner = $0.corner.next }
        case .cameraShape: cameraChange { $0.shape = $0.shape.next }
        case .cameraToggle: cameraChange { $0.visible.toggle() }
        case .stopRecording: if phase == .recording { Task { await stop() } }
        }
    }

    private var now: Double { hostSeconds() - t0 }

    private func zoomIn() {
        guard phase == .recording else { return }
        guard (zoomKeys.last?.scale ?? 1) <= 1.05 else { return }
        zoomKeys.append(ZoomKey(time: now, scale: style.zoomLevel))
        saveDraft()
    }

    private func zoomOut() {
        guard phase == .recording, (zoomKeys.last?.scale ?? 1) > 1.05 else { return }
        zoomKeys.append(ZoomKey(time: now, scale: 1))
        saveDraft()
    }

    private func cameraChange(_ f: (inout CameraKey) -> Void) {
        guard phase == .recording, usingCamera, var k = cameraKeys.last else { return }
        k.id = UUID()
        k.time = now
        f(&k)
        cameraKeys.append(k)
        overlay.update(corner: k.corner, shape: k.shape, visible: k.visible)
        saveDraft()
    }

    func toggleTest() {
        if testing { stopTest() } else { Task { await startTest() } }
    }

    func startTest() async {
        guard phase == .idle, !testing else { return }
        let cam = !selectedCamera.isEmpty, mic = !selectedMic.isEmpty
        guard cam || mic else { error = "Choose a camera or microphone to test"; return }
        if cam, !(await AVCaptureDevice.requestAccess(for: .video)) { error = "Camera access denied"; return }
        if mic, !(await AVCaptureDevice.requestAccess(for: .audio)) { error = "Microphone access denied"; return }
        let screen = nsScreen(selectedDisplay) ?? NSScreen.main!
        overlay.prepare(on: screen, style: DefaultStyle.load(), corner: startCorner, shape: startShape)
        if cam, let dev = cameras.first(where: { $0.uniqueID == selectedCamera }) {
            do {
                try camRec.configure(device: dev)
                camRec.startRunning()
                overlay.show(on: screen, session: camRec.session, style: DefaultStyle.load(), corner: startCorner, shape: startShape)
                testHasCamera = true
            } catch { self.error = error.localizedDescription }
        }
        if mic, let dev = mics.first(where: { $0.uniqueID == selectedMic }) {
            meter.onLevel = { [weak self] l in
                guard let self else { return }
                self.micLevel = max(l, self.micLevel * 0.85)
                self.overlay.setLevel(self.micLevel)
            }
            do { try meter.start(device: dev); overlay.showMeter() } catch { self.error = error.localizedDescription }
        }
        testing = true
    }

    func stopTest() {
        guard testing else { return }
        testing = false
        testHasCamera = false
        meter.stop()
        meter.onLevel = nil
        overlay.hide()
        camRec.stopRunning()
        micLevel = 0
    }

    func applyTestLayout() {
        if testing { overlay.setLayout(corner: startCorner, shape: startShape) }
    }

    func start() async {
        guard phase == .idle else { return }
        stopTest()
        error = nil
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            error = "Allow Screen Recording for Record123 in System Settings → Privacy & Security, then restart the app."
            return
        }
        usingCamera = !selectedCamera.isEmpty
        usingMic = !selectedMic.isEmpty
        if usingCamera, !(await AVCaptureDevice.requestAccess(for: .video)) { error = "Camera access denied"; return }
        if usingMic, !(await AVCaptureDevice.requestAccess(for: .audio)) { error = "Microphone access denied"; return }
        guard let display = selectedOrMainDisplay() else {
            error = "No display available"; return
        }
        let screen = nsScreen(display.displayID) ?? NSScreen.main!
        let area = captureArea ? activeRegion(for: display.displayID) : nil
        if captureArea, area == nil { error = "Select an area on the chosen display first"; return }
        style = DefaultStyle.load()

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Recording \(f.string(from: Date()))"
        let dir = Paths.root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dir = dir

        var excluded: [CGWindowID] = []
        if usingCamera, let dev = cameras.first(where: { $0.uniqueID == selectedCamera }) {
            do {
                try camRec.configure(device: dev)
                camRec.startRunning()
                overlay.show(on: screen, session: camRec.session, style: style, corner: startCorner, shape: startShape)
                if let id = overlay.windowID { excluded.append(id) }
            } catch { self.error = error.localizedDescription; usingCamera = false }
        }

        regionFrame.hide()
        let count = UserDefaults.standard.object(forKey: "countdown") as? Int ?? 3
        for n in stride(from: count, to: 0, by: -1) {
            phase = .countdown(n)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if phase == .idle { return }
        }
        hiddenWindows = NSApp.windows.filter { !($0 is NSPanel) && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
        hiddenWindows.forEach { $0.orderOut(nil) }

        zoomKeys = []
        cameraKeys = []
        do {
            if usingCamera { camRec.beginWriting(to: dir.appendingPathComponent("camera.mov")) }
            if usingMic, let dev = mics.first(where: { $0.uniqueID == selectedMic }) {
                try micRec.start(device: dev, url: dir.appendingPathComponent("mic.m4a"))
            }
            try await screenRec.start(display: display, region: area, excludingWindowIDs: excluded, url: dir.appendingPathComponent("screen.mov"),
                                      scale: screen.backingScaleFactor)
        } catch {
            await abort(error)
            return
        }
        t0 = await screenRec.waitForFirstFrame(timeout: 2) ?? hostSeconds()
        let captured = area.map { CGRect(x: screen.frame.minX + $0.minX, y: screen.frame.maxY - $0.maxY, width: $0.width, height: $0.height) } ?? screen.frame
        cursor.start(frame: captured, t0: t0)
        if usingCamera {
            cameraKeys = [CameraKey(time: 0, corner: startCorner, shape: startShape)]
        }
        elapsed = 0
        lastDraftSave = 0
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.now
                if self.elapsed - self.lastDraftSave >= 3 { self.saveDraft() }
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        phase = .recording
    }

    private func abort(_ e: Error) async {
        let end = hostSeconds()
        await screenRec.stop(endHostTime: end)
        if usingCamera { await camRec.finish(endHostTime: end) }
        overlay.hide()
        camRec.stopRunning()
        await micRec.stop()
        phase = .idle
        syncRegionFrame()
        error = e.localizedDescription
        showMainWindow()
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .saving
        ticker?.invalidate()
        let end = hostSeconds()
        let duration = end - t0
        let samples = cursor.stop()
        await screenRec.stop(endHostTime: end)
        if usingCamera { await camRec.finish(endHostTime: end) }
        if usingMic { await micRec.stop() }
        overlay.hide()
        camRec.stopRunning()

        guard let dir, screenRec.firstPTS != nil else {
            phase = .idle
            syncRegionFrame()
            error = screenRec.writerError.map { "Recording failed: \($0.localizedDescription)" } ?? "Nothing was recorded"
            showMainWindow()
            return
        }
        guard var p = makeProject(dir: dir, duration: duration) else { return }
        p.incomplete = nil
        p.cursor = samples
        try? ProjectIO.save(p, to: dir)
        projects = ProjectRef.loadAll()
        phase = .idle
        syncRegionFrame()
        showMainWindow()
        open(dir)
    }

    private func makeProject(dir: URL, duration: Double) -> Project? {
        guard let screenFirst = screenRec.firstPTS else { return nil }
        var p = Project(name: dir.lastPathComponent, duration: duration)
        p.screenOffset = screenFirst - t0
        p.screenWidth = Int(screenRec.pixelSize.width)
        p.screenHeight = Int(screenRec.pixelSize.height)
        if usingCamera, let c = camRec.firstPTS { p.cameraFile = "camera.mov"; p.cameraOffset = c - t0 }
        if usingMic, let m = micRec.firstPTS { p.micFile = "mic.m4a"; p.micOffset = m - t0 }
        p.cursor = cursor.snapshot()
        p.zoomSegments = ZoomSegment.from(keys: zoomKeys, duration: duration, easeIn: style.zoomDuration, easeOut: style.zoomDuration)
        p.cameraKeys = cameraKeys
        p.style = style
        p.trimStart = min(max(p.screenOffset, 0), max(duration - 0.2, 0))
        p.trimEnd = duration
        p.incomplete = true
        return p
    }

    private func saveDraft() {
        guard phase == .recording, let dir, let p = makeProject(dir: dir, duration: now) else { return }
        lastDraftSave = now
        try? ProjectIO.save(p, to: dir)
    }

    func recoverProjects() async {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? []
        for d in dirs where fm.fileExists(atPath: d.appendingPathComponent("screen.mov").path) {
            var p = (try? ProjectIO.load(d)) ?? Project(name: d.lastPathComponent, duration: 0)
            guard p.incomplete == true || !fm.fileExists(atPath: Paths.projectFile(d).path) else { continue }
            let asset = AVURLAsset(url: d.appendingPathComponent("screen.mov"))
            guard let dur = try? await asset.load(.duration).seconds, dur > 0.2 else { continue }
            if let t = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await t.load(.naturalSize) {
                p.screenWidth = Int(size.width); p.screenHeight = Int(size.height)
            }
            let end = max(p.screenOffset, 0) + dur
            p.duration = end
            p.trimStart = min(max(p.screenOffset, 0), max(end - 0.2, 0))
            p.trimEnd = end
            if p.cameraFile == nil, fm.fileExists(atPath: d.appendingPathComponent("camera.mov").path) { p.cameraFile = "camera.mov" }
            if p.cameraFile != nil, p.cameraKeys.isEmpty { p.cameraKeys = [CameraKey(time: 0, corner: .bottomRight, shape: .circle)] }
            if p.micFile == nil, fm.fileExists(atPath: d.appendingPathComponent("mic.m4a").path) { p.micFile = "mic.m4a" }
            p.incomplete = nil
            try? ProjectIO.save(p, to: d)
        }
        projects = ProjectRef.loadAll()
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let wins = hiddenWindows.isEmpty ? NSApp.windows.filter { !($0 is NSPanel) && $0.canBecomeMain } : hiddenWindows
        hiddenWindows = []
        for w in wins {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
        if wins.isEmpty { NSWorkspace.shared.open(Bundle.main.bundleURL) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.activate(ignoringOtherApps: true) }
        syncRegionFrame()
    }

    func open(_ dir: URL) {
        guard let p = try? ProjectIO.load(dir) else { error = "Cannot open project"; return }
        editor?.player.pause()
        let m = EditorModel(project: p, dir: dir)
        m.onSaved = { [weak self] in self?.projects = ProjectRef.loadAll() }
        openCancellable = m.$ready.filter { $0 }.first().sink { [weak self] _ in
            self?.editor = m
            self?.openCancellable = nil
        }
        syncRegionFrame()
    }

    func closeEditor() {
        openCancellable = nil
        editor?.finishVoice()
        editor?.flushSave()
        editor?.player.pause()
        editor?.player.replaceCurrentItem(with: nil)
        editor = nil
        cameraBlur = DefaultStyle.load().cameraBlur
        projects = ProjectRef.loadAll()
    }

    func delete(_ ref: ProjectRef) {
        try? FileManager.default.trashItem(at: ref.dir, resultingItemURL: nil)
        projects = ProjectRef.loadAll()
    }

    func moveRecording(_ dragged: ProjectRef, relativeTo target: ProjectRef, after: Bool) {
        guard dragged.id != target.id else { return }
        var list = projects
        list.removeAll { $0.id == dragged.id }
        guard var i = list.firstIndex(where: { $0.id == target.id }) else { return }
        if after { i += 1 }
        list.insert(dragged, at: i)
        ProjectRef.saveOrder(list)
        projects = ProjectRef.loadAll()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var state: AppState?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let state = AppDelegate.state, state.phase != .recording { state.showMainWindow() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = AppDelegate.state else { return .terminateNow }
        state.editor?.finishVoice()
        state.editor?.flushSave()
        state.cancelCountdown()
        guard state.phase == .recording || state.phase == .saving else { return .terminateNow }
        Task { @MainActor in
            await state.stop()
            while state.phase == .saving { try? await Task.sleep(nanoseconds: 100_000_000) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
