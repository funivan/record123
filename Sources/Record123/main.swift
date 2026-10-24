import Foundation
import AppKit
import SwiftUI
import ScreenCaptureKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--export"), args.count > i + 2 {
    let dir = URL(fileURLWithPath: args[i + 1])
    let out = URL(fileURLWithPath: args[i + 2])
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        do {
            let p = try ProjectIO.load(dir)
            let ex = Exporter()
            await ex.export(project: p, dir: dir, to: out)
            if let e = ex.error { print("export failed: \(e)"); exit(1) }
            print("exported \(out.path)")
        } catch { print("error: \(error)"); exit(1) }
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    exit(0)
}
if let i = args.firstIndex(of: "--diag"), args.count > i + 1 {
    let out = args[i + 1]
    let sem = DispatchSemaphore(value: 0)
    Task {
        var log = "preflight=\(CGPreflightScreenCaptureAccess())\n"
        do {
            let c = try await SCShareableContent.current
            log += "displays=\(c.displays.count) windows=\(c.windows.count)\n"
        } catch { log += "SCShareableContent error: \(error)\n" }
        try? log.write(toFile: out, atomically: true, encoding: .utf8)
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 20)
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    MainActor.assumeIsolated {
        if let t = ProcessInfo.processInfo.environment["RECORD123_THEME"], let k = ThemeKind(rawValue: t) { ThemeStore.shared.kind = k }
        let state = AppState()
        let dir = URL(fileURLWithPath: args[i + 1])
        if dir.path != "-" { state.open(dir) }
        let settings = ProcessInfo.processInfo.environment["RECORD123_SETTINGS"] != nil
        let size = settings ? CGSize(width: 560, height: 460) : CGSize(width: 1280, height: 800)
        let root: AnyView = settings ? AnyView(SettingsView().environmentObject(state)) : AnyView(RootView().environmentObject(state))
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        let until = Date(timeIntervalSinceNow: 3)
        while Date() < until { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 2]))
        }
    }
    exit(0)
}
Record123App.main()
