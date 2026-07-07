import Foundation
import UserNotifications

/// Una conexión configurada en rclone (p.ej. "Drive trabajo" de tipo "drive").
struct Remote: Identifiable {
    let name: String
    let type: String
    var id: String { name }

    var prettyType: String {
        switch type {
        case "drive":    return "Google Drive"
        case "onedrive": return "OneDrive"
        case "sftp":     return "SFTP"
        case "ftp":      return "FTP"
        default:         return type
        }
    }
    var isOAuth: Bool { type == "drive" || type == "onedrive" }
}

/// Capa fina sobre el binario `rclone`: listar, crear, montar, desmontar.
final class RcloneManager {

    /// Se llama (en main) cuando cambia algo y la UI debe refrescarse.
    var onChange: (() -> Void)?

    private var mountProcesses: [String: Process] = [:]
    /// Conexiones en transición (montando o autenticando) para mostrar "conectando…".
    private(set) var inProgress: Set<String> = []

    // Auto-reintento: conexiones que el usuario quiere montadas, las que llegaron a montarse,
    // y cuántos reintentos llevan tras una caída.
    private var desiredMounted: Set<String> = []
    private var established: Set<String> = []
    private var retryCount: [String: Int] = [:]
    private var watchdog: Timer?

    /// Espacio libre por conexión (texto ya formateado), si el backend lo soporta.
    private var aboutCache: [String: String] = [:]
    func freeSpace(_ name: String) -> String? { aboutCache[name] }

    let rclonePath: String = {
        for c in ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"]
            where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "rclone"
    }()

    /// true si encontramos el binario de rclone en una ruta conocida.
    var rcloneInstalled: Bool { rclonePath.hasPrefix("/") }

