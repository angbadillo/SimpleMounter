import Foundation
import ServiceManagement

/// Preferencias persistentes (UserDefaults) + login item (SMAppService).
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let mountBase = "mountBase"
        static let notifications = "notificationsEnabled"
        static let autoMount = "autoMountNames"
    }

    @Published var mountBasePath: String {
        didSet { defaults.set(mountBasePath, forKey: Keys.mountBase) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published var autoMountNames: Set<String> {
        didSet { defaults.set(Array(autoMountNames), forKey: Keys.autoMount) }
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultBase = home.appendingPathComponent("Mounts").path
        mountBasePath = defaults.string(forKey: Keys.mountBase) ?? defaultBase
        notificationsEnabled = (defaults.object(forKey: Keys.notifications) as? Bool) ?? true
        autoMountNames = Set(defaults.stringArray(forKey: Keys.autoMount) ?? [])
    }

    func toggleAutoMount(_ name: String, on: Bool) {
        if on { autoMountNames.insert(name) } else { autoMountNames.remove(name) }
    }

    // MARK: - Login item

    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
            return false
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("SimpleMounter: error login item: \(error)")
            }
        }
    }
}
