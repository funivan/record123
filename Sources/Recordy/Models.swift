import Foundation
import SwiftUI

enum CameraShape: String, Codable, CaseIterable, Identifiable {
    case circle, square, wide, tall
    var id: String { rawValue }
    var label: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Rounded square"
        case .wide: return "Rectangle"
        case .tall: return "Portrait"
        }
    }
    var next: CameraShape {
        let all = CameraShape.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    func size(base d: Double) -> CGSize {
        switch self {
        case .circle, .square: return CGSize(width: d, height: d)
        case .wide: return CGSize(width: d * 1.7, height: d * 0.96)
        case .tall: return CGSize(width: d * 0.8, height: d * 1.25)
        }
    }
    func radius(for size: CGSize) -> Double {
        switch self {
        case .circle: return min(size.width, size.height) / 2
        case .square: return min(size.width, size.height) * 0.24
        case .wide: return size.height * 0.14
        case .tall: return size.width * 0.2
        }
    }
}

enum CameraCorner: Int, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomRight, bottomLeft
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        }
    }
    var shortLabel: String {
        switch self {
        case .topLeft: return "TL"
        case .topRight: return "TR"
        case .bottomRight: return "BR"
        case .bottomLeft: return "BL"
        }
    }
    var next: CameraCorner { CameraCorner(rawValue: (rawValue + 1) % 4)! }
    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        }
    }
}

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    var color: Color {
        get { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
        set {
            let c = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
            r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent
        }
    }
}

enum BgPattern: String, Codable, CaseIterable, Identifiable {
    case none, dots, grid, lines, grain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .dots: return "Dots"
        case .grid: return "Grid"
        case .lines: return "Lines"
        case .grain: return "Grain"
        }
    }
}

enum BackgroundMode: String, Codable, CaseIterable, Identifiable {
    case wallpaper, gradient, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gradient: return "Gradient"
        case .wallpaper: return "Wallpaper"
        case .image: return "Image"
        }
    }
    var icon: String {
        switch self {
        case .gradient: return "square.lefthalf.filled"
        case .wallpaper: return "photo.fill"
        case .image: return "photo.badge.plus"
        }
    }
}

struct Style: Codable, Equatable {
    var bgColor1 = RGBA(r: 1.0, g: 0.36, b: 0.2)
    var bgColor2 = RGBA(r: 0.55, g: 0.16, b: 0.5)
    var bgGradient = true
    var bgMode = BackgroundMode.wallpaper
    var bgAngle = 135.0
    var padding = 0.07
    var cornerRadius = 0.025
    var shadow = 0.55
    var resolution = 0
    var cameraSize = 0.24
    var cameraBorder = 4.0
    var cameraBorderColor = RGBA(r: 1, g: 1, b: 1)
    var cameraMirror = true
    var cameraBlur = false
    var zoomLevel = 2.0
    var zoomDuration = 0.9
    var cameraMoveDuration = 0.5
    var cursorSmoothing = 0.35
    var screenBorder = 0.0
    var screenBorderColor = RGBA(r: 1, g: 1, b: 1, a: 0.6)
    var bgImageFile: String? = Wallpapers.defaultName
    var bgPattern = BgPattern.none

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bgColor1 = c.opt(.bgColor1, bgColor1)
        bgColor2 = c.opt(.bgColor2, bgColor2)
        bgGradient = c.opt(.bgGradient, bgGradient)
        bgAngle = c.opt(.bgAngle, bgAngle)
        padding = c.opt(.padding, padding)
        cornerRadius = c.opt(.cornerRadius, cornerRadius)
        shadow = c.opt(.shadow, shadow)
        resolution = c.opt(.resolution, resolution)
        cameraSize = c.opt(.cameraSize, cameraSize)
        cameraBorder = c.opt(.cameraBorder, cameraBorder)
        cameraBorderColor = c.opt(.cameraBorderColor, cameraBorderColor)
        cameraMirror = c.opt(.cameraMirror, cameraMirror)
        cameraBlur = c.opt(.cameraBlur, cameraBlur)
        zoomLevel = c.opt(.zoomLevel, zoomLevel)
        zoomDuration = c.opt(.zoomDuration, zoomDuration)
        cameraMoveDuration = c.opt(.cameraMoveDuration, cameraMoveDuration)
        cursorSmoothing = c.opt(.cursorSmoothing, cursorSmoothing)
        screenBorder = c.opt(.screenBorder, screenBorder)
        screenBorderColor = c.opt(.screenBorderColor, screenBorderColor)
        bgImageFile = try? c.decodeIfPresent(String.self, forKey: .bgImageFile)
        bgMode = c.opt(.bgMode, bgImageFile != nil ? .image : .gradient)
        if !bgGradient && bgImageFile == nil {
            bgColor2 = bgColor1
            bgGradient = true
        }
        bgPattern = bgMode == .gradient ? c.opt(.bgPattern, bgPattern) : .none
    }

    mutating func selectBackground(_ mode: BackgroundMode) {
        bgMode = mode
        bgImageFile = nil
        bgGradient = true
        if mode != .gradient { bgPattern = .none }
    }
}

