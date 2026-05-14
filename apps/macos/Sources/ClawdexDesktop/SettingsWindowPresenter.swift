import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(controller: BridgeController) {
        if let window {
            present(window)
            return
        }

        let rootView = DesktopSettingsView(mode: .settings)
            .environmentObject(controller)
            .frame(minWidth: 760, minHeight: 560)
        let hostingView = NSHostingView(rootView: rootView)
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clawdex Settings"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.onClose = { [weak self] in
            self?.window = nil
        }

        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

private final class SettingsWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
        super.close()
    }
}
