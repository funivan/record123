import CoreGraphics

struct DeviceOption: Equatable {
    let id: String
    let builtIn: Bool
}

enum DeviceDefaults {
    nonisolated static func selection(stored: String?, available: [DeviceOption], systemDefault: String?, accessDenied: Bool) -> String {
        if accessDenied { return "" }
        if stored == "" { return "" }
        if let stored, available.contains(where: { $0.id == stored }) { return stored }
        if let builtIn = available.first(where: { $0.builtIn }) { return builtIn.id }
        if let systemDefault, available.contains(where: { $0.id == systemDefault }) { return systemDefault }
        return ""
    }

    nonisolated static func display(current: CGDirectDisplayID, available: [CGDirectDisplayID], main: CGDirectDisplayID) -> CGDirectDisplayID? {
        if available.contains(current) { return current }
        if available.contains(main) { return main }
        return available.first
    }
}
