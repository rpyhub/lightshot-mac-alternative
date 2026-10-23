// Lightshot tarzı seçim ekranı: dondurulmuş ekran, seçim, çizim araçları, büyüteç, pencere seçimi, alt araç çubuğu
import Cocoa

enum Tool { case none, pen, line, arrow, rect, marker, text, step, blur }

func rectFrom(_ a: NSPoint, _ b: NSPoint) -> NSRect {
    NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}

func segDist(_ p: NSPoint, _ a: NSPoint, _ b: NSPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
    let t = l2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

struct Shape {
    var tool: Tool
    var pts: [NSPoint]
    var color: NSColor
    var text = ""        // metin aracı: yazı, adım aracı: numara
    var width: CGFloat = 3
    var fill = false     // sadece dikdörtgen

    var fontSize: CGFloat { 12 + width * 2 }
    var stepRadius: CGFloat { 10 + width * 2 }

    var bbox: NSRect {
        switch tool {
        case .text:
            return NSRect(origin: pts[0], size: (text as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: fontSize)]))
        case .step:
            return NSRect(x: pts[0].x - stepRadius, y: pts[0].y - stepRadius, width: stepRadius * 2, height: stepRadius * 2)
        case .pen, .marker:
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return NSRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        default:
            return rectFrom(pts[0], pts.last!)
        }
    }

    func hit(_ p: NSPoint) -> Bool {
        let tol = max(6, width + 3)
        switch tool {
        case .pen, .marker:
            return zip(pts, pts.dropFirst()).contains { segDist(p, $0, $1) <= tol } || (pts.count == 1 && hypot(p.x - pts[0].x, p.y - pts[0].y) <= tol)
        case .line, .arrow:
            return segDist(p, pts[0], pts.last!) <= tol
        case .rect:
            let b = bbox
            if fill { return b.insetBy(dx: -tol, dy: -tol).contains(p) }
            return b.insetBy(dx: -tol, dy: -tol).contains(p) && !b.insetBy(dx: tol, dy: tol).contains(p)
        case .blur, .text, .step:
            return bbox.insetBy(dx: -4, dy: -4).contains(p)
        case .none:
            return false
        }
    }

    mutating func move(_ dx: CGFloat, _ dy: CGFloat) { pts = pts.map { NSPoint(x: $0.x + dx, y: $0.y + dy) } }

    // bg/bounds: bulanıklaştırma ekran görüntüsünün kendi piksellerini kullanır
    func draw(bg: NSImage, bounds: NSRect) {
        color.set()
        switch tool {
        case .pen, .marker:
            let p = NSBezierPath()
            p.lineWidth = tool == .pen ? width : max(12, width * 4)
            p.lineCapStyle = .round; p.lineJoinStyle = .round
            p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }
            if pts.count == 1 { p.line(to: pts[0]) }
            if tool == .marker { color.withAlphaComponent(0.4).set() }
            p.stroke()
        case .line, .arrow:
            let a = pts[0], b = pts.last!
            let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round
            p.move(to: a); p.line(to: b); p.stroke()
            if tool == .arrow {
                let ang = atan2(b.y - a.y, b.x - a.x), len = 10 + width * 2
                let h = NSBezierPath()
                h.move(to: b)
                h.line(to: NSPoint(x: b.x - len * cos(ang - 0.45), y: b.y - len * sin(ang - 0.45)))
                h.line(to: NSPoint(x: b.x - len * cos(ang + 0.45), y: b.y - len * sin(ang + 0.45)))
                h.close(); h.fill()
            }
        case .rect:
            let r = rectFrom(pts[0], pts.last!)
            if fill { color.withAlphaComponent(0.35).setFill(); NSBezierPath(rect: r).fill(); color.set() }
            let p = NSBezierPath(rect: r); p.lineWidth = width; p.stroke()
        case .text:
            (text as NSString).draw(at: pts[0], withAttributes: [.font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: color])
        case .step:
            let b = bbox
            NSBezierPath(ovalIn: b).fill()
            let lum = color.usingColorSpace(.sRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: stepRadius * 1.1),
                                                        .foregroundColor: lum > 0.7 ? NSColor.black : NSColor.white]
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: b.midX - sz.width / 2, y: b.midY - sz.height / 2), withAttributes: attrs)
        case .blur:
            let r = rectFrom(pts[0], pts.last!)
            guard r.width > 2, r.height > 2 else { break }
            let sx = bg.size.width / bounds.width, sy = bg.size.height / bounds.height
            let src = NSRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
            let small = NSImage(size: NSSize(width: max(1, (r.width / 10).rounded()), height: max(1, (r.height / 10).rounded())))
            small.lockFocus()
            bg.draw(in: NSRect(origin: .zero, size: small.size), from: src, operation: .copy, fraction: 1)
            small.unlockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none
            small.draw(in: r)
            NSGraphicsContext.current?.imageInterpolation = .default
        case .none: break
        }
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // sol/üst ekranlar negatif koordinatta olabilir; macOS pencereyi başka ekrana kaydırmasın
    override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }
}

