import Foundation

/// Edición quirúrgica de rclone.conf (formato INI). Se usa en las operaciones
/// donde un secreto no debe pasar por argumentos de proceso — los argumentos son
/// visibles en `ps` para cualquier proceso local: guardar contraseñas y
/// renombrar secciones (que arrastran el token OAuth).
enum ConfigFile {

    /// true si rclone tiene el fichero cifrado (no es editable directamente).
    static func isEncrypted(_ text: String) -> Bool {
        text.hasPrefix("RCLONE_ENCRYPT")
    }

    /// Texto con `key = value` fijado dentro de la sección [remote], sustituyendo
    /// cualquier asignación previa de esa clave. nil si la sección no existe.
    static func settingValue(_ key: String, _ value: String,
                             remote: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let section = sectionRange(of: remote, in: lines) else { return nil }
        var body = Array(lines[(section.lowerBound + 1)..<section.upperBound])
        body.removeAll {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("\(key) =") || t.hasPrefix("\(key)=")
        }
        body.insert("\(key) = \(value)", at: 0)
        lines.replaceSubrange((section.lowerBound + 1)..<section.upperBound, with: body)
        return lines.joined(separator: "\n")
    }

    /// Texto con la sección [old] renombrada a [new] conservando todos sus
    /// campos. nil si [old] no existe o [new] ya existe.
    static func renamingSection(_ old: String, to new: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard sectionRange(of: new, in: lines) == nil,
              let section = sectionRange(of: old, in: lines) else { return nil }
        lines[section.lowerBound] = "[\(new)]"
        return lines.joined(separator: "\n")
    }

    /// Rango [cabecera, siguiente cabecera o fin) de una sección.
    private static func sectionRange(of remote: String, in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "[\(remote)]"
        }) else { return nil }
        var end = start + 1
        while end < lines.count,
              !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
        return start..<end
    }
}
