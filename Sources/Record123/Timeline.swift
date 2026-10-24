import Foundation
import CoreGraphics

func easeInOut(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * t * (t * (t * 6 - 15) + 10)
}

struct CameraPose {
    var anchor: CGPoint
    var shape: CameraShape
    var alpha: Double
    var pop: Double
}

private struct ZoomPose {
    var l: Double
    var q: CGPoint

    func mix(_ o: ZoomPose, _ w: Double) -> ZoomPose {
        ZoomPose(l: l + (o.l - l) * w, q: CGPoint(x: q.x + (o.q.x - q.x) * w, y: q.y + (o.q.y - q.y) * w))
    }
}

private func softUnit(_ x: Double, knee k: Double = 0.12) -> Double {
    if x < k { return k * exp(x / k - 1) }
    if x > 1 - k { return 1 - k * exp((1 - x) / k - 1) }
    return x
}

struct Timeline {
    static let cursorRate = 120.0

    let segments: [ZoomSegment]
    private let chains: [[ZoomSegment]]
    let cameraKeys: [CameraKey]
    private let cursorStart: Double
    private let cursorX: [Double]
    private let cursorY: [Double]
    let style: Style

    init(project: Project) {
        let c = project.cropRect
        let cursor = project.cursor.map { CursorSample(t: $0.t, x: ($0.x - c.x) / c.w, y: ($0.y - c.y) / c.h) }
        self.init(segments: project.segments, cameraKeys: project.cameraKeys, cursor: cursor, style: project.style)
    }

    init(segments: [ZoomSegment], cameraKeys: [CameraKey], cursor: [CursorSample], style: Style) {
        self.segments = segments
        var chains: [[ZoomSegment]] = []
        var chainEnd = -Double.infinity
        for g in segments.sorted(by: { $0.start < $1.start }) {
            if !chains.isEmpty, g.start < chainEnd + 0.4 {
                chains[chains.count - 1].append(g)
                chainEnd = max(chainEnd, g.end)
            } else {
                chains.append([g])
                chainEnd = g.end
            }
        }
        self.chains = chains
        self.cameraKeys = cameraKeys.sorted { $0.time < $1.time }
        self.style = style
        let (start, xs, ys) = Timeline.resample(cursor, rate: Timeline.cursorRate)
        let tau = style.cursorSmoothing * 0.6
        cursorStart = start
        cursorX = Timeline.smooth(xs, tau: tau, rate: Timeline.cursorRate)
        cursorY = Timeline.smooth(ys, tau: tau, rate: Timeline.cursorRate)
    }

    private static func resample(_ raw: [CursorSample], rate: Double) -> (Double, [Double], [Double]) {
        guard let first = raw.first, let last = raw.last else { return (0, [], []) }
        let n = Int(((last.t - first.t) * rate).rounded(.up)) + 1
        var xs = [Double](repeating: 0, count: n), ys = xs
        let move = 0.0085
        var j = 0
        for i in 0..<n {
            let t = first.t + Double(i) / rate
            while j + 1 < raw.count, raw[j + 1].t <= t { j += 1 }
            let a = raw[j]
            guard j + 1 < raw.count else { xs[i] = a.x; ys[i] = a.y; continue }
            let b = raw[j + 1]
            let from = max(a.t, b.t - move)
            let f = min(max((t - from) / max(b.t - from, 1e-6), 0), 1)
            xs[i] = a.x + (b.x - a.x) * f
            ys[i] = a.y + (b.y - a.y) * f
        }
        return (first.t, xs, ys)
    }

    private static func smooth(_ v: [Double], tau: Double, rate: Double) -> [Double] {
        guard v.count > 1, tau > 0.001 else { return v }
        var v = v
        let a = 1 - exp(-1 / (rate * tau))
        for _ in 0..<2 {
            for i in 1..<v.count { v[i] = v[i - 1] + (v[i] - v[i - 1]) * a }
            for i in stride(from: v.count - 2, through: 0, by: -1) { v[i] = v[i + 1] + (v[i] - v[i + 1]) * a }
        }
        return v
    }

