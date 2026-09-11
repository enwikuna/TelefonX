import AppKit
import SwiftUI

struct DoNotDisturbMenuItems: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        if model.manualDoNotDisturb {
            Button("Disable Do Not Disturb") { model.setDoNotDisturb(false) }
            Divider()
        }
        ForEach(DoNotDisturbDuration.allCases) { duration in
            Button(duration.title) { model.activateDoNotDisturb(for: duration) }
        }
    }
}

struct NativeDoNotDisturbMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let activate: (DoNotDisturbDuration) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, activate: activate)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.activate = activate
        guard isPresented, !context.coordinator.isPresenting, anchor.window != nil else { return }
        context.coordinator.isPresenting = true
        DispatchQueue.main.async {
            guard context.coordinator.isPresented.wrappedValue else {
                context.coordinator.isPresenting = false
                return
            }
            context.coordinator.isPresented.wrappedValue = false
            context.coordinator.presentMenu(relativeTo: anchor)
            context.coordinator.isPresenting = false
        }
    }

    @MainActor final class Coordinator: NSObject {
        var isPresented: Binding<Bool>
        var activate: (DoNotDisturbDuration) -> Void
        var isPresenting = false

        init(isPresented: Binding<Bool>, activate: @escaping (DoNotDisturbDuration) -> Void) {
            self.isPresented = isPresented
            self.activate = activate
        }

        func presentMenu(relativeTo anchor: NSView) {
            let menu = NSMenu()
            for (index, duration) in DoNotDisturbDuration.allCases.enumerated() {
                let item = NSMenuItem(title: duration.title,
                                      action: #selector(selectDuration(_:)),
                                      keyEquivalent: "")
                item.tag = index
                item.target = self
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -8), in: anchor)
        }

        @objc private func selectDuration(_ sender: NSMenuItem) {
            let durations = DoNotDisturbDuration.allCases
            guard durations.indices.contains(sender.tag) else { return }
            activate(durations[sender.tag])
        }
    }
}
