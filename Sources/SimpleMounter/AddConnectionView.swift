import SwiftUI

struct ServiceType: Identifiable, Equatable {
    let id: String          // tipo rclone: sftp/ftp/drive/onedrive
    let label: String
    let symbol: String
    let defaultPort: String
    var isOAuth: Bool { id == "drive" || id == "onedrive" }
}

/// Modo de cifrado para conexiones FTP.
enum FtpSecurity: String, CaseIterable, Identifiable {
    case none, explicit, implicit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:     return "Unencrypted (FTP)"
        case .explicit: return "FTPS · explicit TLS"
        case .implicit: return "FTPS · implicit TLS"
        }
    }
    var defaultPort: String { self == .implicit ? "990" : "21" }

    /// Opciones rclone. Se pasan siempre explícitas para que el cambio funcione en ambos sentidos.
    func options(noCertCheck: Bool) -> [String: String] {
        var o: [String: String] = [
            "explicit_tls": self == .explicit ? "true" : "false",
            "tls": self == .implicit ? "true" : "false"
        ]
        if self != .none { o["no_check_certificate"] = noCertCheck ? "true" : "false" }
        return o
    }

    /// Deduce el modo a partir de los campos guardados de un remote.
    static func from(fields: [String: String]) -> FtpSecurity {
        if fields["tls"] == "true" { return .implicit }
        if fields["explicit_tls"] == "true" { return .explicit }
        return .none
    }
}

let serviceTypes = [
    ServiceType(id: "sftp",     label: "SFTP",         symbol: "server.rack",           defaultPort: "22"),
    ServiceType(id: "ftp",      label: "FTP",          symbol: "folder.badge.gearshape", defaultPort: "21"),
    ServiceType(id: "drive",    label: "Google Drive", symbol: "externaldrive.badge.icloud", defaultPort: ""),
    ServiceType(id: "onedrive", label: "OneDrive",     symbol: "cloud",                 defaultPort: "")
]

struct AddConnectionView: View {
    let manager: RcloneManager
    var onClose: () -> Void

    @State private var selected = serviceTypes[0]
    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = "22"
    @State private var password = ""
    @State private var ftpSecurity: FtpSecurity = .explicit
    @State private var noCertCheck = false
    @State private var connecting = false
    @State private var errorText: String?

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if selected.isOAuth { return true }
        return !host.isEmpty && !user.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add connection").font(.system(size: 16, weight: .medium))

            // Selector de tipo
            HStack(spacing: 8) {
                ForEach(serviceTypes) { t in
                    Button { select(t) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.symbol).font(.system(size: 22))
                            Text(t.label).font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(selected == t ? Theme.skyBlue.opacity(0.18) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(selected == t ? Theme.skyBlue : Color.gray.opacity(0.3),
                                    lineWidth: selected == t ? 2 : 1))
                        .foregroundColor(selected == t ? Theme.skyBlue : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(namePlaceholder, text: $name).textFieldStyle(.roundedBorder)

            if selected.isOAuth {
                Text("Your browser will open to authorize the account. Come back here when you’re done.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                TextField("Host  ·  e.g. 192.168.1.10", text: $host).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Username", text: $user).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 90)
                }
                SecureField(selected.id == "sftp" ? "Password (optional with SSH key)" : "Password",
                            text: $password)
                    .textFieldStyle(.roundedBorder)

                if selected.id == "ftp" {
                    Picker("Security", selection: $ftpSecurity) {
                        ForEach(FtpSecurity.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: ftpSecurity) { port = $0.defaultPort }
                    if ftpSecurity != .none {
                        Toggle("Don’t verify the TLS certificate (self-signed servers)",
                               isOn: $noCertCheck)
                            .font(.system(size: 12))
                    }
                }
            }

            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("rclone stores credentials encrypted in ~/.config/rclone.",
                  systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                Button(action: save) {
                    HStack(spacing: 6) {
                        if connecting { ProgressView().controlSize(.small) }
                        Text(selected.isOAuth ? "Connect with browser" : "Save connection")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || connecting)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var namePlaceholder: String {
        switch selected.id {
        case "drive":    return "Name (e.g. Work Drive)"
        case "onedrive": return "Name (e.g. Personal OneDrive)"
        default:         return "Name (e.g. Home server)"
        }
    }

    private func select(_ t: ServiceType) {
        selected = t
        if !t.defaultPort.isEmpty { port = t.defaultPort }
        errorText = nil
    }

    private func save() {
        errorText = nil
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        if selected.isOAuth {
            connecting = true
            manager.createOAuth(name: cleanName, type: selected.id) { ok, err in
                connecting = false
                if ok { onClose() } else { errorText = err ?? "Authorization failed." }
            }
        } else {
            let extra = selected.id == "ftp" ? ftpSecurity.options(noCertCheck: noCertCheck) : [:]
            let r = manager.createBasic(name: cleanName, type: selected.id,
                                        host: host, user: user, port: port, password: password,
                                        extra: extra)
            if r.ok { onClose() } else { errorText = r.error ?? "Couldn’t create the connection." }
        }
    }
}
