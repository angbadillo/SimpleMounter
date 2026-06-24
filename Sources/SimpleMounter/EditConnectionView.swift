import SwiftUI

struct EditConnectionView: View {
    let manager: RcloneManager
    let original: Remote
    var onDone: () -> Void

    @State private var name: String
    @State private var host: String
    @State private var user: String
    @State private var port: String
    @State private var password = ""
    @State private var ftpSecurity: FtpSecurity
    @State private var noCertCheck: Bool
    @State private var errorText: String?

    init(manager: RcloneManager, original: Remote, onDone: @escaping () -> Void) {
        self.manager = manager
        self.original = original
        self.onDone = onDone
        let f = manager.configFields(original.name)
        _name = State(initialValue: original.name)
        _host = State(initialValue: f["host"] ?? "")
        _user = State(initialValue: f["user"] ?? "")
        _port = State(initialValue: f["port"] ?? "")
        _ftpSecurity = State(initialValue: FtpSecurity.from(fields: f))
        _noCertCheck = State(initialValue: f["no_check_certificate"] == "true")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: Theme.symbolName(for: original.type))
                    .foregroundColor(Color(nsColor: Theme.accentNS(for: original.name)))
                Text("Edit connection").font(.system(size: 16, weight: .medium))
                Spacer()
                Text(original.prettyType).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Text("Name").font(.system(size: 12)).foregroundColor(.secondary)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            if original.isOAuth {
                Text("\(original.prettyType) accounts only allow renaming here. To re-authorize the account, use “Reconnect”.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Server").font(.system(size: 12)).foregroundColor(.secondary)
                TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Username", text: $user).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 90)
                }
                SecureField("Password (empty = keep current)", text: $password)
                    .textFieldStyle(.roundedBorder)

                if original.type == "ftp" {
                    Picker("Security", selection: $ftpSecurity) {
                        ForEach(FtpSecurity.allCases) { Text($0.label).tag($0) }
                    }
                    if ftpSecurity != .none {
                        Toggle("Don’t verify the TLS certificate", isOn: $noCertCheck)
                            .font(.system(size: 12))
                    }
                }
            }

            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        let extra = original.type == "ftp" ? ftpSecurity.options(noCertCheck: noCertCheck) : [:]
        let r = manager.saveEdit(original: original, newName: name, host: host,
                                 user: user, port: port, newPassword: password, extra: extra)
        if r.ok { onDone() } else { errorText = r.error ?? "Couldn’t save." }
    }
}