// Tüm ekranlar tek bir birleşik koordinat uzayında ("yerel": sol-alt köşe = tüm ekranların birleşiminin sol-altı).
// Seçim, çizimler ve araç çubukları bu uzayda yaşar; her ekranın penceresi (OverlayView) kendi parçasını çizer.
final class Session: NSObject, NSTextFieldDelegate {
    let full: NSImage      // tüm ekranların birleştirilmiş görüntüsü (nokta boyutu = U.size)
    let fullRep: NSBitmapImageRep?
    let fullCG: CGImage?   // GPU'ya yüklenen ve büyüteç/renk için örneklenen ham görüntü
    let U: NSRect          // ekranların global birleşimi
    let scale: CGFloat     // çıktı piksel yoğunluğu (en yüksek ekran ölçeği)
    var ub: NSRect { NSRect(origin: .zero, size: U.size) }
    var selGlobal: NSRect { sel.offsetBy(dx: U.minX, dy: U.minY) }
    var views: [OverlayView] = []

    var sel = NSRect.zero
    var shapes: [Shape] = []
    var undoStack: [[Shape]] = []
    var selected: Int?
    var current: Shape?
    var tool = Tool.none
    var color = NSColor.systemRed
    var lineWidth: CGFloat = 3
    var fillRects = false

    var dragStart: NSPoint?, moveOffset: NSPoint?, movingShape: NSPoint?
    var resizing: (Int, Int)?   // tutamak yönü: -1 sol/alt, 0 sabit, 1 sağ/üst
    let handleDirs = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    var windowRects: [NSRect] = []   // pencere seçimi: öndeki pencere önce
    var hoverRect: NSRect?
    var cursor: NSPoint?
    var colorFlash: Date?

    var textField: NSTextField?, textHost: OverlayView?
    var sideBar: NSStackView!, bottomBar: NSStackView!
    var toolButtons: [Tool: NSButton] = [:]
    var colorButton: NSButton!
    let sizeLabel = NSTextField(labelWithString: "")
    lazy var sideSize = sideBar.fittingSize       // çubuk boyutları sabit: her fare olayında Auto Layout çözülmesin
    lazy var bottomSize = bottomBar.fittingSize
    // "upload" | "search" | "ocr" | "pin" | "record" | "scroll" | "print" | "copy" | "save" | "close"; üçüncü parametre seçimin global dikdörtgeni
    var onAction: ((String, Shot?, NSRect?) -> Void)!

