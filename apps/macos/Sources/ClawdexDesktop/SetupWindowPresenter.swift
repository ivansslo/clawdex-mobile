import AppKit
import SwiftUI

@MainActor
final class SetupWindowPresenter {
    static let shared = SetupWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(controller: BridgeController) {
        if let window {
            present(window)
            return
        }

        let rootView = OnboardingView()
            .environmentObject(controller)
            .frame(minWidth: 760, minHeight: 560)
        let hostingView = NSHostingView(rootView: rootView)
        let window = SetupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clawdex Setup"
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

private final class SetupWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
        super.close()
    }
}
