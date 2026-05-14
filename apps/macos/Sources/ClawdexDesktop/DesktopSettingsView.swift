import AppKit
import SwiftUI

enum DesktopSettingsMode {
    case onboarding
    case settings
}

private enum DesktopSettingsSection: String, CaseIterable, Identifiable {
    case connection
    case engines
    case chat
    case appearance
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .connection:
            "Connection"
        case .engines:
            "Engines"
        case .chat:
            "Chat"
        case .appearance:
            "Appearance"
        case .advanced:
            "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .connection:
            "network"
        case .engines:
            "cpu"
        case .chat:
            "bubble.left.and.bubble.right"
        case .appearance:
            "paintpalette"
        case .advanced:
            "slider.horizontal.3"
        }
    }
}

struct DesktopSettingsView: View {
    @EnvironmentObject private var controller: BridgeController

    let mode: DesktopSettingsMode
    @State private var selection: DesktopSettingsSection = .connection

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionHeader
                        sectionContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BrandIconView(asset: .clawdex, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clawdex")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(mode == .onboarding ? "Setup" : "Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)

            ForEach(DesktopSettingsSection.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 9) {
                        settingsSectionIcon(item)
                        Text(item.title)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selection == item ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func settingsSectionIcon(_ item: DesktopSettingsSection) -> some View {
        Image(systemName: item.systemImage)
            .foregroundStyle(.secondary)
            .frame(width: 20)
    }

    private var header: some View {
        HStack(spacing: 16) {
            statusBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(controller.configuration.bridgeURL)
                    .font(.headline)
                    .textSelection(.enabled)
                Text(connectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            QRCodeView(payload: controller.pairingPayload)
                .frame(width: 92, height: 92)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(sectionSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .connection:
            connectionSection
        case .engines:
            enginesSection
        case .chat:
            chatSection
        case .appearance:
            appearanceSection
        case .advanced:
            advancedSection
        }
    }

    private var connectionSection: some View {
        SettingGroup {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Work folder")
                    HStack {
                        TextField("Work folder", text: $controller.configuration.workdir)
                        Button {
                            chooseWorkFolder()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                    }
                }

                GridRow {
                    Text("Phone URL host")
                    TextField("Phone URL host", text: $controller.configuration.connectHost)
                }

                GridRow {
                    Text("Bind host")
                    TextField("Bind host", text: $controller.configuration.bindHost)
                }

                GridRow {
                    Text("Port")
                    TextField("Port", value: $controller.configuration.port, format: .number)
                        .frame(width: 120)
                }
            }
        }
    }

    private var enginesSection: some View {
        SettingGroup {
            VStack(spacing: 0) {
                ForEach(BridgeEngine.allCases) { engine in
                    HStack(spacing: 12) {
                        BrandIconView(asset: engine.brandAsset, size: 24)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.title)
                                .font(.body)
                            Text(engine.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: engineEnabledBinding(engine))
                            .labelsHidden()
                            .disabled(engine == .codex)
                    }
                    .padding(.vertical, 10)

                    if engine != BridgeEngine.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingGroup {
                Picker("Execution approvals", selection: $controller.configuration.approvalMode) {
                    Text("Normal").tag("normal")
                    Text("YOLO").tag("yolo")
                }
                .pickerStyle(.segmented)
            }

            SettingGroup {
                Toggle("Show tool calls in transcripts", isOn: $controller.configuration.showToolCalls)
                    .toggleStyle(.switch)
            }
        }
    }

    private var appearanceSection: some View {
        SettingGroup {
            Picker("Theme", selection: $controller.configuration.appearancePreference) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingGroup {
                Toggle("Allow token in WebSocket query string", isOn: $controller.configuration.allowQueryTokenAuth)
                    .toggleStyle(.switch)
            }

            SettingGroup {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Pairing token")
                        HStack {
                            SecureField("Token", text: $controller.configuration.token)
                            Button("New Token") {
                                controller.resetToken()
                            }
                        }
                    }

                    GridRow {
                        Text("Bridge URL")
                        HStack {
                            Text(controller.configuration.bridgeURL)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                copy(controller.configuration.bridgeURL)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }

            if !controller.lastLogLines.isEmpty {
                SettingGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent bridge log")
                            .font(.headline)
                        Text(controller.lastLogLines.suffix(6).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let detail = controller.runState.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Save changes before restarting the bridge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save") {
                controller.saveConfiguration()
            }

            if controller.runState == .running || controller.runState == .starting {
                Button("Stop Bridge") {
                    controller.stop()
                }
            } else {
                Button(mode == .onboarding ? "Save and Start" : "Start Bridge") {
                    controller.start()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var statusBadge: some View {
        Label(controller.runState.title, systemImage: controller.menuBarSystemImage)
            .font(.callout)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.14))
            )
            .foregroundStyle(statusColor)
    }

    private var connectionSummary: String {
        let devices = controller.statusSnapshot?.devices.count ?? 0
        let deviceText = "\(devices) connected \(devices == 1 ? "device" : "devices")"
        return "\(controller.configuration.enabledEngineSummary) / \(deviceText)"
    }

    private var sectionSubtitle: String {
        switch selection {
        case .connection:
            "The phone pairs to this Mac over your private network."
        case .engines:
            "Codex stays available; add Cursor or OpenCode when their local tools are installed."
        case .chat:
            "Defaults the phone can use after pairing from this app."
        case .appearance:
            "Controls the desktop menu-bar app appearance."
        case .advanced:
            "Pairing token, compatibility, and recent bridge output."
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

    private func engineEnabledBinding(_ engine: BridgeEngine) -> Binding<Bool> {
        Binding(
            get: { controller.configuration.enabledEngineValues.contains(engine.rawValue) },
            set: { controller.setEngineEnabled(engine, isEnabled: $0) }
        )
    }

    private func chooseWorkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: controller.configuration.workdir)

        if panel.runModal() == .OK, let url = panel.url {
            controller.configuration.workdir = url.path
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct SettingGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}
