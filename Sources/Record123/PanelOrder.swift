import SwiftUI

protocol OrderedPanel: RawRepresentable, CaseIterable, Hashable where RawValue == String {
    static var defaultOrder: [Self] { get }
    var title: String { get }
    var icon: String { get }
}

enum PanelOrder {
    static let inspectorKey = "inspector.order"
    static let recorderKey = "recorder.order"

    static func load<T: OrderedPanel>(_ stored: String) -> [T] {
        let saved = stored.split(separator: ",").compactMap { T(rawValue: String($0)) }
        return saved + T.defaultOrder.filter { !saved.contains($0) }
    }

    static func store<T: OrderedPanel>(_ panels: [T]) -> String {
        panels.map(\.rawValue).joined(separator: ",")
    }

    static func move<T: OrderedPanel>(_ panel: T, by delta: Int, in stored: inout String) {
        var list: [T] = load(stored)
        guard let i = list.firstIndex(of: panel), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        stored = store(list)
    }
}

struct PanelOrderEditor<T: OrderedPanel>: View {
    @Binding var stored: String

    var body: some View {
        let panels: [T] = PanelOrder.load(stored)
        ForEach(Array(panels.enumerated()), id: \.element) { i, panel in
            HStack {
                Label(panel.title, systemImage: panel.icon)
                Spacer()
                Button { PanelOrder.move(panel, by: -1, in: &stored) } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                Button { PanelOrder.move(panel, by: 1, in: &stored) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == panels.count - 1)
            }
            .buttonStyle(.borderless)
        }
        Button("Reset order") { stored = "" }
            .disabled(stored.isEmpty)
    }
}