    var mountBase: URL {
        URL(fileURLWithPath: Settings.shared.mountBasePath, isDirectory: true)
    }
    func mountPoint(for name: String) -> URL {
        mountBase.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: - Lectura

    func listRemotes() -> [Remote] {
        guard let out = runCapturing(args: ["config", "dump"]),
              let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return json.map { name, value in
            Remote(name: name, type: (value as? [String: Any])?["type"] as? String ?? "?")
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Rutas de montaje del sistema vía getmntinfo(3): sin lanzar procesos y sin
    /// bloquear aunque haya un NFS colgado (MNT_NOWAIT usa datos cacheados).
    func mountedPaths() -> Set<String> {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return [] }
        var paths = Set<String>()
        for i in 0..<Int(count) {
            let path = withUnsafeBytes(of: mounts[i].f_mntonname) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            paths.insert(path)
        }
        return paths
    }
    func isMounted(_ name: String) -> Bool { isMounted(name, in: mountedPaths()) }
    func isMounted(_ name: String, in paths: Set<String>) -> Bool {
        paths.contains(mountPoint(for: name).path)
    }
    /// true si hay algún volumen montado dentro de la carpeta de montajes.
    var anyMounted: Bool {
        let base = mountBase.path.hasSuffix("/") ? mountBase.path : mountBase.path + "/"
        return mountedPaths().contains { $0.hasPrefix(base) }
    }
    func isBusy(_ name: String) -> Bool { inProgress.contains(name) }

    // MARK: - Crear conexiones

    /// Crea un remote SFTP/FTP de forma directa (rclone ofusca la contraseña).
    @discardableResult
    func createBasic(name: String, type: String, host: String, user: String,
                     port: String, password: String,
                     extra: [String: String] = [:]) -> (ok: Bool, error: String?) {
        var args = ["config", "create", name, type, "host=\(host)", "user=\(user)"]
        if !port.isEmpty { args.append("port=\(port)") }
        if !password.isEmpty { args.append("pass=\(password)") }
        for (k, v) in extra { args.append("\(k)=\(v)") }
        let (out, code) = runCapturingWithStatus(args: args)
        let ok = code == 0
        if ok {
            onChange?()
            // SFTP nace seguro: fijamos la clave del host en segundo plano (sin bloquear la UI).
            if type == "sftp" {
                DispatchQueue.global().async { [weak self] in self?.pinHostKey(name: name, host: host, port: port) }
            }
        }
        return (ok, ok ? nil : out)
    }

    /// Crea un remote OAuth (Drive/OneDrive) lanzando el flujo de navegador de rclone.
    func createOAuth(name: String, type: String, completion: @escaping (Bool, String?) -> Void) {
        inProgress.insert(name)
        onChange?()
        runOAuth(args: ["config", "create", name, type], name: name, completion: completion)
    }

    /// Re-autoriza un remote OAuth existente (token caducado).
    func reconnect(name: String, completion: @escaping (Bool, String?) -> Void) {
        inProgress.insert(name)
        onChange?()
        runOAuth(args: ["config", "reconnect", "\(name):"], name: name, completion: completion)
    }

    private func runOAuth(args: [String], name: String, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global().async {
            let (out, code) = self.runCapturingWithStatus(args: args, timeout: 180)
            DispatchQueue.main.async {
                self.inProgress.remove(name)
                let ok = code == 0
                self.onChange?()
                completion(ok, ok ? nil : out)
            }
        }
    }

    func deleteRemote(_ name: String) {
        if isMounted(name) { unmount(name) }
        _ = runCapturing(args: ["config", "delete", name])
        Settings.shared.toggleAutoMount(name, on: false)
        onChange?()
    }

    /// Descarga la clave pública del host (ssh-keyscan) y la fija en known_hosts del remote.
    /// TOFU: confía en la clave en el primer uso; protege de MITM en adelante.
    private func pinHostKey(name: String, host: String, port: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/rclone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let kh = dir.appendingPathComponent("known_hosts")
        let portArg = port.isEmpty ? "22" : port

        let (out, code) = runCapturingWithStatus(
            executable: "/usr/bin/ssh-keyscan",
            args: ["-T", "8", "-p", portArg, "-t", "ed25519,rsa,ecdsa", host], timeout: 12)
        guard code == 0, let scanned = out,
              !scanned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Quitar entradas previas de este host (evita conflictos de clave) y añadir las nuevas.
        var lines: [String] = []
        if let existing = try? String(contentsOf: kh, encoding: .utf8) {
            let bare = host, bracket = "[\(host)]"
            lines = existing.split(separator: "\n").map(String.init).filter {
                !($0.hasPrefix(bare + " ") || $0.hasPrefix(bare + ",") || $0.hasPrefix(bracket))
            }
        }
        lines += scanned.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        try? (lines.joined(separator: "\n") + "\n").write(to: kh, atomically: true, encoding: .utf8)

        _ = runCapturingWithStatus(args: ["config", "update", name, "known_hosts_file=\(kh.path)"])
        DispatchQueue.main.async { self.onChange?() }
    }

    // MARK: - Editar conexiones

    /// Todos los campos de un remote (host, user, port, pass cifrada, token…).
    func configFields(_ name: String) -> [String: String] {
        guard let out = runCapturing(args: ["config", "dump"]),
              let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = json[name] as? [String: Any] else { return [:] }
        var res: [String: String] = [:]
        for (k, v) in r { if let s = v as? String { res[k] = s } }
        return res
    }

    /// Datos para precargar el formulario de edición (SFTP/FTP).
    func details(_ name: String) -> (host: String, user: String, port: String) {
        let f = configFields(name)
        return (f["host"] ?? "", f["user"] ?? "", f["port"] ?? "")
    }

    /// Guarda la edición de una conexión. Para SFTP/FTP edita host/user/port y,
    /// si `newPassword` no está vacío, también la contraseña. Renombra si cambia el nombre.
    /// Para OAuth solo permite renombrar (la re-autorización se hace con Reconectar).
    func saveEdit(original: Remote, newName: String, host: String, user: String,
                  port: String, newPassword: String,
                  extra: [String: String] = [:]) -> (ok: Bool, error: String?) {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return (false, "The name can’t be empty.") }
        let renaming = newName != original.name
        if renaming && listRemotes().contains(where: { $0.name == newName }) {
            return (false, "A connection named “\(newName)” already exists.")
        }

        if original.isOAuth {
            return renaming ? renameCopy(original.name, to: newName) : (true, nil)
        }

        // SFTP / FTP
        if renaming {
            var args = ["config", "create", newName, original.type, "--non-interactive",
                        "host=\(host)", "user=\(user)", "port=\(port)"]
            for (k, v) in extra { args.append("\(k)=\(v)") }
            if !newPassword.isEmpty {
                args.append("pass=\(newPassword)")
            } else if let p = configFields(original.name)["pass"], !p.isEmpty {
                args.append("--no-obscure"); args.append("pass=\(p)")
            }
            let (out, code) = runCapturingWithStatus(args: args)
            if code != 0 { return (false, out) }
            migrateAndDelete(original.name, to: newName)
            return (true, nil)
        } else {
            var args = ["config", "update", original.name,
                        "host=\(host)", "user=\(user)", "port=\(port)"]
            for (k, v) in extra { args.append("\(k)=\(v)") }
            if !newPassword.isEmpty { args.append("pass=\(newPassword)") }
            let (out, code) = runCapturingWithStatus(args: args)
            if code != 0 { return (false, out) }
            onChange?()
            return (true, nil)
        }
    }

    /// Copia un remote (todos sus campos, sin re-cifrar) con otro nombre y borra el viejo.
    private func renameCopy(_ old: String, to new: String) -> (ok: Bool, error: String?) {
        let fields = configFields(old)
        guard let type = fields["type"] else { return (false, "Unknown type.") }
        var args = ["config", "create", new, type, "--non-interactive", "--no-obscure"]
        for (k, v) in fields where k != "type" { args.append("\(k)=\(v)") }
        let (out, code) = runCapturingWithStatus(args: args)
        if code != 0 { return (false, out) }
        migrateAndDelete(old, to: new)
        return (true, nil)
    }

    /// Traslada montaje/automontaje del nombre viejo al nuevo y elimina el viejo.
    private func migrateAndDelete(_ old: String, to new: String) {
        if isMounted(old) { unmount(old) }
        let wasAuto = Settings.shared.autoMountNames.contains(old)
        _ = runCapturing(args: ["config", "delete", old])
        Settings.shared.toggleAutoMount(old, on: false)
        if wasAuto { Settings.shared.toggleAutoMount(new, on: true) }
        onChange?()
    }

    // MARK: - Montar / Desmontar

    func mount(_ name: String) {
        let point = mountPoint(for: name)
        try? FileManager.default.createDirectory(at: point, withIntermediateDirectories: true)

        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SimpleMounter", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("\(name).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = ["nfsmount", "\(name):", point.path,
                             "--volname", name,
                             // Finder hace muchas lecturas pequeñas (miniaturas, QuickLook,
                             // .DS_Store): cachearlas en disco las hace instantáneas la 2ª vez.
                             "--vfs-cache-mode", "full",
                             "--vfs-cache-max-size", "5G",
                             "--vfs-read-ahead", "128M",
                             // Caché de directorios larga; en Drive/OneDrive el polling
                             // detecta cambios remotos, así que no se queda obsoleta.
                             "--dir-cache-time", "15m",
                             "--poll-interval", "30s",
                             "--attr-timeout", "5s",
                             // Precarga el árbol de directorios al montar.
                             "--vfs-refresh",
                             // Resiliencia ante redes intermitentes:
                             "--low-level-retries", "10",
                             "--contimeout", "15s",
                             "--timeout", "30s"]
        process.environment = childEnv()
        if let logHandle { process.standardOutput = logHandle; process.standardError = logHandle }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.mountProcesses[name] = nil
                self?.onChange?()
            }
        }
        do {
            try process.run()
            mountProcesses[name] = process
            desiredMounted.insert(name)
            inProgress.insert(name)
            onChange?()
            // Esperar a que el volumen aparezca (NFS tarda un par de segundos).
            pollUntilMounted(name)
        } catch {
            notify("Couldn’t mount \(name)", error.localizedDescription)
        }
    }

    private func pollUntilMounted(_ name: String, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if self.isMounted(name) {
                self.inProgress.remove(name)
                self.established.insert(name)
                self.retryCount[name] = 0
                self.onChange?()
                self.notify("Mounted", "\(name) is available in Finder")
                self.fetchAbout(name)
            } else if attempt < 12 && self.mountProcesses[name] != nil {
                self.pollUntilMounted(name, attempt: attempt + 1)
            } else {
                self.inProgress.remove(name)
                self.onChange?()
                if self.established.contains(name) {
                    // Era un reintento tras caída; el watchdog decide si insiste o se rinde.
                } else {
                    // Fallo de montaje inicial (credenciales/red): avisar y no reintentar.
                    self.desiredMounted.remove(name)
                    let reason = self.lastLogError(name) ?? "Check the log for details."
                    self.notify("Couldn’t mount \(name)", reason)
                }
            }
        }
    }

    /// Reintenta en segundo plano las conexiones que se cayeron (el proceso rclone murió),
    /// sin tocar las que el usuario desmontó a propósito ni las que fallaron al inicio.
    func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
    }

    private func watchdogTick() {
        for name in desiredMounted {
            let alive = mountProcesses[name]?.isRunning == true
            if alive { retryCount[name] = 0; continue }
            if isBusy(name) || !established.contains(name) { continue }

            let n = (retryCount[name] ?? 0) + 1
            if n > 5 {
                desiredMounted.remove(name); established.remove(name); retryCount[name] = nil
                notify("Connection lost", "\(name) couldn’t be remounted after several tries.")
                continue
            }
            retryCount[name] = n
            inProgress.insert(name)   // evita que el siguiente tick lo procese de nuevo
            let path = mountPoint(for: name).path
            DispatchQueue.global().async { [weak self] in
                _ = self?.runCapturing(executable: "/sbin/umount", args: ["-f", path], timeout: 10)
                DispatchQueue.main.async {
                    self?.inProgress.remove(name)
                    self?.mount(name)
                }
            }
        }
    }

    /// Consulta el espacio libre del backend (si lo soporta) y lo cachea para el menú.
    private func fetchAbout(_ name: String) {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (out, code) = self.runCapturingWithStatus(args: ["about", "\(name):", "--json"], timeout: 15)
            guard code == 0, let out, let data = out.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let free = json["free"] as? Double else { return }
            let text = ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file) + " free"
            DispatchQueue.main.async { self.aboutCache[name] = text; self.onChange?() }
        }
    }

    func unmount(_ name: String) {
        let path = mountPoint(for: name).path
        let process = mountProcesses.removeValue(forKey: name)
        // Desmontaje intencional: dejar de vigilar/reintentar esta conexión.
        desiredMounted.remove(name)
        established.remove(name)
        retryCount[name] = nil
        aboutCache[name] = nil
        inProgress.insert(name)
        onChange?()
        // diskutil/umount pueden tardar mucho si el servidor no responde
        // (justo cuando más se usa Desmontar): nunca en el hilo de UI.
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            _ = self.runCapturing(executable: "/usr/sbin/diskutil",
                                  args: ["unmount", "force", path], timeout: 15)
            _ = self.runCapturing(executable: "/sbin/umount", args: ["-f", path], timeout: 10)
            if let process, process.isRunning { process.terminate() }
            DispatchQueue.main.async {
                self.inProgress.remove(name)
                self.onChange?()
                self.notify("Unmounted", "\(name) was unmounted")
            }
        }
    }

    func unmountAll() { for n in Array(mountProcesses.keys) { unmount(n) } }

    /// Desmontaje síncrono pero acotado en tiempo, solo para salir de la app
    /// (el unmount normal es asíncrono y no llegaría a ejecutarse antes de terminar).
    func unmountAllBeforeQuit() {
        let names = Array(mountProcesses.keys)
        for name in names {
            if let p = mountProcesses[name], p.isRunning { p.terminate() }
        }
        for name in names {
            _ = runCapturing(executable: "/sbin/umount",
                             args: ["-f", mountPoint(for: name).path], timeout: 3)
        }
        mountProcesses.removeAll()
    }

    func mountAll() {
        let mounted = mountedPaths()
        for r in listRemotes() where !isMounted(r.name, in: mounted) && !isBusy(r.name) { mount(r.name) }
    }

    func mountAutoMounts() {
        let mounted = mountedPaths()
        for name in Settings.shared.autoMountNames where !isMounted(name, in: mounted) { mount(name) }
    }

    /// Extrae un mensaje de error legible de la última línea CRITICAL/ERROR del log.
    private func lastLogError(_ name: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SimpleMounter/\(name).log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").map(String.init)
        guard let line = lines.last(where: { $0.contains("CRITICAL") || $0.contains("ERROR") })
        else { return nil }
        // Traducir los fallos más comunes a algo entendible.
        let lower = line.lowercased()
        if lower.contains("no supported methods") || lower.contains("unable to authenticate") {
            return "Incorrect username or password."
        }
        if lower.contains("connection reset") || lower.contains("i/o timeout") || lower.contains("no route") {
            return "Couldn’t reach the server (check the network or VPN)."
        }
        if lower.contains("knownhosts") || lower.contains("host key") {
            return "The server key doesn’t match the saved one."
        }
        // Si no, devolver la parte tras el último ':' del mensaje original.
        return line.components(separatedBy: ": ").last
    }

    // MARK: - Notificaciones

    func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func notify(_ title: String, _ body: String) {
        guard Settings.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Helpers de proceso

    private func childEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"
        return env
    }

    private func runCapturing(executable: String? = nil, args: [String],
                              timeout: TimeInterval = 30) -> String? {
        runCapturingWithStatus(executable: executable, args: args, timeout: timeout).0
    }

    @discardableResult
    private func runCapturingWithStatus(executable: String? = nil, args: [String],
                                        timeout: TimeInterval = 30) -> (String?, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable ?? rclonePath)
        process.arguments = args
        process.environment = childEnv()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ("couldn’t run rclone: \(error.localizedDescription)", -1)
        }
        // Si el proceso excede el tiempo, se termina: la lectura del pipe devuelve
        // lo acumulado hasta entonces y waitUntilExit no queda bloqueado para siempre.
        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return (String(data: data, encoding: .utf8), process.terminationStatus)
    }
}
