import AppKit
import SwiftUI

@main
struct ClawdexDesktopApp: App {
    @StateObject private var controller: BridgeController

    init() {
        let controller = BridgeController()
        _controller = StateObject(wrappedValue: controller)

        DispatchQueue.main.async {
            StatusBarController.shared.install(controller: controller)
            if !BridgeConfiguration.hasSavedConfiguration {
                SetupWindowPresenter.shared.show(controller: controller)
            }
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsWindowPresenter.shared.show(controller: controller)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
