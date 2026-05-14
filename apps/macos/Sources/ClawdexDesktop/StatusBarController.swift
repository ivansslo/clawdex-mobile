import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private override init() {
        super.init()
    }

    func install(controller: BridgeController) {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.toolTip = "Clawdex"
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel().environmentObject(controller)
        )
        self.popover = popover

        updateIcon(systemImage: controller.menuBarSystemImage)
    }

    func updateIcon(systemImage: String) {
        guard let button = statusItem?.button else {
            return
        }

        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: "Clawdex")
        button.imagePosition = .imageOnly
    }

    func showSettings(controller: BridgeController) {
        popover?.performClose(nil)
        SettingsWindowPresenter.shared.show(controller: controller)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