extension KeyedDecodingContainer {
    func opt<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

enum Wallpapers {
    static let defaultName = "27-ukraine-halftone.jpg"
    static var dir: URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Wallpapers"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Wallpapers")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static var all: [URL] {
        guard let dir else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

struct BackgroundPreset: Identifiable {
    let name: String
    let c1: RGBA, c2: RGBA
    var id: String { name }
    static let all: [BackgroundPreset] = [
        .init(name: "Signal", c1: RGBA(r: 1.0, g: 0.36, b: 0.2), c2: RGBA(r: 0.55, g: 0.16, b: 0.5)),
        .init(name: "Bone", c1: RGBA(r: 0.96, g: 0.94, b: 0.9), c2: RGBA(r: 0.88, g: 0.84, b: 0.77)),
        .init(name: "Graphite", c1: RGBA(r: 0.17, g: 0.17, b: 0.2), c2: RGBA(r: 0.05, g: 0.05, b: 0.07)),
        .init(name: "Clay", c1: RGBA(r: 0.78, g: 0.42, b: 0.3), c2: RGBA(r: 0.45, g: 0.2, b: 0.17)),
        .init(name: "Lichen", c1: RGBA(r: 0.74, g: 0.8, b: 0.55), c2: RGBA(r: 0.3, g: 0.42, b: 0.3)),
        .init(name: "Cobalt", c1: RGBA(r: 0.1, g: 0.2, b: 0.75), c2: RGBA(r: 0.03, g: 0.07, b: 0.3)),
    ]
}


struct ZoomKey: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Double
    var scale: Double
    var follow = true
    var fx = 0.5
    var fy = 0.5
}

struct ZoomSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var scale: Double
    var easeIn = 0.7
    var easeOut = 0.7
    var follow = true
    var fx = 0.5
    var fy = 0.5

    static func from(keys: [ZoomKey], duration: Double, easeIn: Double, easeOut: Double) -> [ZoomSegment] {
        var out: [ZoomSegment] = []
        var open: ZoomSegment?
        func close(at t: Double) {
            guard var s = open else { return }
            s.end = max(t, s.start + 0.4)
            out.append(s)
            open = nil
        }
        for k in keys.sorted(by: { $0.time < $1.time }) {
            if k.scale > 1.05 {
                if let o = open, abs(o.scale - k.scale) < 0.01 { continue }
                close(at: k.time)
                open = ZoomSegment(start: k.time, end: duration, scale: k.scale, easeIn: easeIn, easeOut: easeOut, follow: k.follow, fx: k.fx, fy: k.fy)
            } else {
                close(at: k.time)
            }
        }
        close(at: duration)
        return out
    }
}

struct CameraKey: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Double
    var corner: CameraCorner
    var shape: CameraShape
    var visible = true
    var x: Double?
    var y: Double?
    var moveDuration: Double?

    var anchor: CGPoint {
        if let x, let y { return CGPoint(x: x, y: y) }
        return corner.unit
    }

    func resolvedMoveDuration(_ fallback: Double) -> Double { max(moveDuration ?? fallback, 0.05) }
}

enum AudioKind: String, Codable {
    case system, mic, music, voice
    var label: String {
        switch self {
        case .system: return "System audio"
        case .mic: return "Microphone"
        case .music: return "Music"
        case .voice: return "Voice"
        }
    }
    var icon: String {
        switch self {
        case .system: return "speaker.wave.2.fill"
        case .mic: return "mic.fill"
        case .music: return "music.note"
        case .voice: return "waveform"
        }
    }
}

struct AudioClip: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: AudioKind
    var file: String
    var start: Double
    var srcStart = 0.0
    var duration: Double
    var volume = 1.0
    var muted = false
    var name: String?

    var end: Double { start + duration }
    var title: String { name ?? kind.label }
}

enum CropHandle: String, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    static let resizing = allCases.filter { $0 != .move }

    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

    func anchor(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        case .move: return CGPoint(x: r.midX, y: r.midY)
        }
    }
}

struct CropRect: Codable, Equatable {
    var x: Double, y: Double, w: Double, h: Double

    static let full = CropRect(x: 0, y: 0, w: 1, h: 1)

    func isFull(tolerance: Double = 0.001) -> Bool {
        abs(x) <= tolerance && abs(y) <= tolerance && abs(w - 1) <= tolerance && abs(h - 1) <= tolerance
    }

    func clamped() -> CropRect {
        let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
        let cw = min(max(w, 0), 1 - cx), ch = min(max(h, 0), 1 - cy)
        guard cw > 0.0001, ch > 0.0001 else { return .full }
        return CropRect(x: cx, y: cy, w: cw, h: ch)
    }

