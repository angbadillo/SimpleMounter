import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let rclone = RcloneManager()
    private var addWindow: NSWindow?
    private var prefsWindow: NSWindow?
    private var editWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()   // habilita ⌘C/⌘V/⌘X en los campos de texto
        rclone.setupNotifications()
        rclone.startWatchdog()   // re-monta automáticamente las conexiones que se caigan
        rclone.onChange = { [weak self] in self?.refreshStatusIcon() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Aviso temprano si falta rclone (la app no puede hacer nada sin él).
        if !rclone.rcloneInstalled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showRcloneHelp() }
        }

        // Montar al arrancar las conexiones marcadas (tras leer la config).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rclone.mountAutoMounts()
        }
    }

    /// Ícono azul celeste; cambia a relleno cuando hay algo montado.
    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let anyMounted = !rclone.listRemotes().filter { rclone.isMounted($0.name) }.isEmpty
        let symbol = anyMounted ? "externaldrive.connected.to.line.below.fill"
                                : "externaldrive.connected.to.line.below"
        let config = NSImage.SymbolConfiguration(paletteColors: [Theme.skyBlueNS])
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SimpleMounter")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        button.image = image
    }

    // MARK: - Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let remotes = rclone.listRemotes()
        let mountedCount = remotes.filter { rclone.isMounted($0.name) }.count

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let title = "SimpleMounter \(version)" + (mountedCount > 0 ? " — \(mountedCount) mounted" : "")
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !rclone.rcloneInstalled {
            let warn = NSMenuItem(title: "⚠︎ rclone is not installed", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
            addItem(to: menu, "How to install rclone…", #selector(showRcloneHelp), symbol: "questionmark.circle")
        } else if remotes.isEmpty {
            let empty = NSMenuItem(title: "No connections — use “Add connection…”",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for r in remotes { menu.addItem(remoteItem(r)) }
            let unmounted = remotes.filter { !rclone.isMounted($0.name) }.count
            if remotes.count > 1 {
                menu.addItem(.separator())
                if unmounted > 0 { addItem(to: menu, "Mount all", #selector(mountAll), symbol: "arrow.down.circle") }
                if mountedCount > 0 { addItem(to: menu, "Unmount all", #selector(unmountAllAction), symbol: "eject") }
            }
        }

        menu.addItem(.separator())
        addItem(to: menu, "Add connection…", #selector(showAddConnection), symbol: "plus")
        addItem(to: menu, "Open mounts folder", #selector(openMountsFolder), symbol: "folder")
        addItem(to: menu, "Preferences…", #selector(showPreferences), key: ",", symbol: "gearshape")
        menu.addItem(.separator())
        addItem(to: menu, "Quit", #selector(quit), key: "q")
    }

    private func remoteItem(_ r: Remote) -> NSMenuItem {
        let mounted = rclone.isMounted(r.name)
        let busy = rclone.isBusy(r.name)
        var status: String = busy ? "connecting…" : (mounted ? rclone.mountPoint(for: r.name).path : "not mounted")
        if mounted, let free = rclone.freeSpace(r.name) { status += " · \(free)" }

        let item = NSMenuItem()
        item.attributedTitle = twoLineTitle(name: r.name, subtitle: "\(r.prettyType) · \(status)")
        item.image = tintedSymbol(Theme.symbolName(for: r.type),
                                  color: mounted ? .systemGreen : Theme.accentNS(for: r.name))

        let sub = NSMenu()
        if busy {
            let i = NSMenuItem(title: "Working…", action: nil, keyEquivalent: ""); i.isEnabled = false
            sub.addItem(i)
        } else if mounted {
            addItem(to: sub, "Unmount", #selector(unmountSelected), represented: r.name)
            addItem(to: sub, "Open in Finder", #selector(openInFinder), represented: r.name)
        } else {
            addItem(to: sub, "Mount", #selector(mountSelected), represented: r.name)
        }
        sub.addItem(.separator())
        addItem(to: sub, "Edit…", #selector(editSelected), represented: r.name)
        addItem(to: sub, "View log", #selector(showLog), represented: r.name)
        if r.isOAuth {
            addItem(to: sub, "Reconnect (re-authorize)", #selector(reconnectSelected), represented: r.name)
        }
        sub.addItem(.separator())
        addItem(to: sub, "Remove…", #selector(deleteSelected), represented: r.name)
        item.submenu = sub
        return item
    }

    private func twoLineTitle(name: String, subtitle: String) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: name,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                         .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(
            string: "\n\(subtitle)",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        return s
    }

    private func tintedSymbol(_ symbol: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        img?.isTemplate = false
        return img
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector,
                         key: String = "", symbol: String? = nil, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = represented
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    // MARK: - Acciones de conexión

    @objc private func mountSelected(_ s: NSMenuItem) { if let n = s.representedObject as? String { rclone.mount(n) } }
    @objc private func unmountSelected(_ s: NSMenuItem) { if let n = s.representedObject as? String { rclone.unmount(n) } }
    @objc private func openInFinder(_ s: NSMenuItem) {
        if let n = s.representedObject as? String { NSWorkspace.shared.open(rclone.mountPoint(for: n)) }
    }
    @objc private func showLog(_ s: NSMenuItem) {
        guard let n = s.representedObject as? String else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SimpleMounter/\(n).log")
        NSWorkspace.shared.open(url)
    }
    @objc private func reconnectSelected(_ s: NSMenuItem) {
        guard let n = s.representedObject as? String else { return }
        rclone.reconnect(name: n) { _, _ in }
    }
    @objc private func editSelected(_ s: NSMenuItem) {
        guard let n = s.representedObject as? String,
              let remote = rclone.listRemotes().first(where: { $0.name == n }) else { return }
        showEditConnection(remote)
    }
    @objc private func deleteSelected(_ s: NSMenuItem) {
        guard let n = s.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(n)”?"
        alert.informativeText = "This removes the connection from rclone. It does not delete any files on the cloud or server."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { rclone.deleteRemote(n) }
    }

    @objc private func openMountsFolder() {
        try? FileManager.default.createDirectory(at: rclone.mountBase, withIntermediateDirectories: true)
        NSWorkspace.shared.open(rclone.mountBase)
    }

    @objc private func mountAll() { rclone.mountAll() }
    @objc private func unmountAllAction() { rclone.unmountAll() }

    @objc private func showRcloneHelp() {
        let alert = NSAlert()
        alert.messageText = "rclone is not installed"
        alert.informativeText = """
        SimpleMounter uses rclone to connect and mount. Install it with Homebrew:

            brew install rclone

        Then restart SimpleMounter.
        """
        alert.addButton(withTitle: "Copy command")
        alert.addButton(withTitle: "Open rclone.org")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install rclone", forType: .string)
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://rclone.org/install/") { NSWorkspace.shared.open(url) }
        default: break
        }
    }

    // MARK: - Ventanas

    @objc private func showAddConnection() {
        let window = makeWindow(title: "Add connection")
        let view = AddConnectionView(manager: rclone) { [weak window] in window?.close() }
        window.contentViewController = NSHostingController(rootView: view)
        present(window); addWindow = window
    }

    private func showEditConnection(_ remote: Remote) {
        let window = makeWindow(title: "Edit connection")
        let view = EditConnectionView(manager: rclone, original: remote) { [weak self, weak window] in
            window?.close()
            self?.refreshStatusIcon()
        }
        window.contentViewController = NSHostingController(rootView: view)
        present(window); editWindow = window
    }

    @objc private func showPreferences() {
        let window = makeWindow(title: "Preferences")
        let view = PreferencesView(manager: rclone) { [weak self] in self?.refreshStatusIcon() }
        window.contentViewController = NSHostingController(rootView: view)
        present(window); prefsWindow = window
    }

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private func present(_ window: NSWindow) {
        if let fitting = window.contentViewController?.view.fittingSize {
            let size = NSSize(width: max(fitting.width, 380), height: max(fitting.height, 200))
            window.setContentSize(size)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { rclone.unmountAll(); NSApp.terminate(nil) }

    /// Menú principal mínimo. En apps de barra de menú (.accessory) no se muestra,
    /// pero sus atajos (⌘X/⌘C/⌘V/⌘A) sí se enrutan a los campos de texto enfocados.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit SimpleMounter", action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
