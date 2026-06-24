import AppKit
import SwiftUI

/// Identidad visual compartida.
enum Theme {
    /// Azul celeste de la app (#54C7EC).
    static let skyBlueNS = NSColor(srgbRed: 0x54/255.0, green: 0xC7/255.0, blue: 0xEC/255.0, alpha: 1)
    static let skyBlue = Color(nsColor: skyBlueNS)

    /// Símbolo SF por tipo de servicio rclone.
    static func symbolName(for type: String) -> String {
        switch type {
        case "drive":    return "externaldrive.badge.icloud"
        case "onedrive": return "cloud"
        case "sftp":     return "server.rack"
        case "ftp":      return "folder.badge.gearshape"
        default:         return "externaldrive"
        }
    }

    /// Color estable derivado del nombre, para distinguir cuentas del mismo tipo.
    static func accentNS(for name: String) -> NSColor {
        let palette: [NSColor] = [
            skyBlueNS,
            NSColor.systemTeal, NSColor.systemIndigo, NSColor.systemPurple,
            NSColor.systemPink, NSColor.systemOrange, NSColor.systemGreen
        ]
        // Hash determinista (estable entre ejecuciones).
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}
