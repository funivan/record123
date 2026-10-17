import Testing
import Foundation
import CoreGraphics
@testable import Recordy

struct EditorCropTests {
    private func project(width: Int = 1920, height: Int = 1080, crop: CropRect? = nil) -> Project {
        var p = Project(name: "t", duration: 10)
        p.screenWidth = width
        p.screenHeight = height
        p.trimEnd = 10
        p.crop = crop
        return p
    }

    private func legacyJSON(width: Int, height: Int, style: [String: Any] = [:]) throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        var obj = try #require(JSONSerialization.jsonObject(with: enc.encode(project(width: width, height: height))) as? [String: Any])
        obj.removeValue(forKey: "crop")
        var st = try #require(obj["style"] as? [String: Any])
        for (k, v) in style { st[k] = v }
        obj["style"] = st
        return String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: Data(json.utf8))
    }

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    private func expect(_ r: CropRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(close(r.x, x) && close(r.y, y) && close(r.w, w) && close(r.h, h), "got \(r)", sourceLocation: sourceLocation)
    }

    private let minSize = CGSize(width: 64.0 / 1920, height: 64.0 / 1080)

    @Test("Given a new recording that was never cropped, then the whole screen is shown and the video has the size of the recorded screen")
    func newRecordingNotCropped() throws {
        let json = try legacyJSON(width: 1920, height: 1080)
        let p = try decode(Project.self, json)
        #expect(p.crop == nil)
        #expect(p.cropRect == .full)
        #expect(p.croppedSize == CGSize(width: 1920, height: 1080))
        #expect(outputSize(for: p) == CGSize(width: 1920, height: 1080))
    }

    @Test("Given an odd sized recorded screen and no crop, then the video size is the screen size rounded to even numbers")
    func oddSourceRoundsToEven() {
        let p = project(width: 1921, height: 1081)
        let s = outputSize(for: p)
        #expect(Int(s.width) % 2 == 0 && Int(s.height) % 2 == 0)
        #expect(abs(s.width - 1921) <= 1 && abs(s.height - 1081) <= 1)
    }

    @Test("Given a recording saved with the aspect set to 16:9 before this change, when it is opened, then it opens without an error and has the shape of the recorded screen")
    func legacyAspectKeyIgnored() throws {
        let json = try legacyJSON(width: 1000, height: 1000, style: ["aspect": "wide16x9"])
        #expect(json.contains("wide16x9"))
        let p = try decode(Project.self, json)
        #expect(outputSize(for: p) == CGSize(width: 1000, height: 1000))
        let style = try decode(Style.self, #"{"aspect":"vertical9x16","padding":0.2}"#)
        #expect(style.padding == 0.2)
    }

    @Test("Given a 1920 by 1080 recording cropped from the top quarter at native resolution, then the video is 1920 by 810")
    func topQuarterCropSize() {
        let p = project(crop: CropRect(x: 0, y: 0.25, w: 1, h: 0.75))
        #expect(p.croppedSize == CGSize(width: 1920, height: 810))
        #expect(outputSize(for: p) == CGSize(width: 1920, height: 810))
    }

    @Test("Given a cropped recording and the resolution set to 1080p, then the shorter side is 1080 and the longer side follows the crop, rounded to even")
    func resolutionAppliesToCrop() {
        var p = project(crop: CropRect(x: 0, y: 0.25, w: 1, h: 0.75))
        p.style.resolution = 1080
        #expect(outputSize(for: p) == CGSize(width: 2560, height: 1080))
        var q = project(crop: CropRect(x: 0.1, y: 0.1, w: 0.3, h: 0.7))
        q.style.resolution = 1080
        let s = outputSize(for: q)
        #expect(s.width == 1080)
        #expect(Int(s.height) % 2 == 0)
        let ratio = (0.3 * 1920) / (0.7 * 1080)
        #expect(abs(s.height - 1080 / ratio) <= 1)
    }

    @Test("Given a very thin crop, then the video size is never below 2 pixels")
    func minimumOutputSize() {
        let p = project(crop: CropRect(x: 0, y: 0, w: 0.001, h: 0.001))
        let s = outputSize(for: p)
        #expect(s.width >= 2 && s.height >= 2)
    }

    @Test("Given a cropped recording with no spacing, then the content fills the whole video without bars")
    func contentRectFillsOutput() {
        var p = project(crop: CropRect(x: 0, y: 0.25, w: 1, h: 0.75))
        p.style.padding = 0
        let out = outputSize(for: p)
        let r = Compositor.contentRect(project: p, out: out)
        #expect(r == CGRect(origin: .zero, size: out))
        var q = project(crop: CropRect(x: 0.2, y: 0.3, w: 0.4, h: 0.5))
        q.style.padding = 0
        q.style.resolution = 720
        let o2 = outputSize(for: q)
        let r2 = Compositor.contentRect(project: q, out: o2)
        #expect(abs(r2.width - o2.width) <= 1 && abs(r2.height - o2.height) <= 1)
    }

    @Test("Given an uncropped recording and a zoom, then the visible region equals the old zoom math")
    func sourceRectMatchesOldMath() {
        let frame = CGSize(width: 1920, height: 1080)
        for scale in [1.0, 1.5, 2.0, 3.7] {
            for c in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.9, y: 0.1)] {
                let vw = frame.width / scale, vh = frame.height / scale
                let x0 = min(max(c.x * frame.width - vw / 2, 0), frame.width - vw)
                let y0 = min(max(c.y * frame.height - vh / 2, 0), frame.height - vh)
                let r = Compositor.sourceRect(crop: .full, zoomScale: scale, zoomCenter: c, frame: frame)
                #expect(close(r.minX, x0) && close(r.minY, y0) && close(r.width, vw) && close(r.height, vh), "scale \(scale) center \(c)")
            }
        }
    }

    @Test("Given a cropped recording without zoom, then the visible region is exactly the crop in pixels")
    func sourceRectScaleOneIsCrop() {
        let crop = CropRect(x: 0.25, y: 0.5, w: 0.5, h: 0.25)
        let r = Compositor.sourceRect(crop: crop, zoomScale: 1, zoomCenter: CGPoint(x: 0.5, y: 0.5), frame: CGSize(width: 1920, height: 1080))
        #expect(r == CGRect(x: 480, y: 540, width: 960, height: 270))
    }

    @Test("Given a cropped recording and a zoom centered at an edge, then the zoom stays inside the cropped area")
    func sourceRectZoomStaysInsideCrop() {
        let crop = CropRect(x: 0.25, y: 0.5, w: 0.5, h: 0.25)
        let frame = CGSize(width: 1920, height: 1080)
        let area = CGRect(x: 480, y: 540, width: 960, height: 270)
        for scale in [1.0, 2.0, 4.0] {
            for c in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: -3, y: 4)] {
                let r = Compositor.sourceRect(crop: crop, zoomScale: scale, zoomCenter: c, frame: frame)
                #expect(close(r.width, area.width / scale) && close(r.height, area.height / scale))
                #expect(r.minX >= area.minX - 1e-9 && r.maxX <= area.maxX + 1e-9 && r.minY >= area.minY - 1e-9 && r.maxY <= area.maxY + 1e-9, "scale \(scale) center \(c) got \(r)")
            }
        }
        let corner = Compositor.sourceRect(crop: crop, zoomScale: 2, zoomCenter: CGPoint(x: 0, y: 0), frame: frame)
        #expect(corner.origin == area.origin)
        let center = Compositor.sourceRect(crop: crop, zoomScale: 2, zoomCenter: CGPoint(x: 0.5, y: 0.5), frame: frame)
        #expect(close(center.midX, area.midX) && close(center.midY, area.midY))
    }

    @Test("Given a cropped recording with a following zoom, then a cursor at the center of the crop is at the center of the cropped area")
    func timelineCursorInCropSpace() {
        var p = project(crop: CropRect(x: 0.2, y: 0.4, w: 0.4, h: 0.2))
        p.cursor = (0..<10).map { CursorSample(t: Double($0) / Timeline.cursorRate, x: 0.4, y: 0.5) }
        let pos = Timeline(project: p).cursorPosition(at: 0)
        #expect(close(pos.x, 0.5) && close(pos.y, 0.5))
        p.cursor = (0..<10).map { CursorSample(t: Double($0) / Timeline.cursorRate, x: 0.2, y: 0.6) }
        let corner = Timeline(project: p).cursorPosition(at: 0)
        #expect(close(corner.x, 0) && close(corner.y, 1))
    }

    @Test("Given an uncropped recording, then the cursor positions are unchanged")
    func timelineCursorUncropped() {
        var p = project()
        p.cursor = (0..<10).map { CursorSample(t: Double($0) / Timeline.cursorRate, x: 0.3, y: 0.7) }
        let pos = Timeline(project: p).cursorPosition(at: 0)
        #expect(close(pos.x, 0.3) && close(pos.y, 0.7))
    }

    @Test("Given crop mode, when the user drags the top edge down by a quarter, then the top quarter is cut and the width is unchanged")
    func dragTopEdge() {
        let r = CropRect.dragged(.full, handle: .top, by: CGPoint(x: 0.4, y: 0.25), minSize: minSize)
        expect(r, 0, 0.25, 1, 0.75)
    }

    @Test("Given crop mode, when the user drags the bottom right corner up and left, then only width and height change")
    func dragBottomRightCorner() {
        let base = CropRect(x: 0.1, y: 0.2, w: 0.8, h: 0.7)
        let r = CropRect.dragged(base, handle: .bottomRight, by: CGPoint(x: -0.2, y: -0.3), minSize: minSize)
        expect(r, 0.1, 0.2, 0.6, 0.4)
    }

    @Test("Given crop mode, when the user drags each edge handle, then only that edge moves")
    func dragEachEdge() {
        let base = CropRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
        let d = CGPoint(x: 0.1, y: 0.1)
        expect(CropRect.dragged(base, handle: .left, by: d, minSize: minSize), 0.3, 0.2, 0.5, 0.6)
        expect(CropRect.dragged(base, handle: .right, by: d, minSize: minSize), 0.2, 0.2, 0.7, 0.6)
        expect(CropRect.dragged(base, handle: .top, by: d, minSize: minSize), 0.2, 0.3, 0.6, 0.5)
        expect(CropRect.dragged(base, handle: .bottom, by: d, minSize: minSize), 0.2, 0.2, 0.6, 0.7)
        expect(CropRect.dragged(base, handle: .topLeft, by: d, minSize: minSize), 0.3, 0.3, 0.5, 0.5)
        expect(CropRect.dragged(base, handle: .topRight, by: d, minSize: minSize), 0.2, 0.3, 0.7, 0.5)
        expect(CropRect.dragged(base, handle: .bottomLeft, by: d, minSize: minSize), 0.3, 0.2, 0.5, 0.7)
    }

    @Test("Given crop mode with a crop smaller than the screen, when the user drags inside the frame, then it moves without changing size and stays inside the screen")
    func dragMoveKeepsSizeAndStaysInside() {
        let base = CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.4)
        expect(CropRect.dragged(base, handle: .move, by: CGPoint(x: 0.2, y: 0.3), minSize: minSize), 0.3, 0.4, 0.5, 0.4)
        expect(CropRect.dragged(base, handle: .move, by: CGPoint(x: 5, y: 5), minSize: minSize), 0.5, 0.6, 0.5, 0.4)
        expect(CropRect.dragged(base, handle: .move, by: CGPoint(x: -5, y: -5), minSize: minSize), 0, 0, 0.5, 0.4)
        expect(CropRect.dragged(.full, handle: .move, by: CGPoint(x: 0.3, y: 0.3), minSize: minSize), 0, 0, 1, 1)
    }

    @Test("Given crop mode, when the user drags an edge past the border of the screen, then the edge stops at the border")
    func dragPastBorder() {
        let base = CropRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
        let big = CGPoint(x: 9, y: 9)
        let small = CGPoint(x: -9, y: -9)
        expect(CropRect.dragged(base, handle: .left, by: small, minSize: minSize), 0, 0.2, 0.8, 0.6)
        expect(CropRect.dragged(base, handle: .top, by: small, minSize: minSize), 0.2, 0, 0.6, 0.8)
        expect(CropRect.dragged(base, handle: .right, by: big, minSize: minSize), 0.2, 0.2, 0.8, 0.6)
        expect(CropRect.dragged(base, handle: .bottom, by: big, minSize: minSize), 0.2, 0.2, 0.6, 0.8)
        expect(CropRect.dragged(base, handle: .topLeft, by: small, minSize: minSize), 0, 0, 0.8, 0.8)
        expect(CropRect.dragged(base, handle: .bottomRight, by: big, minSize: minSize), 0.2, 0.2, 0.8, 0.8)
    }

    @Test("Given crop mode, when the user drags an edge past the opposite edge, then the crop stays at least 64 by 64 pixels and does not flip")
    func dragPastOppositeEdge() {
        let base = CropRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
        let big = CGPoint(x: 9, y: 9)
        let small = CGPoint(x: -9, y: -9)
        let l = CropRect.dragged(base, handle: .left, by: big, minSize: minSize)
        #expect(close(l.w, minSize.width) && close(l.x + l.w, 0.8))
        let r = CropRect.dragged(base, handle: .right, by: small, minSize: minSize)
        #expect(close(r.w, minSize.width) && close(r.x, 0.2))
        let t = CropRect.dragged(base, handle: .top, by: big, minSize: minSize)
        #expect(close(t.h, minSize.height) && close(t.y + t.h, 0.8))
        let b = CropRect.dragged(base, handle: .bottom, by: small, minSize: minSize)
        #expect(close(b.h, minSize.height) && close(b.y, 0.2))
        let corner = CropRect.dragged(base, handle: .topLeft, by: big, minSize: minSize)
        #expect(close(corner.w, minSize.width) && close(corner.h, minSize.height) && close(corner.x + corner.w, 0.8) && close(corner.y + corner.h, 0.8))
        let pixelsW = l.w * 1920, pixelsH = t.h * 1080
        #expect(pixelsW >= 64 - 1e-6 && pixelsH >= 64 - 1e-6)
    }

    @Test("Given any sequence of drags, then the crop stays inside the unit square and above the minimum size")
    func dragInvariants() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var r = CropRect.full
            for _ in 0..<5 {
                let h = CropHandle.allCases.randomElement(using: &rng)!
                let d = CGPoint(x: Double.random(in: -1.5...1.5, using: &rng), y: Double.random(in: -1.5...1.5, using: &rng))
                r = CropRect.dragged(r, handle: h, by: d, minSize: minSize)
                #expect(r.x >= -1e-9 && r.y >= -1e-9 && r.x + r.w <= 1 + 1e-9 && r.y + r.h <= 1 + 1e-9)
                #expect(r.w >= minSize.width - 1e-9 && r.h >= minSize.height - 1e-9)
            }
        }
    }

    @Test("Given a recorded screen, then the minimum crop size is 64 source pixels per side")
    func minCropSizeIs64Pixels() {
        let p = project(width: 1920, height: 1080)
        #expect(close(p.minCropSize.width * 1920, 64) && close(p.minCropSize.height * 1080, 64))
        let tiny = project(width: 40, height: 40)
        #expect(tiny.minCropSize == CGSize(width: 1, height: 1))
    }

    @Test("Given crop values outside the screen or degenerate, then the crop is clamped or falls back to the whole screen")
    func clampedCrop() {
        expect(CropRect(x: -0.5, y: 0.5, w: 2, h: 0.8).clamped(), 0, 0.5, 1, 0.5)
        #expect(CropRect(x: 0.5, y: 0.5, w: 0, h: 0.2).clamped() == .full)
        #expect(project(crop: CropRect(x: 2, y: 2, w: 1, h: 1)).cropRect == .full)
    }

    @Test("Given a crop within 0.001 of the whole screen, then it counts as full")
    func fullTolerance() {
        #expect(CropRect(x: 0.0005, y: 0, w: 0.9995, h: 1).isFull())
        #expect(!CropRect(x: 0.01, y: 0, w: 0.99, h: 1).isFull())
        #expect(CropRect.full.isFull())
    }

    @Test("Given a cropped project is saved and loaded, then the crop is kept; and the style carries no crop")
    func cropStoredInProjectNotStyle() throws {
        let crop = CropRect(x: 0.1, y: 0.2, w: 0.5, h: 0.6)
        let p = project(crop: crop)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(p)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(Project.self, from: data).crop == crop)
        let styleJSON = String(decoding: try JSONEncoder().encode(p.style), as: UTF8.self)
        #expect(!styleJSON.contains("crop"))
        #expect(!styleJSON.contains("aspect"))
    }

    @Test("Given a project saved to disk, when it is opened again, then it is still cropped")
    func cropSurvivesDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recordy-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crop = CropRect(x: 0, y: 0.25, w: 1, h: 0.75)
        try ProjectIO.save(project(crop: crop), to: dir)
        #expect(try ProjectIO.load(dir).crop == crop)
        try ProjectIO.save(project(), to: dir)
        #expect(try ProjectIO.load(dir).crop == nil)
    }

    @Test("Given the style is saved as the default, then a new style loaded from it has no crop and a new project is not cropped")
    func defaultStyleCarriesNoCrop() {
        let key = DefaultStyle.key
        let previous = UserDefaults.standard.data(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let cropped = project(crop: CropRect(x: 0, y: 0.25, w: 1, h: 0.75))
        DefaultStyle.save(cropped.style)
        var fresh = Project(name: "new", duration: 3)
        fresh.style = DefaultStyle.load()
        #expect(fresh.crop == nil)
        #expect(fresh.cropRect == .full)
        #expect(DefaultStyle.load() == cropped.style.withoutZoom())
    }
}