    static func dragged(_ base: CropRect, handle: CropHandle, by delta: CGPoint, minSize: CGSize) -> CropRect {
        var l = base.x, t = base.y, r = base.x + base.w, b = base.y + base.h
        let minW = min(max(Double(minSize.width), 0), 1), minH = min(max(Double(minSize.height), 0), 1)
        let dx = Double(delta.x), dy = Double(delta.y)
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        switch handle {
        case .move:
            return CropRect(x: clamp(base.x + dx, 0, max(1 - base.w, 0)), y: clamp(base.y + dy, 0, max(1 - base.h, 0)), w: base.w, h: base.h)
        default:
            if handle.movesLeft { l = clamp(l + dx, 0, max(r - minW, 0)) }
            if handle.movesRight { r = clamp(r + dx, min(l + minW, 1), 1) }
            if handle.movesTop { t = clamp(t + dy, 0, max(b - minH, 0)) }
            if handle.movesBottom { b = clamp(b + dy, min(t + minH, 1), 1) }
        }
        return CropRect(x: l, y: t, w: r - l, h: b - t)
    }
}

struct CursorSample: Codable {
    var t: Double
    var x: Double
    var y: Double
}

struct Project: Codable, Identifiable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var duration: Double
    var screenFile = "screen.mov"
    var screenOffset = 0.0
    var screenWidth = 1920
    var screenHeight = 1080
    var cameraFile: String?
    var cameraOffset = 0.0
    var micFile: String?
    var micOffset = 0.0
    var audioClips: [AudioClip]?
    var cursor: [CursorSample] = []
    var zoomKeys: [ZoomKey] = []
    var zoomSegments: [ZoomSegment]?
    var cameraKeys: [CameraKey] = []
    var style = Style()
    var trimStart = 0.0
    var trimEnd = 0.0
    var incomplete: Bool?
    var crop: CropRect?

    mutating func migrateZoom() {
        guard zoomSegments == nil else { return }
        zoomSegments = ZoomSegment.from(keys: zoomKeys, duration: duration, easeIn: style.zoomDuration, easeOut: style.zoomDuration)
        zoomKeys = []
    }

    var segments: [ZoomSegment] { zoomSegments ?? [] }

    var sourceSize: CGSize { CGSize(width: screenWidth, height: screenHeight) }

    var cropRect: CropRect { (crop ?? .full).clamped() }

    var croppedSize: CGSize {
        let c = cropRect
        return CGSize(width: c.w * Double(screenWidth), height: c.h * Double(screenHeight))
    }

    var minCropSize: CGSize {
        CGSize(width: min(64 / Double(max(screenWidth, 1)), 1), height: min(64 / Double(max(screenHeight, 1)), 1))
    }

    var trimmedDuration: Double { max(0.1, trimEnd - trimStart) }
}

enum Paths {
    static var root: URL {
        let u = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordy")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func projectFile(_ dir: URL) -> URL { dir.appendingPathComponent("project.json") }
}

struct ProjectRef: Identifiable, Hashable {
    let dir: URL
    let name: String
    let createdAt: Date
    let duration: Double
    var id: URL { dir }

    static let orderKey = "recordingsOrder"

    static func loadAll() -> [ProjectRef] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? []
        let order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return dirs.compactMap { d in
            guard let p = try? ProjectIO.load(d) else { return nil }
            return ProjectRef(dir: d, name: p.name, createdAt: p.createdAt, duration: p.trimmedDuration)
        }.sorted { a, b in
            switch (rank[a.dir.lastPathComponent], rank[b.dir.lastPathComponent]) {
            case let (x?, y?): return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return a.createdAt > b.createdAt
            }
        }
    }

    static func saveOrder(_ refs: [ProjectRef]) {
        UserDefaults.standard.set(refs.map { $0.dir.lastPathComponent }, forKey: orderKey)
    }
}

enum ProjectIO {
    static func load(_ dir: URL) throws -> Project {
        let data = try Data(contentsOf: Paths.projectFile(dir))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var p = try dec.decode(Project.self, from: data)
        p.migrateZoom()
        return p
    }
    static func save(_ p: Project, to dir: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        try enc.encode(p).write(to: Paths.projectFile(dir), options: .atomic)
    }
}

enum BackgroundImages {
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordy/Backgrounds")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func url(_ name: String, projectDir: URL) -> URL? {
        let candidates = [projectDir, dir, Wallpapers.dir].compactMap { $0 }.map { $0.appendingPathComponent(name) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func importImage(_ src: URL) -> String? {
        let name = "background-\(Int(Date().timeIntervalSince1970)).\(src.pathExtension)"
        do { try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(name)) } catch { return nil }
        return name
    }
}

extension Style {
    mutating func resetZoom() {
        let d = Style()
        zoomLevel = d.zoomLevel
        zoomDuration = d.zoomDuration
        cursorSmoothing = d.cursorSmoothing
    }
}

enum DefaultStyle {
    static let key = "defaultStyle"
    static func load() -> Style {
        guard let d = UserDefaults.standard.data(forKey: key), var s = try? JSONDecoder().decode(Style.self, from: d) else { return Style() }
        s.resetZoom()
        return s
    }
    static func save(_ s: Style) {
        var s = s
        s.resetZoom()
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }
}
