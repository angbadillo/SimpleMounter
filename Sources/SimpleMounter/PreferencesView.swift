import SwiftUI
import AppKit

struct PreferencesView: View {
    let manager: RcloneManager
    var onChanged: () -> Void

    /// Versión del Info.plist ("0.mesdía", la genera package.sh con la fecha de build).
    private static let appVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0707"

    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = Settings.shared.launchAtLogin
    @State private var remotes: [Remote] = []
    @State private var reconnecting: String?
    @State private var editing: Remote?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in settings.launchAtLogin = v }
                Toggle("Notify on mount or unmount", isOn: $settings.notificationsEnabled)
                LabeledContent("Mounts folder") {
                    HStack(spacing: 8) {
                        Text(settings.mountBasePath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { chooseFolder() }
                    }
                }
            }

            Section("Connections") {
                if remotes.isEmpty {
                    Text("No connections yet. Use “Add connection…” from the menu.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remotes) { connectionRow($0) }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                Text("Freeware · © 2026 Buscarruidos")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .onAppear { remotes = manager.listRemotes() }
        .sheet(item: $editing) { r in
            EditConnectionView(manager: manager, original: r) {
                editing = nil
                remotes = manager.listRemotes()
                onChanged()
            }
        }
    }

    @ViewBuilder
    private func connectionRow(_ r: Remote) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.symbolName(for: r.type))
                .foregroundColor(Theme.tint(for: r.type))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                Text(r.prettyType).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Auto", isOn: Binding(
                get: { settings.autoMountNames.contains(r.name) },
                set: { settings.toggleAutoMount(r.name, on: $0) }
            )).toggleStyle(.checkbox).help("Mount this connection at startup")

            Button { editing = r } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Edit connection")
            if r.isOAuth {
                Button {
                    reconnecting = r.name
                    manager.reconnect(name: r.name) { _, _ in reconnecting = nil; onChanged() }
                } label: {
                    if reconnecting == r.name { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless).help("Reconnect (re-authorize)")
            }
            Button { delete(r) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Remove connection")
        }
        .padding(.vertical, 2)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { settings.mountBasePath = url.path }
    }

    private func delete(_ r: Remote) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(r.name)”?"
        alert.informativeText = "This removes the connection from rclone. It does not delete any files on the cloud or server."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            manager.deleteRemote(r.name)
            remotes = manager.listRemotes()
            onChanged()
        }
    }
}
