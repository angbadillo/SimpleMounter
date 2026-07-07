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

    /// Color por tipo de servicio: identifica el servicio de un vistazo.
    static func tintNS(for type: String) -> NSColor {
        switch type {
        case "onedrive": // azul oscuro
            return NSColor(srgbRed: 0x1A/255.0, green: 0x5F/255.0, blue: 0xB4/255.0, alpha: 1)
        case "drive":    // amarillo-anaranjado
            return NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1)
        case "ftp":      return .systemRed
        case "sftp":     return .systemTeal
        default:         return skyBlueNS
        }
    }
    static func tint(for type: String) -> Color { Color(nsColor: tintNS(for: type)) }
}
