import AppKit

// Genera AppIcon.icns con el mismo glifo de la barra, en azul celeste.
let sky = NSColor(srgbRed: 0x54/255.0, green: 0xC7/255.0, blue: 0xEC/255.0, alpha: 1)
let symbolName = "externaldrive.connected.to.line.below"

func makePNG(_ px: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let f = CGFloat(px)
    // Fondo squircle blanco (deja un pequeño margen como los íconos de macOS).
    let inset = f * 0.06
    let rect = NSRect(x: inset, y: inset, width: f - inset * 2, height: f - inset * 2)
    let radius = rect.width * 0.2237
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    // Glifo celeste centrado.
    let glyphPt = f * 0.5
    let cfg = NSImage.SymbolConfiguration(pointSize: glyphPt, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [sky]))
    if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(cfg) {
        sym.isTemplate = false
        let s = sym.size
        let origin = NSPoint(x: (f - s.width) / 2, y: (f - s.height) / 2)
        sym.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in specs {
    makePNG(px, to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset generado")