    init(full: NSImage, U: NSRect, scale: CGFloat) {
        self.full = full; self.U = U; self.scale = scale
        fullRep = full.representations.first as? NSBitmapImageRep
        fullCG = fullRep?.cgImage ?? full.cgImage(forProposedRect: nil, context: nil, hints: nil)
        super.init()
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white; sizeLabel.drawsBackground = true
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        sizeLabel.isHidden = true

        let tools: [(Tool, String, String)] = [
            (.none, "cursorarrow", "Seç / taşı (çizimleri düzenle, Delete siler)"),
            (.pen, "pencil", "Kalem"), (.line, "line.diagonal", "Çizgi"), (.arrow, "arrow.up.right", "Ok"),
            (.rect, "rectangle", "Dikdörtgen"), (.marker, "highlighter", "İşaretleyici"), (.text, "textformat", "Metin"),
            (.step, "1.circle", "Numaralı adım işareti"), (.blur, "eye.slash", "Bulanıklaştır (gizli bilgi)")]
        var side: [NSView] = tools.map { t, sym, tip in
            let b = button(sym, tip, #selector(pickTool(_:))); toolButtons[t] = b; return b
        }
        colorButton = button("circle.fill", "Renk", #selector(pickColor(_:)))
        colorButton.contentTintColor = color
        side += [colorButton, button("lineweight", "Kalınlık / dolgu", #selector(pickWidth(_:))),
                 button("arrow.uturn.backward", "Geri al (⌘Z)", #selector(undo))]
        sideBar = bar(side, .vertical)
        highlightTool()

        bottomBar = bar([
            { let b = button("icloud.and.arrow.up", "Yükle (⌘D)", #selector(doUpload)); b.contentTintColor = .systemBlue; return b }(),
            button("magnifyingglass", "Google'da benzer görselleri ara (önce yükler)", #selector(doSearch)),
            button("text.viewfinder", "Yazıyı kopyala (OCR)", #selector(doOCR)),
            button("pin", "Ekrana sabitle", #selector(doPin)),
            button("record.circle", "Bu alanı kaydet (video / GIF)", #selector(doRecord)),
            button("arrow.up.and.down.square", "Kaydırmalı yakalama (uzun sayfa)", #selector(doScroll)),
            button("printer", "Yazdır (⌘P)", #selector(doPrint)),
            button("doc.on.doc", "Kopyala (⌘C)", #selector(doCopy)),
            button("square.and.arrow.down", "Kaydet (⌘S)", #selector(doSave)),
            button("xmark", "Kapat (Esc)", #selector(doClose))], .horizontal)
    }

    func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let img = (NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: tip)!)
            .withSymbolConfiguration(cfg)!
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false; b.toolTip = tip; b.contentTintColor = NSColor(white: 0.15, alpha: 1)
        b.wantsLayer = true; b.layer?.cornerRadius = 5
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    func bar(_ views: [NSView], _ o: NSUserInterfaceLayoutOrientation) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = o; s.spacing = 2; s.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        s.wantsLayer = true
        s.layer?.backgroundColor = NSColor.white.cgColor; s.layer?.cornerRadius = 6
        s.layer?.borderWidth = 1; s.layer?.borderColor = NSColor(white: 0, alpha: 0.25).cgColor
        s.shadow = NSShadow(); s.layer?.shadowOpacity = 0.35; s.layer?.shadowRadius = 6; s.layer?.shadowOffset = CGSize(width: 0, height: -2)
        s.appearance = NSAppearance(named: .aqua)
        s.isHidden = true
        return s
    }

    // MARK: Katmanlar (GPU)
    // Ekran görüntüsü her ekranın görünümünde BİR KEZ katman içeriği olarak yüklenir; karartma, çerçeve ve tutamaçlar vektör katmanıdır.
    // Seçim değişince sadece katman yolları güncellenir: büyük görüntü hiç yeniden çizilmez (ve eski parça kalması mümkün olmaz).

    func redraw() { syncChrome(); shapesChanged(); updateLoupe() }

    func syncChrome() {
        let has = sel.width > 3 && sel.height > 3
        let handles = has ? handleDirs.map { d -> NSRect in let h = handlePoint(d); return NSRect(x: h.x - 4, y: h.y - 4, width: 8, height: 8) } : []
        for v in views { v.apply(sel: sel, hover: hoverRect, handles: handles) }
    }

    // Çizimleri sadece değişen bölgede (yerel koordinat) ya da tamamen yeniden çizdirir
    func shapesChanged(_ r: NSRect? = nil) {
        for v in views {
            guard let r else { v.shapesView.needsDisplay = true; continue }
            let i = r.intersection(v.localFrame)
            if !i.isNull, !i.isEmpty { v.shapesView.setNeedsDisplay(i.offsetBy(dx: -v.off.x, dy: -v.off.y)) }
        }
    }

    func drawShapes(offset o: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: -o.x, yBy: -o.y); t.concat()
        shapes.forEach { $0.draw(bg: full, bounds: ub) }
        if let c = current {
            if c.tool == .blur {   // sürüklerken pikselleştirmeyi her olayda yeniden hesaplama (~20 ms): hafif önizleme, fare bırakılınca asıl bulanıklaştırma
                let r = rectFrom(c.pts[0], c.pts.last!)
                NSColor(white: 1, alpha: 0.18).setFill(); NSBezierPath(rect: r).fill()
                let d = NSBezierPath(rect: r); d.setLineDash([5, 4], count: 2, phase: 0); NSColor.white.setStroke(); d.stroke()
            } else { c.draw(bg: full, bounds: ub) }
        }
        if let i = selected, shapes.indices.contains(i) {   // seçili çizimin çerçevesi
            let b = NSBezierPath(rect: shapes[i].bbox.insetBy(dx: -4, dy: -4))
            b.setLineDash([3, 3], count: 2, phase: 0); b.lineWidth = 1.5; NSColor.systemBlue.setStroke(); b.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // bir ekranın görünümüne düşen parça (piksel cinsinden kırpma; bellek paylaşılır, kopya yok)
    func screenImage(off: NSPoint, size: NSSize) -> CGImage? {
        guard let cg = fullCG else { return nil }
        let all = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let r = CGRect(x: off.x * scale, y: (U.height - off.y - size.height) * scale, width: size.width * scale, height: size.height * scale).integral
        return cg.cropping(to: r.intersection(all))
    }

    // MARK: Büyüteç ve renk seçici

    var loupeVisible: Bool {
        defaults.bool(forKey: "loupe") && cursor != nil && (sel.width < 3 || dragStart != nil || resizing != nil)
    }

    // imlecin altındaki piksel (sol-üst orijinli)
    func pixelIndex(_ c: NSPoint) -> (x: Int, y: Int)? {
        guard let cg = fullCG else { return nil }
        return (min(max(Int(floor(c.x * scale)), 0), cg.width - 1), min(max(Int(floor((U.height - c.y) * scale)), 0), cg.height - 1))
    }

    func color(atX x: Int, y: Int) -> NSColor? {
        guard let one = fullCG?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
    }

    // imlecin çevresindeki n x n piksel; kenara yakınsa dışarısı siyah
    func loupeCrop(_ x: Int, _ y: Int, n: Int = 15) -> CGImage? {
        guard let cg = fullCG else { return nil }
        let r = CGRect(x: x - n / 2, y: y - n / 2, width: n, height: n)
        if CGRect(x: 0, y: 0, width: cg.width, height: cg.height).contains(r) { return cg.cropping(to: r) }
        guard let ctx = makeContext(n, n, nil) else { return nil }
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.draw(cg, in: CGRect(x: -(x - n / 2), y: -(cg.height - (y - n / 2) - n), width: cg.width, height: cg.height))   // CG sol-alt orijinli
        return ctx.makeImage()
    }

    func updateLoupe() {
        guard loupeVisible, let c = cursor, let (x, y) = pixelIndex(c) else { views.forEach { $0.loupe.isHidden = true }; return }
        let col = color(atX: x, y: y) ?? .clear, crop = loupeCrop(x, y)
        let flashing = colorFlash.map { Date().timeIntervalSince($0) < 1.2 } ?? false
        for v in views {
            let l = v.loupe
            guard v.localFrame.contains(c) else { l.isHidden = true; continue }
            l.crop = crop; l.swatch = col; l.hexText = hex(col); l.posText = "\(x), \(y) px"; l.flashing = flashing
            let vr = v.localFrame, w = LoupeView.w, h = LoupeView.h
            var o = NSPoint(x: c.x + 22, y: c.y - 22 - h)
            if o.x + w > vr.maxX - 4 { o.x = c.x - 22 - w }      // sağ kenara değerse imlecin soluna
            if o.y < vr.minY + 4 { o.y = c.y + 22 }              // alta değerse imlecin üstüne
            o.x = max(o.x, vr.minX + 4); o.y = min(o.y, vr.maxY - h - 4)
            l.frame = NSRect(x: o.x - v.off.x, y: o.y - v.off.y, width: w, height: h)
            l.isHidden = false; l.needsDisplay = true
        }
    }

    func copyColor() {
        guard let c = cursor, let (x, y) = pixelIndex(c), let col = color(atX: x, y: y) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex(col), forType: .string)
        colorFlash = Date(); updateLoupe()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.updateLoupe() }
    }

    // MARK: Tutamaçlar ve araç çubukları

    func handlePoint(_ d: (Int, Int)) -> NSPoint {
        NSPoint(x: d.0 < 0 ? sel.minX : d.0 > 0 ? sel.maxX : sel.midX, y: d.1 < 0 ? sel.minY : d.1 > 0 ? sel.maxY : sel.midY)
    }

    func handleAt(_ p: NSPoint) -> (Int, Int)? {
        guard sel.width > 3, sel.height > 3 else { return nil }
        return handleDirs.first { let h = handlePoint($0); return abs(h.x - p.x) <= 7 && abs(h.y - p.y) <= 7 }
    }

    // Çubuğu merkezine en yakın (içeren) ekrana koyar ve o ekranın içine sığdırır; yerleştiği yerel dikdörtgeni döndürür
    @discardableResult func place(_ v: NSView, _ r: NSRect) -> NSRect {
        let c = NSPoint(x: min(max(r.midX, 0), ub.maxX - 1), y: min(max(r.midY, 0), ub.maxY - 1))
        func dist(_ f: NSRect) -> CGFloat { hypot(max(f.minX - c.x, 0, c.x - f.maxX), max(f.minY - c.y, 0, c.y - f.maxY)) }
        guard let host = views.min(by: { dist($0.localFrame) < dist($1.localFrame) }) else { return r }
        let f = host.localFrame
        let o = NSPoint(x: min(max(r.minX, f.minX), max(f.maxX - r.width, f.minX)), y: min(max(r.minY, f.minY), max(f.maxY - r.height, f.minY)))
        if v.superview !== host { v.removeFromSuperview(); host.addSubview(v) }
        v.setFrameSize(r.size)
        v.setFrameOrigin(NSPoint(x: o.x - f.minX, y: o.y - f.minY))
        return NSRect(origin: o, size: r.size)
    }

    func layoutBars() {
        let has = sel.width > 3 && sel.height > 3
        [sideBar!, bottomBar!, sizeLabel].forEach { $0.isHidden = !has }
        guard has else { return }
        sizeLabel.stringValue = " \(Int(sel.width * scale))x\(Int(sel.height * scale)) "; sizeLabel.sizeToFit()
        place(sizeLabel, NSRect(origin: NSPoint(x: sel.minX, y: sel.maxY + 4), size: sizeLabel.frame.size))
        let sb = sideSize, bb = bottomSize
        let side = place(sideBar, NSRect(origin: NSPoint(x: sel.maxX + 6, y: sel.maxY - sb.height), size: sb))
        var bottom = NSRect(origin: NSPoint(x: sel.maxX - bb.width, y: sel.minY - 6 - bb.height), size: bb)
        if bottom.insetBy(dx: -4, dy: -4).intersects(side) { bottom.origin.x = side.minX - 6 - bb.width }   // iki çubuk üst üste binmesin
        place(bottomBar, bottom)
    }

    // MARK: Düzenleme

    func snapshot() { undoStack.append(shapes); if undoStack.count > 50 { undoStack.removeFirst() } }

    func hitShape(_ p: NSPoint) -> Int? { shapes.indices.reversed().first { shapes[$0].hit(p) } }

    func applyToSelected(_ f: (inout Shape) -> Void) {
        guard let i = selected, shapes.indices.contains(i) else { return }
        snapshot(); f(&shapes[i]); redraw()
    }

    func deleteSelected() {
        guard let i = selected, shapes.indices.contains(i) else { return }
        snapshot(); shapes.remove(at: i); selected = nil; redraw()
    }

    // MARK: Fare (p: birleşik yerel koordinat)

    func mouseDown(_ p: NSPoint, _ v: OverlayView) {
        commitText()
        cursor = p
        if let d = handleAt(p) {
            resizing = d; selected = nil
        } else if tool == .none, sel.contains(p), let i = hitShape(p) {
            selected = i; snapshot(); movingShape = p
        } else if tool != .none && sel.contains(p) {
            selected = nil
            if tool == .text { startText(at: p, in: v); return }
            if tool == .step {
                snapshot()
                let n = (shapes.filter { $0.tool == .step }.compactMap { Int($0.text) }.max() ?? 0) + 1
                shapes.append(Shape(tool: .step, pts: [p], color: color, text: "\(n)", width: lineWidth))
                redraw(); return
            }
            current = Shape(tool: tool, pts: [p], color: color, width: lineWidth, fill: fillRects && tool == .rect)
        } else if sel.contains(p) {
            selected = nil; moveOffset = NSPoint(x: p.x - sel.minX, y: p.y - sel.minY)
        } else {
            selected = nil; dragStart = p; sel = .zero; shapes = []; undoStack = []; layoutBars()
        }
        redraw()
    }

    func mouseDragged(_ p: NSPoint) {
        cursor = p
        if current != nil {
            let before = current!.bbox
            if tool == .pen || tool == .marker { current!.pts.append(p) } else { current!.pts = [current!.pts[0], p] }
            let pad = current!.width * 4 + 24
            shapesChanged(before.union(current!.bbox).insetBy(dx: -pad, dy: -pad))
        } else if let last = movingShape, let i = selected, shapes.indices.contains(i) {
            let before = shapes[i].bbox
            shapes[i].move(p.x - last.x, p.y - last.y); movingShape = p
            shapesChanged(before.union(shapes[i].bbox).insetBy(dx: -24, dy: -24))
        } else if let d = resizing {
            var x0 = sel.minX, x1 = sel.maxX, y0 = sel.minY, y1 = sel.maxY
            if d.0 < 0 { x0 = p.x } else if d.0 > 0 { x1 = p.x }
            if d.1 < 0 { y0 = p.y } else if d.1 > 0 { y1 = p.y }
            sel = rectFrom(NSPoint(x: x0, y: y0), NSPoint(x: x1, y: y1)).intersection(ub)
            layoutBars(); syncChrome()
        } else if let o = moveOffset {
            // çizimler ekrana sabit kalır (bulanıklaştırma ekran pikselleriyle eşleşsin diye), sadece seçim taşınır
            sel.origin = NSPoint(x: min(max(p.x - o.x, 0), ub.maxX - sel.width), y: min(max(p.y - o.y, 0), ub.maxY - sel.height))
            layoutBars(); syncChrome()
        } else if let s = dragStart {
            sel = rectFrom(s, p).intersection(ub)
            layoutBars(); syncChrome()
        }
        updateLoupe()
    }

    func mouseUp() {
        if let c = current { snapshot(); shapes.append(c); current = nil }
        // sürükleme olmadan tıklandıysa: üzerindeki pencerenin tamamını seç
        if dragStart != nil, sel.width < 4, sel.height < 4 {
            if let r = hoverRect?.intersection(ub), !r.isNull { sel = r; hoverRect = nil } else { sel = .zero }
            layoutBars()
        }
        dragStart = nil; moveOffset = nil; resizing = nil; movingShape = nil
        redraw()
    }

    func mouseMoved(_ p: NSPoint) {
        let oldHover = hoverRect
        cursor = p
        if sel.width < 3, dragStart == nil { hoverRect = windowRects.first { $0.contains(p) } }
        if hoverRect != oldHover { syncChrome() }
        updateLoupe()
    }

    func keyDown(_ e: NSEvent) {
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd, e.charactersIgnoringModifiers ?? "") {
        case (53, _, _): doClose()
        case (36, _, _), (_, true, "d"): doUpload()
        case (_, true, "c"): doCopy()
        case (_, true, "p"): doPrint()
        case (_, true, "s"): doSave()
        case (_, true, "z"): undo()
        case (51, _, _), (117, _, _): deleteSelected()
        case (_, false, "c"): copyColor()
        default: NSSound.beep()
        }
    }

    // MARK: Metin

    func startText(at p: NSPoint, in v: OverlayView) {
        let tf = NSTextField(frame: NSRect(x: p.x - v.off.x, y: p.y - v.off.y, width: 240, height: 12 + (12 + lineWidth * 2) * 1.4))
        tf.font = .boldSystemFont(ofSize: 12 + lineWidth * 2); tf.textColor = color
        tf.drawsBackground = false; tf.isBordered = true; tf.focusRingType = .none
        tf.placeholderString = "Metin yazın, Enter"
        tf.delegate = self
        v.addSubview(tf); v.window?.makeFirstResponder(tf); textField = tf; textHost = v
    }

    func controlTextDidEndEditing(_ n: Notification) { commitText() }

    func commitText() {
        guard let tf = textField, let v = textHost else { return }
        textField = nil; textHost = nil
        if !tf.stringValue.isEmpty {
            snapshot()
            shapes.append(Shape(tool: .text, pts: [NSPoint(x: tf.frame.minX + v.off.x + 2, y: tf.frame.minY + v.off.y + 2)],
                                color: color, text: tf.stringValue, width: lineWidth))
        }
        tf.removeFromSuperview(); v.window?.makeFirstResponder(v); redraw()
    }

    // MARK: Araçlar

    func highlightTool() {
        toolButtons.forEach { t, b in
            b.contentTintColor = t == tool ? .white : NSColor(white: 0.15, alpha: 1)
            b.layer?.backgroundColor = t == tool ? NSColor.systemBlue.cgColor : nil
        }
    }

    @objc func pickTool(_ b: NSButton) {
        tool = toolButtons.first { $0.value === b }!.key
        selected = nil; highlightTool(); redraw()
    }

    @objc func pickColor(_ b: NSButton) {
        let m = NSMenu()
        let colors: [(String, NSColor)] = [("Kırmızı", .systemRed), ("Turuncu", .systemOrange), ("Sarı", .systemYellow),
            ("Yeşil", .systemGreen), ("Mavi", .systemBlue), ("Mor", .systemPurple), ("Siyah", .black), ("Beyaz", .white)]
        for (name, c) in colors {
            let it = m.addItem(withTitle: name, action: #selector(setColor(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = c
            it.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [c]))
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height), in: b)
    }

    @objc func setColor(_ it: NSMenuItem) {
        color = it.representedObject as! NSColor; colorButton.contentTintColor = color
        let c = color
        applyToSelected { $0.color = c }
    }

    @objc func pickWidth(_ b: NSButton) {
        let m = NSMenu()
        for (name, w) in [("İnce", 2.0), ("Orta", 3.0), ("Kalın", 6.0), ("Çok kalın", 10.0)] as [(String, CGFloat)] {
            let it = m.addItem(withTitle: name, action: #selector(setWidth(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = w; it.state = lineWidth == w ? .on : .off
        }
        m.addItem(.separator())
        let f = m.addItem(withTitle: "Dikdörtgeni doldur", action: #selector(toggleFill), keyEquivalent: "")
        f.target = self; f.state = fillRects ? .on : .off
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height), in: b)
    }

    @objc func setWidth(_ it: NSMenuItem) {
        lineWidth = it.representedObject as! CGFloat
        let w = lineWidth
        applyToSelected { $0.width = w }
    }

    @objc func toggleFill() {
        fillRects.toggle()
        let f = fillRects
        applyToSelected { if $0.tool == .rect { $0.fill = f } }
    }

    @objc func undo() {
        if let s = undoStack.popLast() { shapes = s; selected = nil; redraw() }
    }

    // MARK: Çıktı

    func render() -> Shot? {
        commitText()
        guard sel.width > 3, sel.height > 3 else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sel.width * scale), pixelsHigh: Int(sel.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = sel.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let t = NSAffineTransform(); t.translateX(by: -sel.minX, yBy: -sel.minY); t.concat()
        full.draw(in: ub)
        shapes.forEach { $0.draw(bg: full, bounds: ub) }
        NSGraphicsContext.restoreGraphicsState()
        return Shot(rep)
    }

    func fire(_ action: String, image: Bool = true) {
        guard sel.width > 3, sel.height > 3 else { return }
        commitText()
        let shot = image ? render() : nil
        if image && shot == nil { return }
        onAction(action, shot, selGlobal)
    }

    @objc func doUpload() { fire("upload") }
    @objc func doSearch() { fire("search") }
    @objc func doOCR() { fire("ocr") }
    @objc func doPin() { fire("pin") }
    @objc func doRecord() { fire("record", image: false) }
    @objc func doScroll() { fire("scroll", image: false) }
    @objc func doPrint() { fire("print") }
    @objc func doCopy() { fire("copy") }
    @objc func doSave() { fire("save") }
    @objc func doClose() { onAction("close", nil, nil) }
}

// Bir ekranın penceresindeki görünüm: katmanları (ekran görüntüsü, karartma/çerçeve, çizimler, büyüteç) taşır, fare/klavyeyi Session'a iletir
final class OverlayView: NSView {
    weak var session: Session?   // zayıf: Session ↔ görünüm güçlü döngüsü her yakalamada tüm ekran görüntüsünü bellekte bırakıyordu
    let off: NSPoint             // bu ekranın birleşik yerel koordinattaki sol-alt köşesi
    let chrome: ChromeView, shapesView: ShapesView, loupe: LoupeView

    init(frame: NSRect, session: Session, off: NSPoint) {
        self.session = session; self.off = off
        let own = NSRect(origin: .zero, size: frame.size)
        chrome = ChromeView(frame: own)
        shapesView = ShapesView(frame: own, session: session, off: off)
        loupe = LoupeView(frame: NSRect(x: 0, y: 0, width: LoupeView.w, height: LoupeView.h))
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        if let img = session.screenImage(off: off, size: frame.size) { addSubview(BackgroundView(frame: own, image: img, scale: session.scale)) }
        addSubview(chrome); addSubview(shapesView)
        loupe.isHidden = true; addSubview(loupe)
    }
    required init?(coder: NSCoder) { fatalError() }

    var localFrame: NSRect { NSRect(origin: off, size: bounds.size) }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // Session'ın birleşik yerel koordinatındaki durumu bu ekranın katmanlarına yansıtır
    func apply(sel: NSRect, hover: NSRect?, handles: [NSRect]) {
        func l(_ r: NSRect) -> NSRect { r.offsetBy(dx: -off.x, dy: -off.y) }
        let has = sel.width > 0
        chrome.apply(sel: has ? l(sel) : nil, hover: hover.map(l), handles: handles.map(l))
        shapesView.setMask(has ? l(sel) : nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // fare sürüklemesi başka ekrana taşsa bile olaylar bu pencereye gelir; global konuma çevirmek yeterli
    func local(_ e: NSEvent) -> NSPoint {
        guard let u = session?.U, let w = window else { return .zero }
        let g = w.convertPoint(toScreen: e.locationInWindow)
        return NSPoint(x: g.x - u.minX, y: g.y - u.minY)
    }

    override func mouseDown(with e: NSEvent) { session?.mouseDown(local(e), self) }
    override func mouseDragged(with e: NSEvent) { session?.mouseDragged(local(e)) }
    override func mouseUp(with e: NSEvent) { session?.mouseUp() }
    override func mouseMoved(with e: NSEvent) { session?.mouseMoved(local(e)) }
    override func keyDown(with e: NSEvent) { session?.keyDown(e) }
}

// Ekran görüntüsünün bu ekrana düşen parçası: katman içeriği olarak bir kez GPU'ya yüklenir, bir daha çizilmez
final class BackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    init(frame: NSRect, image: CGImage, scale: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image; layer?.contentsGravity = .resize; layer?.contentsScale = scale
        layer?.magnificationFilter = .nearest   // 1:1 gösterim, bulanıklaşmasın
    }
    required init?(coder: NSCoder) { fatalError() }
}

// Karartma (seçimin dışı), seçim çerçevesi, tutamaçlar ve pencere vurgusu: vektör katmanları, yolları güncellemek yeterli
final class ChromeView: NSView {
    private let dim = CAShapeLayer(), hoverL = CAShapeLayer(), edge = CAShapeLayer(), dash = CAShapeLayer(), handlesL = CAShapeLayer()
    private var all: [CAShapeLayer] { [dim, hoverL, edge, dash, handlesL] }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override func hitTest(_ p: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dim.fillRule = .evenOdd; dim.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        hoverL.fillColor = nil; hoverL.strokeColor = NSColor.systemBlue.cgColor; hoverL.lineWidth = 3
        edge.fillColor = nil; edge.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor; edge.lineWidth = 1   // her zemin üstünde görünsün diye koyu alt çizgi
        dash.fillColor = nil; dash.strokeColor = NSColor.white.cgColor; dash.lineWidth = 1; dash.lineDashPattern = [4, 4]
        handlesL.fillColor = NSColor.white.cgColor; handlesL.strokeColor = NSColor.systemBlue.cgColor; handlesL.lineWidth = 1.5
        for l in all { l.frame = bounds; l.contentsScale = 2; layer?.addSublayer(l) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        for l in all { l.contentsScale = s }
    }

    func apply(sel: NSRect?, hover: NSRect?, handles: [NSRect]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)   // örtük animasyon (0,25 sn kayma) olmasın
        let p = CGMutablePath(); p.addRect(bounds)
        if let h = sel ?? hover { p.addRect(h) }
        dim.path = p
        hoverL.path = (sel == nil ? hover : nil).map { CGPath(rect: $0.insetBy(dx: 1.5, dy: 1.5), transform: nil) }
        let edgePath = sel.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        edge.path = edgePath; dash.path = edgePath
        let hp = CGMutablePath(); handles.forEach { hp.addRect($0) }
        handlesL.path = handles.isEmpty ? nil : hp
        CATransaction.commit()
    }
}

// Çizimler (ok, metin, bulanıklaştırma ...): sadece çizimler değişince yeniden çizilir; seçimin dışı katman maskesiyle gizlenir
final class ShapesView: NSView {
    weak var session: Session?
    let off: NSPoint
    private let maskLayer = CAShapeLayer()

    init(frame: NSRect, session: Session, off: NSPoint) {
        self.session = session; self.off = off
        super.init(frame: frame)
        wantsLayer = true
        maskLayer.frame = bounds; maskLayer.fillColor = NSColor.black.cgColor
        layer?.mask = maskLayer
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ dirty: NSRect) { session?.drawShapes(offset: off) }

    func setMask(_ r: NSRect?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        maskLayer.path = r.map { CGPath(rect: $0, transform: nil) }
        CATransaction.commit()
    }
}

// Büyüteç ve renk bilgisi: küçük, kendi görünümü; her fare hareketinde sadece bu küçük alan yenilenir
final class LoupeView: NSView {
    static let w: CGFloat = 156, h: CGFloat = 164
    var crop: CGImage?, swatch = NSColor.clear, hexText = "", posText = "", flashing = false
    override func hitTest(_ p: NSPoint) -> NSView? { nil }

    override func draw(_ r: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n: CGFloat = 15, cell: CGFloat = 8, size = n * cell, labelH: CGFloat = 44
        let box = NSRect(x: 0, y: labelH, width: size, height: size)
        ctx.saveGState()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).addClip()
        ctx.interpolationQuality = .none   // pikseller net kare görünsün
        NSColor.black.setFill(); box.fill()
        if let c = crop { ctx.draw(c, in: box) }
        ctx.restoreGState()
        let cellRect = NSRect(x: box.minX + 7 * cell, y: box.minY + 7 * cell, width: cell, height: cell)
        NSColor.black.setStroke(); NSBezierPath(rect: cellRect.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke(); NSBezierPath(rect: cellRect).stroke()
        NSColor(white: 1, alpha: 0.9).setStroke(); let bd = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6); bd.lineWidth = 2; bd.stroke()

        let label = NSRect(x: 0, y: 0, width: Self.w, height: labelH - 6)
        NSColor(white: 0.1, alpha: 0.92).setFill(); NSBezierPath(roundedRect: label, xRadius: 6, yRadius: 6).fill()
        let a1: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let a2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(white: 0.7, alpha: 1)]
        let sw = NSRect(x: label.minX + 8, y: label.minY + 21, width: 12, height: 12)
        swatch.setFill(); NSBezierPath(roundedRect: sw, xRadius: 2, yRadius: 2).fill()
        NSColor.white.setStroke(); NSBezierPath(roundedRect: sw, xRadius: 2, yRadius: 2).stroke()
        (hexText as NSString).draw(at: NSPoint(x: label.minX + 26, y: label.minY + 19), withAttributes: a1)
        (posText as NSString).draw(at: NSPoint(x: label.minX + 8, y: label.minY + 4), withAttributes: a2)
        ((flashing ? "Kopyalandı ✓" : "C: rengi kopyala") as NSString).draw(at: NSPoint(x: label.minX + 84, y: label.minY + 4),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: flashing ? NSColor.systemGreen : NSColor(white: 0.7, alpha: 1)])
    }
}

// Sağ altta çıkan yükleme bildirimi (Lightshot'taki gibi)
final class Toast {
    static var panel: NSPanel?
    static var timer: Timer?
    static var link = ""

    static func show(_ title: String, link: String? = nil, seconds: Double? = nil) {
        panel?.close(); timer?.invalidate()
        let w: CGFloat = 360, h: CGFloat = link == nil ? 44 : 92
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar; p.isReleasedWhenClosed = false; p.hasShadow = true
        p.backgroundColor = .clear; p.isOpaque = false
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        v.wantsLayer = true; v.layer?.cornerRadius = 12
        v.layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.97).cgColor
        v.layer?.borderWidth = 1; v.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        p.contentView = v

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold); t.textColor = .white; t.lineBreakMode = .byTruncatingTail
        t.frame = NSRect(x: 16, y: h - 30, width: w - 32, height: 18); v.addSubview(t)
        if let link {
            Toast.link = link
            let l = NSTextField(labelWithString: link)
            l.font = .systemFont(ofSize: 12); l.textColor = NSColor(calibratedRed: 0.55, green: 0.75, blue: 1, alpha: 1)
            l.lineBreakMode = .byTruncatingMiddle; l.isSelectable = true
            l.frame = NSRect(x: 16, y: h - 52, width: w - 32, height: 16); v.addSubview(l)
            v.addSubview(pill("QR", NSColor(white: 0.32, alpha: 1), #selector(showLinkQR), NSRect(x: w - 232, y: 12, width: 52, height: 26)))
            v.addSubview(pill("Kopyala", .systemBlue, #selector(copyLink), NSRect(x: w - 172, y: 12, width: 76, height: 26)))
            v.addSubview(pill("Aç", NSColor(white: 0.32, alpha: 1), #selector(openLink), NSRect(x: w - 90, y: 12, width: 74, height: 26)))
        }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.maxX - w - 16, y: vf.minY + 16))
        p.orderFrontRegardless()
        panel = p
        // "…" ile biten (yükleniyor) bildirim işlem bitene kadar kalır; diğerleri kısa süre
        if !title.hasSuffix("…") {
            timer = Timer.scheduledTimer(withTimeInterval: seconds ?? (link == nil ? 2 : 5), repeats: false) { _ in panel?.close() }
        }
    }

    static func pill(_ title: String, _ color: NSColor, _ action: Selector, _ frame: NSRect) -> NSButton {
        let b = NSButton(frame: frame)
        b.isBordered = false; b.target = Toast.self; b.action = action
        b.wantsLayer = true; b.layer?.backgroundColor = color.cgColor; b.layer?.cornerRadius = 6
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        return b
    }

    @objc static func openLink() {
        if let u = URL(string: link) { NSWorkspace.shared.open(u) }; panel?.close()
    }
    @objc static func copyLink() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(formatLink(link), forType: .string)
        show("Link kopyalandı ✓")
    }
    @objc static func showLinkQR() { showQR(link); panel?.close() }
}
