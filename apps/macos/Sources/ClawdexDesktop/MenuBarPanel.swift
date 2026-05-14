import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var controller: BridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: controller.menuBarSystemImage)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clawdex")
                        .font(.headline)
                    Text(controller.runState.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    StatusBarController.shared.showSettings(controller: controller)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            if let detail = controller.runState.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            statusGrid

            deviceSummary

            VStack(alignment: .center, spacing: 8) {
                QRCodeView(payload: controller.pairingPayload)
                    .frame(width: 176, height: 176)
                Text("Pair from the mobile app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )

            HStack(spacing: 8) {
                if controller.runState == .running || controller.runState == .starting {
                    Button("Stop") {
                        controller.stop()
                    }
                } else {
                    Button("Start") {
                        controller.start()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Button("Copy URL") {
                    copy(controller.configuration.bridgeURL)
                }
            }

            Divider()

            Button("Quit Clawdex") {
                controller.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .task {
            await controller.refreshStatus()
        }
    }

    private var statusColor: Color {
        switch controller.runState {
        case .running:
            .green
        case .starting:
            .orange
        case .failed:
            .red
        case .stopped:
            .secondary
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                statBlock("URL", controller.configuration.bridgeURL, selectable: true)
                statBlock("Engines", controller.configuration.enabledEngineSummary)
            }
            GridRow {
                statBlock("Port", String(controller.configuration.port))
                statBlock("Approval", approvalModeTitle)
            }
        }
    }

    private func statBlock(_ label: String, _ value: String, selectable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            statValue(value, selectable: selectable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    @ViewBuilder
    private func statValue(_ value: String, selectable: Bool) -> some View {
        let text = Text(value)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
        if selectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var approvalModeTitle: String {
        controller.configuration.approvalMode == "normal" ? "Normal" : "YOLO"
    }

    @ViewBuilder
    private var deviceSummary: some View {
        let devices = controller.statusSnapshot?.devices ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("\(devices.count) connected \(devices.count == 1 ? "device" : "devices")")
                .font(.subheadline)
                .fontWeight(.medium)
            if devices.isEmpty {
                Text("No phones connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices.prefix(4)) { device in
                    HStack {
                        Image(systemName: device.clientType == "mobile" ? "iphone" : "network")
                            .foregroundStyle(.secondary)
                        Text(device.clientName)
                            .lineLimit(1)
                        Spacer()
                        Text(device.clientType)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