private extension Style {
    func withoutZoom() -> Style { var s = self; s.resetZoom(); return s }
}

@MainActor
struct EditorCropModelTests {
    private func makeModel(crop: CropRect? = nil) throws -> (EditorModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recordy-crop-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var p = Project(name: "t", duration: 10)
        p.trimEnd = 10
        p.crop = crop
        return (EditorModel(project: p, dir: dir), dir)
    }

    private let part = CropRect(x: 0, y: 0.25, w: 1, h: 0.75)

    @Test("Given crop mode, when the user chooses the whole screen or a crop within tolerance and clicks Done, then no crop is stored and crop mode closes")
    func fullStoresNil() throws {
        let (m, dir) = try makeModel(crop: part)
        defer { try? FileManager.default.removeItem(at: dir) }
        m.beginCrop()
        #expect(m.croppingArea)
        m.setCrop(.full)
        #expect(m.project.crop == nil)
        #expect(!m.croppingArea)
        m.beginCrop()
        m.setCrop(CropRect(x: 0.0004, y: 0, w: 0.9996, h: 1))
        #expect(m.project.crop == nil)
    }

    @Test("Given crop mode, when the user clicks Done with a smaller area, then it is stored and crop mode closes")
    func setStoresCrop() throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.beginCrop()
        #expect(m.croppingArea)
        m.setCrop(part)
        #expect(m.project.crop == part)
        #expect(!m.croppingArea)
        #expect(outputSize(for: m.project) == CGSize(width: 1920, height: 810))
    }

    @Test("Given crop mode, when the user clicks Cancel, then the crop is unchanged and crop mode closes")
    func cancelKeepsCrop() throws {
        let (m, dir) = try makeModel(crop: part)
        defer { try? FileManager.default.removeItem(at: dir) }
        m.beginCrop()
        m.cancelCrop()
        #expect(m.project.crop == part)
        #expect(!m.croppingArea)
    }

    @Test("Given a cropped recording, when the user clicks Reset crop, then no crop is stored")
    func resetClearsCrop() throws {
        let (m, dir) = try makeModel(crop: part)
        defer { try? FileManager.default.removeItem(at: dir) }
        m.resetCrop()
        #expect(m.project.crop == nil)
        #expect(!m.croppingArea)
    }

    @Test("Given crop mode, then play is a no-op, and picking a focus is cancelled")
    func cropModeBlocksPlayback() throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.pickingFocus = true
        m.beginCrop()
        #expect(!m.pickingFocus)
        m.togglePlay()
        #expect(!m.isPlaying)
    }

    @Test("Given the user cropped the recording, when they press Command Z, then the previous crop is back; and redo applies it again")
    func undoRestoresPreviousCrop() throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let second = CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        m.setCrop(part)
        m.setCrop(second)
        #expect(m.project.crop == second)
        m.undo()
        #expect(m.project.crop == part)
        m.undo()
        #expect(m.project.crop == nil)
        m.redo()
        #expect(m.project.crop == part)
    }

    @Test("Given Done with an unchanged crop, then the project is not modified and no undo step is added")
    func unchangedCropAddsNoUndoStep() throws {
        let (m, dir) = try makeModel(crop: part)
        defer { try? FileManager.default.removeItem(at: dir) }
        m.beginCrop()
        m.setCrop(part)
        #expect(!m.croppingArea)
        m.undo()
        #expect(m.project.crop == part)
    }
}
