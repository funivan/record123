import SwiftUI
import AVFoundation
import AppKit

enum ThemeKind: String, CaseIterable, Identifiable {
    case system, signal, midnight, tiles, planet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .signal: return "Signal"
        case .midnight: return "Midnight"
        case .tiles: return "Tiles"
        case .planet: return "Planet"
        }
    }
    var subtitle: String {
        switch self {
        case .system: return "Native macOS look. Follows light/dark and your accent colour."
        case .signal: return "Ink black with signal orange. The Recordy signature."
        case .midnight: return "Deep blue-black with cool cyan. Clean and technical."
        case .tiles: return "Soft grey canvas, white tiles, vermilion and lime. Rounded widget look."
        case .planet: return "Peach gradient, cream tiles, orange and yellow accents. Clock dashboard look."
        }
    }
}

struct Palette {
    var bg: Color
    var text: Color
    var accent: Color
    var accentB: Color
    var accent2: Color
    var onAccent: Color
    var scheme: ColorScheme?
    var serif: Bool
    var dots: Bool
    var glow: Bool
    var surface: Color? = nil
    var chip: Color? = nil
    var radius: CGFloat = 12
    var inverse: Color? = nil
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var kind: ThemeKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: "theme") }
    }
    init() {
        kind = ThemeKind(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .tiles
    }
    var palette: Palette { ThemeStore.palette(for: kind) }

    static func palette(for kind: ThemeKind) -> Palette {
        switch kind {
        case .system:
            return Palette(bg: Color(nsColor: .windowBackgroundColor), text: .primary, accent: .accentColor, accentB: .accentColor.opacity(0.8),
                           accent2: .accentColor, onAccent: .white, scheme: nil, serif: false, dots: false, glow: false)
        case .signal:
            return Palette(bg: Color(red: 0.055, green: 0.055, blue: 0.07), text: Color(red: 0.96, green: 0.94, blue: 0.9),
                           accent: Color(red: 1.0, green: 0.30, blue: 0.16), accentB: Color(red: 1.0, green: 0.55, blue: 0.2),
                           accent2: Color(red: 0.78, green: 1.0, blue: 0.24), onAccent: Color(red: 0.055, green: 0.055, blue: 0.07),
                           scheme: .dark, serif: true, dots: true, glow: true)
        case .midnight:
            return Palette(bg: Color(red: 0.04, green: 0.055, blue: 0.105), text: Color(red: 0.9, green: 0.94, blue: 1.0),
                           accent: Color(red: 0.25, green: 0.78, blue: 1.0), accentB: Color(red: 0.4, green: 0.6, blue: 1.0),
                           accent2: Color(red: 0.62, green: 0.52, blue: 1.0), onAccent: Color(red: 0.03, green: 0.05, blue: 0.1),
                           scheme: .dark, serif: false, dots: false, glow: true)
        case .tiles:
            return Palette(bg: Color(red: 0.918, green: 0.918, blue: 0.918), text: Color(red: 0.102, green: 0.102, blue: 0.102),
                           accent: Color(red: 1.0, green: 0.318, blue: 0.133), accentB: Color(red: 1.0, green: 0.318, blue: 0.133),
                           accent2: Color(red: 0.82, green: 0.98, blue: 0.0), onAccent: .white,
                           scheme: .light, serif: false, dots: false, glow: false,
                           surface: .white, chip: Color(red: 0.961, green: 0.961, blue: 0.961), radius: 28,
                           inverse: Color(red: 0.157, green: 0.157, blue: 0.157))
        case .planet:
            return Palette(bg: Color(red: 0.976, green: 0.894, blue: 0.808), text: Color(red: 0.086, green: 0.086, blue: 0.086),
                           accent: Color(red: 1.0, green: 0.557, blue: 0.306), accentB: Color(red: 1.0, green: 0.66, blue: 0.4),
                           accent2: Color(red: 0.961, green: 0.94, blue: 0.231), onAccent: Color(red: 0.086, green: 0.086, blue: 0.086),
                           scheme: .light, serif: false, dots: false, glow: true,
                           surface: Color(red: 0.984, green: 0.969, blue: 0.945), chip: Color(red: 0.945, green: 0.918, blue: 0.886), radius: 28,
                           inverse: Color(red: 0.086, green: 0.086, blue: 0.086))
        }
    }
}

