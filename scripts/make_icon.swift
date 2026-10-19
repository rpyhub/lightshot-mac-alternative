// Uygulama ikonunu çizer: assets/AppIcon.icns ve docs/icon.png üretir.   Kullanım: ./scripts/make_icon.sh
import Cocoa

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = NSAffineTransform(); t.scaleX(by: CGFloat(px) / 1024, yBy: CGFloat(px) / 1024); t.concat()

    // macOS ikon ızgarası: 1024 tuvalde 824'lük yuvarlak kare, çevresinde boşluk
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set(); NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.93, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.74, blue: 0.93, alpha: 1)])!
        .draw(in: body, angle: -50)
    NSGradient(colors: [NSColor(white: 1, alpha: 0.20), NSColor(white: 1, alpha: 0)])!   // üstte hafif ışık
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

    // seçim çerçevesi: kesikli kenar + 8 tutamaç (uygulamadaki seçim gibi)
    let frame = NSRect(x: 252, y: 300, width: 520, height: 424)
    let dash = NSBezierPath(rect: frame); dash.lineWidth = 15; dash.setLineDash([36, 26], count: 2, phase: 0)
    NSColor(white: 1, alpha: 0.95).setStroke(); dash.stroke()
    for fx in [frame.minX, frame.midX, frame.maxX] { for fy in [frame.minY, frame.midY, frame.maxY] where !(fx == frame.midX && fy == frame.midY) {
        let h = NSBezierPath(roundedRect: NSRect(x: fx - 24, y: fy - 24, width: 48, height: 48), xRadius: 10, yRadius: 10)
        NSColor.white.setFill(); h.fill()
        NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.93, alpha: 1).setStroke(); h.lineWidth = 9; h.stroke()
    } }

    // ortada "yükle" simgesi (bulut beyaz, ok mor)
    if let sym = NSImage(systemSymbolName: "icloud.and.arrow.up.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 300, weight: .bold).applying(.init(paletteColors: [NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.93, alpha: 1), .white]))) {
        let r = NSRect(x: 512 - sym.size.width / 2, y: 512 - sym.size.height / 2, width: sym.size.width, height: sym.size.height)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.25); sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -8); sh.set()
        sym.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let set = out + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/icon.png"))
print("ikon çizildi:", out)
