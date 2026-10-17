import SwiftUI
import AVFoundation

struct CropEditorView: View {
    @ObservedObject var model: EditorModel
    @State private var draft: CropRect
    @State private var dragBase: CropRect?
    @State private var still: CGImage?

    private let handleSize: CGFloat = 10
    private let space = "crop.canvas"

    init(model: EditorModel) {
        self.model = model
        _draft = State(initialValue: model.project.cropRect)
    }

    var body: some View {
        GeometryReader { geo in
            let size = fitted(in: geo.size)
            canvas(size)
                .frame(width: size.width, height: size.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) { toolbar }
        .task { still = await loadStill() }
    }

    private func fitted(in available: CGSize) -> CGSize {
        let ar = Double(model.project.screenWidth) / Double(max(model.project.screenHeight, 1))
        var w = available.width, h = w / ar
        if h > available.height { h = available.height; w = h * ar }
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    private func pixelRect(_ size: CGSize) -> CGRect {
        CGRect(x: draft.x * size.width, y: draft.y * size.height, width: draft.w * size.width, height: draft.h * size.height)
    }

    private func canvas(_ size: CGSize) -> some View {
        let r = pixelRect(size)
        return ZStack(alignment: .topLeading) {
            if let still {
                Image(decorative: still, scale: 1).resizable().frame(width: size.width, height: size.height)
            } else {
                Color.black
            }
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Color.clear.contentShape(Rectangle())
                .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .gesture(drag(.move, size: size))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Crop frame")
                .accessibilityIdentifier("crop.frame")
            ForEach(CropHandle.resizing, id: \.self) { h in
                let p = h.anchor(in: r)
                Color.clear.contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: handleSize, height: handleSize)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.5), lineWidth: 1))
                    )
                    .frame(width: handleSize * 2.2, height: handleSize * 2.2)
                    .position(x: p.x, y: p.y)
                    .gesture(drag(h, size: size))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Crop handle \(h.rawValue)")
                    .accessibilityIdentifier("crop.handle.\(h.rawValue)")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: space)
    }

    private func drag(_ handle: CropHandle, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { v in
                let base = dragBase ?? draft
                if dragBase == nil { dragBase = draft }
                let delta = CGPoint(x: v.translation.width / size.width, y: v.translation.height / size.height)
                draft = CropRect.dragged(base, handle: handle, by: delta, minSize: model.project.minCropSize)
            }
            .onEnded { _ in dragBase = nil }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Drag the edges to crop").font(.callout)
            Button("Reset") { draft = .full }
                .controlSize(.small)
                .accessibilityIdentifier("crop.reset")
            Button("Cancel") { model.cancelCrop() }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("crop.cancel")
            Button("Done") { model.setCrop(draft) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("crop.done")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 10)
    }

    private func loadStill() async -> CGImage? {
        let asset = AVURLAsset(url: model.dir.appendingPathComponent(model.project.screenFile))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let t = CMTime(seconds: max(model.time - model.project.screenOffset, 0), preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        if let img = try? await gen.image(at: t).image { return img }
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        return try? await gen.image(at: t).image
    }
}