enum Theme {
    static var p: Palette { ThemeStore.shared.palette }
    static var ink: Color { p.bg }
    static var bone: Color { p.text }
    static var signal: Color { p.accent }
    static var lime: Color { p.accent2 }
    static let camera = Color(red: 1.0, green: 0.42, blue: 0.7)
    static var onAccent: Color { p.onAccent }
    static var accentSolid: Color { p.accent }
    static var accent: LinearGradient { LinearGradient(colors: [p.accent, p.accentB], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var record: LinearGradient { accent }

    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        if p.serif {
            let f = Font.system(size: size, weight: .semibold, design: .serif)
            return italic ? f.italic() : f
        }
        return .system(size: size, weight: .semibold, design: .default)
    }
    static func tileSurface(hover: Bool = false) -> Color? {
        guard let surface = p.surface else { return nil }
        return hover ? p.chip ?? surface : surface
    }
    static var inverseSurface: Color? { p.inverse }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

struct AppBackground: View {
    var body: some View {
        let p = Theme.p
        ZStack {
            p.bg
            if p.glow {
                RadialGradient(colors: [p.accent.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
                RadialGradient(colors: [p.accent2.opacity(0.05), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
            }
            if p.dots {
                Canvas { ctx, size in
                    let step: CGFloat = 26
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(p.text.opacity(0.07)))
                            x += step
                        }
                        y += step
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var title: String?
    var icon: String?
    var expanded: Binding<Bool>?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                let tile = Theme.p.surface != nil
                let header = HStack(spacing: 8) {
                    if tile {
                        Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.bone)
                    } else {
                        Rectangle().fill(Theme.signal).frame(width: 14, height: 2)
                        Text(title.uppercased()).font(Theme.mono(10.5)).tracking(1.4).foregroundStyle(Theme.bone.opacity(0.6))
                    }
                    Spacer()
                    if let icon {
                        if tile {
                            Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.bone)
                                .frame(width: 32, height: 32).background(Theme.p.chip ?? .clear, in: Circle())
                        } else {
                            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.bone.opacity(0.35))
                        }
                    }
                    if let expanded {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.bone.opacity(0.45))
                            .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    }
                }
                if let expanded {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() } } label: { header.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    header
                }
            }
            if expanded?.wrappedValue ?? true { content }
        }
        .padding(Theme.p.surface != nil ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground(radius: Theme.p.radius)
    }
}

extension View {
    @ViewBuilder
    func tileBackground(radius: CGFloat, hover: Bool = false, dark: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if dark, let fill = Theme.inverseSurface {
            self.background(hover ? fill.opacity(0.92) : fill, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        } else if let fill = Theme.tileSurface(hover: hover) {
            self.background(fill, in: shape)
                .shadow(color: .black.opacity(0.04), radius: 14, y: 4)
        } else {
            self.background(Theme.bone.opacity(hover ? 0.09 : 0.045), in: shape)
                .overlay(shape.stroke(Theme.bone.opacity(0.1), lineWidth: 1))
        }
    }
}

struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(gradient, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(Theme.p.surface == nil ? 0.25 : 0), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.bone)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.bone.opacity(configuration.isPressed ? 0.18 : 0.09), in: Capsule())
            .overlay(Capsule().stroke(Theme.bone.opacity(Theme.p.surface == nil ? 0.12 : 0), lineWidth: 1))
    }
}

struct PillSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].0 == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = options[i].0 } } label: {
                    Text(options[i].1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(on ? Color(red: 0.1, green: 0.1, blue: 0.1) : Theme.bone.opacity(0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(on ? Theme.lime : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.p.chip ?? Theme.bone.opacity(0.06), in: Capsule())
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored = true
    func makeNSView(context: Context) -> NSView { CameraPreviewView(session: session, mirrored: mirrored) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    private let blurLayer: CALayer

    init(session: AVCaptureSession, mirrored: Bool) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        blurLayer = BlurredPreview.makeLayer(mirrored: mirrored)
        super.init(frame: .zero)
        preview.videoGravity = .resizeAspectFill
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = mirrored
        }
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(preview)
        layer?.addSublayer(blurLayer)
        BlurredPreview.shared.register(blurLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        BlurredPreview.layout(blurLayer, in: bounds)
        CATransaction.commit()
    }
}

struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bone.opacity(0.1))
                Capsule()
                    .fill(level > 0.9 ? Theme.signal : Theme.lime)
                    .frame(width: max(6, g.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 8)
    }
}

struct VideoThumb: View {
    let dir: URL
    @State private var image: NSImage?
    var body: some View {
        Rectangle().fill(Theme.bone.opacity(0.06))
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "film").foregroundStyle(.tertiary).font(.title) }
            }
            .clipped()
        .task(id: dir) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: dir.appendingPathComponent("screen.mov")))
            gen.maximumSize = CGSize(width: 640, height: 400)
            gen.appliesPreferredTrackTransform = true
            if let r = try? await gen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
                image = NSImage(cgImage: r.image, size: .zero)
            }
        }
    }
}