    func cursorPosition(at t: Double) -> CGPoint {
        let n = cursorX.count
        guard n > 1 else { return n == 1 ? CGPoint(x: cursorX[0], y: cursorY[0]) : CGPoint(x: 0.5, y: 0.5) }
        let u = min(max((t - cursorStart) * Timeline.cursorRate, 0), Double(n - 1))
        let i = min(Int(u), n - 2)
        let f = u - Double(i)
        return CGPoint(x: cursorX[i] + (cursorX[i + 1] - cursorX[i]) * f, y: cursorY[i] + (cursorY[i + 1] - cursorY[i]) * f)
    }

    private func fullPose(_ g: ZoomSegment, at t: Double) -> ZoomPose {
        let big = max(g.scale, 1.01)
        let inv = 1 / big
        let f = g.follow ? cursorPosition(at: t) : CGPoint(x: g.fx, y: g.fy)
        let qx = (f.x - 0.5 * inv) / (1 - inv), qy = (f.y - 0.5 * inv) / (1 - inv)
        if g.follow { return ZoomPose(l: log(big), q: CGPoint(x: softUnit(qx), y: softUnit(qy))) }
        return ZoomPose(l: log(big), q: CGPoint(x: min(max(qx, 0), 1), y: min(max(qy, 0), 1)))
    }

    private func chainPose(_ chain: [ZoomSegment], at t: Double) -> ZoomPose {
        var cur = fullPose(chain[0], at: t)
        for i in 1..<chain.count {
            let a = chain[i - 1], b = chain[i]
            let ts = min(a.end, b.start)
            let te = max(ts + 0.1, b.start + max(b.easeIn, 0.05))
            let w = easeInOut((t - ts) / (te - ts))
            if w <= 0 { break }
            cur = cur.mix(fullPose(b, at: t), w)
        }
        return cur
    }

    func zoomScale(at t: Double) -> Double { zoomState(at: t).scale }

    func zoomState(at t: Double) -> (scale: Double, center: CGPoint) {
        let identity = (1.0, CGPoint(x: 0.5, y: 0.5))
        guard let chain = chains.first(where: { t >= $0[0].start - 0.0001 && t <= $0.map(\.end).max()! + 0.0001 }) else { return identity }
        let first = chain[0]
        let last = chain.max { $0.end < $1.end }!
        var easeIn = max(first.easeIn, 0.05), easeOut = max(last.easeOut, 0.05)
        let span = last.end - first.start
        if easeIn + easeOut > span {
            let k = max(span, 0.1) / (easeIn + easeOut)
            easeIn *= k; easeOut *= k
        }
        let p = min(easeInOut((t - first.start) / easeIn), easeInOut((last.end - t) / easeOut))
        guard p > 0.0001 else { return identity }
        let full = chainPose(chain, at: t)
        let inv = exp(-full.l * p)
        let q = CGPoint(x: min(max(full.q.x, 0), 1), y: min(max(full.q.y, 0), 1))
        return (1 / inv, CGPoint(x: q.x * (1 - inv) + 0.5 * inv, y: q.y * (1 - inv) + 0.5 * inv))
    }

    func cameraPose(at t: Double) -> CameraPose? {
        guard let first = cameraKeys.first else { return nil }
        var d = first.resolvedMoveDuration(style.cameraMoveDuration)
        var from = first.anchor, to = from, start = first.time
        func pos(_ at: Double) -> CGPoint {
            let e = easeInOut((at - start) / d)
            return CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
        }
        var cur = first
        var popStart = first.time
        var visStart = first.time
        for k in cameraKeys.dropFirst() where k.time <= t {
            from = pos(k.time)
            to = k.anchor
            start = k.time
            d = k.resolvedMoveDuration(style.cameraMoveDuration)
            if k.shape != cur.shape || k.visible != cur.visible { popStart = k.time }
            if k.visible != cur.visible { visStart = k.time }
            cur = k
        }
        let p = easeInOut((t - popStart) / 0.3)
        let v = easeInOut((t - visStart) / 0.3)
        let alpha: Double
        if cur.visible { alpha = visStart == first.time ? 1 : v }
        else { alpha = visStart == first.time ? 0 : 1 - v }
        if alpha <= 0.001 { return nil }
        return CameraPose(anchor: pos(t), shape: cur.shape, alpha: alpha, pop: p)
    }
}
