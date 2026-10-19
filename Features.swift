// LightShotMac — ek özellikler: OCR, ekrana sabitleme, QR, S3/R2 yükleme, pencere listesi, GIF, kaydırmalı yakalama
import Cocoa
import Vision
import CryptoKit
import AVFoundation
import UniformTypeIdentifiers
import CoreImage
import ApplicationServices

// MARK: Yakalanan görüntü: kodlama bir kez ve arka planda yapılır (PNG/JPG), panoya/OCR/yazdırmaya hiç kodlanmadan gider

final class Shot {
    let rep: NSBitmapImageRep
    private var cached: (data: Data, ext: String, mime: String)?
    private let lock = NSLock()
    init(_ rep: NSBitmapImageRep) { self.rep = rep }

    var image: NSImage { let i = NSImage(size: rep.size); i.addRepresentation(rep); return i }

    // Ayarlardaki biçim; JPG doğrudan görüntüden üretilir (PNG'den çevrilmez). Ağır iş: ana iş parçacığında çağırma.
    var encoded: (data: Data, ext: String, mime: String)? {
        lock.lock(); defer { lock.unlock() }
        if cached == nil {
            if defaults.string(forKey: "format") == "jpg",
               let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: defaults.double(forKey: "quality")]) {
                cached = (jpg, "jpg", "image/jpeg")
            } else if let png = rep.representation(using: .png, properties: [:]) {
                cached = (png, "png", "image/png")
            }
        }
        return cached
    }
}

// Sunucudan gelen link güvenilmez veri: sadece http(s) açılır (file:// ya da özel uygulama şemaları açılmasın)
func safeLink(_ s: String?) -> String? {
    guard let s, let u = URL(string: s), let sc = u.scheme?.lowercased(), sc == "https" || sc == "http", u.host != nil else { return nil }
    return s
}

// MARK: Anahtarlık (S3 gizli anahtarı düz metin olarak ayar dosyasında durmasın)

func kcQuery(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LightShot", kSecAttrAccount as String: account]
}

func kcGet(_ account: String) -> String {
    var out: AnyObject?
    var q = kcQuery(account); q[kSecReturnData as String] = true
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
    return String(data: d, encoding: .utf8) ?? ""
}

func kcSet(_ account: String, _ value: String) {
    SecItemDelete(kcQuery(account) as CFDictionary)
    if value.isEmpty { return }
    var q = kcQuery(account); q[kSecValueData as String] = Data(value.utf8)
    SecItemAdd(q as CFDictionary, nil)
}

// MARK: OCR (yazıyı kopyala)

func recognizeText(_ rep: NSBitmapImageRep, done: @escaping (String) -> Void) {
    guard let cg = rep.cgImage else { done(""); return }
    DispatchQueue.global().async {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true   // Türkçe ve diğer diller otomatik
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        DispatchQueue.main.async { done(lines.joined(separator: "\n")) }
    }
}

// MARK: Ekrana sabitleme

final class PinView: NSView {
    let image: NSImage
    var dragFrom: NSPoint?

    init(image: NSImage, frame: NSRect) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ r: NSRect) {
        image.draw(in: bounds)
        NSColor(white: 0, alpha: 0.4).setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { closePin(); return }
        dragFrom = NSEvent.mouseLocation
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = dragFrom, let w = window else { return }
        let n = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: w.frame.minX + n.x - s.x, y: w.frame.minY + n.y - s.y)); dragFrom = n
    }

    override func scrollWheel(with e: NSEvent) {   // tekerlek: şeffaflık
        guard let w = window else { return }
        w.alphaValue = min(1, max(0.15, w.alphaValue + e.scrollingDeltaY * 0.01))
    }

    override func rightMouseDown(with e: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: "Kopyala", action: #selector(copyPin), keyEquivalent: "").target = self
        m.addItem(withTitle: "Yarı saydam yap", action: #selector(halfAlpha), keyEquivalent: "").target = self
        m.addItem(withTitle: "Tam görünür yap", action: #selector(fullAlpha), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Kapat (çift tıklama)", action: #selector(closePin), keyEquivalent: "").target = self
        m.addItem(withTitle: "Tüm sabitlenenleri kapat", action: #selector(closeAll), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(m, with: e, for: self)
    }

    @objc func copyPin() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
    @objc func halfAlpha() { window?.alphaValue = 0.5 }
    @objc func fullAlpha() { window?.alphaValue = 1 }
    @objc func closePin() { if let w = window as? NSPanel { w.close(); Pins.all.removeAll { $0 === w } } }
    @objc func closeAll() { Pins.all.forEach { $0.close() }; Pins.all = [] }
}

enum Pins {
    static var all: [NSPanel] = []

    // rect: seçimin global konumu; verilmezse görüntü ekranın ortasında açılır
    static func add(_ img: NSImage, rect: NSRect?) {
        let size = rect?.size ?? NSSize(width: img.size.width / 2, height: img.size.height / 2)
        let vf = (NSScreen.main ?? NSScreen.screens[0]).frame
        let origin = rect?.origin ?? NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating; p.hasShadow = true; p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = PinView(image: img, frame: NSRect(origin: .zero, size: size))
        p.orderFrontRegardless()
        all.append(p)
    }
}

// MARK: QR kod

var qrPanel: NSPanel?

func showQR(_ text: String) {
    guard let f = CIFilter(name: "CIQRCodeGenerator") else { return }
    f.setValue(Data(text.utf8), forKey: "inputMessage"); f.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = f.outputImage else { return }
    let s = max(1, Int(260 / out.extent.width))   // tam sayı katı: keskin kareler
    let big = out.samplingNearest().transformed(by: CGAffineTransform(scaleX: CGFloat(s), y: CGFloat(s)))
    guard let cg = CIContext().createCGImage(big, from: big.extent) else { return }
    let side = CGFloat(cg.width) + 48
    qrPanel?.close()
    let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.titled, .closable, .utilityWindow],
                    backing: .buffered, defer: false)
    p.title = "QR kod — telefonla okut"; p.level = .floating; p.isReleasedWhenClosed = false
    let v = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side)); v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.white.cgColor
    let iv = NSImageView(frame: NSRect(x: 24, y: 24, width: cg.width, height: cg.height))
    iv.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)); iv.imageScaling = .scaleNone
    v.addSubview(iv); p.contentView = v
    p.center(); NSApp.activate(ignoringOtherApps: true); p.makeKeyAndOrderFront(nil)
    qrPanel = p
}

// MARK: Pencere seçimi için pencere listesi (öndeki pencere önce)

// U: tüm ekranların global birleşimi; sonuç birleşik yerel koordinatta
func windowRects(U: NSRect) -> [NSRect] {
    let primaryH = NSScreen.screens[0].frame.height
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    let me = Int(ProcessInfo.processInfo.processIdentifier)
    return list.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0,                      // normal pencereler (menü çubuğu, Dock vb. hariç)
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
              (w[kCGWindowOwnerPID as String] as? Int) != me,
              let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd), r.width >= 40, r.height >= 40 else { return nil }
        return NSRect(x: r.minX - U.minX, y: primaryH - r.maxY - U.minY, width: r.width, height: r.height)   // CG sol-üst → Cocoa sol-alt
    }
}

// MARK: S3 / R2 (kendi sunucun) — AWS Signature V4

struct S3Cfg { let endpoint, bucket, region, access, secret, publicBase: String }

func s3Cfg() -> S3Cfg? {
    func v(_ k: String) -> String { (defaults.string(forKey: "s3." + k) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var ep = v("endpoint"); while ep.hasSuffix("/") { ep.removeLast() }
    let secret = kcGet("s3.secret")
    guard ep.hasPrefix("https://"), !v("bucket").isEmpty, !v("access").isEmpty, !secret.isEmpty else { return nil }
    var pub = v("public"); while pub.hasSuffix("/") { pub.removeLast() }
    return S3Cfg(endpoint: ep, bucket: v("bucket"), region: v("region").isEmpty ? "auto" : v("region"), access: v("access"), secret: secret, publicBase: pub)
}
var s3Configured: Bool { s3Cfg() != nil }

func hmacData(_ key: Data, _ msg: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: key))) }
func hexString(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func sha256Hex(_ d: Data) -> String { hexString(Data(SHA256.hash(data: d))) }

func awsEncode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? s
}

func sigV4(method: String, uri: String, query: String, headers: [(String, String)], payloadHash: String,
           secret: String, region: String, amzDate: String) -> (signedHeaders: String, signature: String, scope: String) {
    let hs = headers.map { ($0.0.lowercased(), $0.1.trimmingCharacters(in: .whitespaces)) }.sorted { $0.0 < $1.0 }
    let canonicalHeaders = hs.map { "\($0.0):\($0.1)\n" }.joined()
    let signed = hs.map(\.0).joined(separator: ";")
    let canonical = [method, uri, query, canonicalHeaders, signed, payloadHash].joined(separator: "\n")
    let date = String(amzDate.prefix(8))
    let scope = "\(date)/\(region)/s3/aws4_request"
    let sts = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(sha256Hex(Data(canonical.utf8)))"
    let k = hmacData(hmacData(hmacData(hmacData(Data(("AWS4" + secret).utf8), date), region), "s3"), "aws4_request")
    return (signed, hexString(hmacData(k, sts)), scope)
}

func amzNow() -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return f.string(from: Date())
}

func hostHeader(_ u: URL) -> String { (u.host ?? "") + (u.port.map { ":\($0)" } ?? "") }   // yol biçimi: endpoint/bucket/key

func s3Request(_ c: S3Cfg, method: String, key: String, body: Data, mime: String?) -> URLRequest {
    let uri = "/" + awsEncode(c.bucket) + "/" + awsEncode(key)
    let url = URL(string: c.endpoint + uri)!
    let amz = amzNow(), ph = sha256Hex(body)
    let s = sigV4(method: method, uri: uri, query: "",
                  headers: [("host", hostHeader(url)), ("x-amz-content-sha256", ph), ("x-amz-date", amz)],
                  payloadHash: ph, secret: c.secret, region: c.region, amzDate: amz)
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.httpMethod = method
    req.setValue(amz, forHTTPHeaderField: "x-amz-date")
    req.setValue(ph, forHTTPHeaderField: "x-amz-content-sha256")
    req.setValue("AWS4-HMAC-SHA256 Credential=\(c.access)/\(s.scope), SignedHeaders=\(s.signedHeaders), Signature=\(s.signature)", forHTTPHeaderField: "Authorization")
    if let m = mime { req.setValue(m, forHTTPHeaderField: "Content-Type") }
    if method == "PUT" { req.httpBody = body }
    return req
}

// Genel URL verilmemişse en fazla 7 gün geçerli imzalı link üretir
func s3Presign(_ c: S3Cfg, key: String, seconds: Int) -> String {
    let uri = "/" + awsEncode(c.bucket) + "/" + awsEncode(key)
    let amz = amzNow(), scope = "\(amz.prefix(8))/\(c.region)/s3/aws4_request"
    let q = [("X-Amz-Algorithm", "AWS4-HMAC-SHA256"), ("X-Amz-Credential", "\(c.access)/\(scope)"), ("X-Amz-Date", amz),
             ("X-Amz-Expires", "\(min(seconds, 604800))"), ("X-Amz-SignedHeaders", "host")]
        .sorted { $0.0 < $1.0 }.map { "\(awsEncode($0.0))=\(awsEncode($0.1))" }.joined(separator: "&")
    let host = hostHeader(URL(string: c.endpoint)!)
    let s = sigV4(method: "GET", uri: uri, query: q, headers: [("host", host)], payloadHash: "UNSIGNED-PAYLOAD",
                  secret: c.secret, region: c.region, amzDate: amz)
    return "\(c.endpoint)\(uri)?\(q)&X-Amz-Signature=\(s.signature)"
}

func s3Upload(_ d: Data, _ ext: String, _ mime: String, _ done: @escaping (String?) -> Void) {
    guard let c = s3Cfg() else { done(nil); return }
    let key = "ss-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
    URLSession.shared.dataTask(with: s3Request(c, method: "PUT", key: key, body: d, mime: mime)) { data, resp, err in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            logFailure("S3 PUT HTTP \(code) \(err?.localizedDescription ?? "")\n\(String(data: data ?? Data(), encoding: .utf8)?.prefix(2000) ?? "")")
            DispatchQueue.main.async { done(nil) }; return
        }
        let days = defaults.integer(forKey: "s3.ttlDays")
        DispatchQueue.main.async {
            if days > 0 { s3Track(key, days: days) }
            done(safeLink(c.publicBase.isEmpty ? s3Presign(c, key: key, seconds: (days > 0 ? days : 7) * 86400) : c.publicBase + "/" + awsEncode(key)))
        }
    }.resume()
}

// Otomatik silme: süresi dolan dosyalar uygulama açıkken saatlik taramayla silinir
func s3Track(_ key: String, days: Int) {
    var l = defaults.array(forKey: "s3.expiring") as? [[String: Any]] ?? []
    l.append(["key": key, "at": Date().addingTimeInterval(Double(days) * 86400).timeIntervalSince1970])
    defaults.set(l, forKey: "s3.expiring")
}

func s3Sweep() {
    guard let c = s3Cfg() else { return }
    let l = defaults.array(forKey: "s3.expiring") as? [[String: Any]] ?? []
    for e in l {
        guard let key = e["key"] as? String, let at = e["at"] as? Double, at <= Date().timeIntervalSince1970 else { continue }
        URLSession.shared.dataTask(with: s3Request(c, method: "DELETE", key: key, body: Data(), mime: nil)) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) || code == 404 else { return }
            DispatchQueue.main.async {
                let cur = defaults.array(forKey: "s3.expiring") as? [[String: Any]] ?? []
                defaults.set(cur.filter { ($0["key"] as? String) != key }, forKey: "s3.expiring")
            }
        }.resume()
    }
}

// MARK: Video → GIF

func convertToGIF(_ mov: URL, _ gif: URL, maxFPS: Double = 10, maxWidth: CGFloat = 640) -> Bool {
    let asset = AVURLAsset(url: mov)
    var dur = 0.0   // load(.duration) async; bu fonksiyon arka plan iş parçacığında çalışır, ana iş parçacığını bloklamaz
    let sem = DispatchSemaphore(value: 0)
    Task { dur = ((try? await asset.load(.duration)).map(CMTimeGetSeconds)) ?? 0; sem.signal() }
    sem.wait()
    guard dur > 0 else { return false }
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: maxWidth, height: 10000)
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    let fps = min(maxFPS, 240 / dur)   // en fazla 240 kare: CGImageDestination hepsini bellekte tutar (uzun kayıtta GB'lar)
    let n = max(1, Int(dur * fps))
    guard let dest = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, n, nil) else { return false }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    var added = 0
    for i in 0..<n {
        guard let img = try? gen.copyCGImage(at: CMTime(seconds: Double(i) / fps, preferredTimescale: 600), actualTime: nil) else { continue }
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
        added += 1
    }
    return added > 0 && CGImageDestinationFinalize(dest)
}

// MARK: Kaydırmalı yakalama

// Her satırın özeti: ardışık karelerde aynı içeriği bulmak için
func rowHashes(_ img: CGImage) -> [UInt32] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (0..<h).map { y in
        var hs: UInt32 = 2166136261
        var x = 0
        while x < w {
            let i = (y * w + x) * 4
            hs = (hs ^ UInt32(buf[i] >> 2)) &* 16777619
            hs = (hs ^ UInt32(buf[i + 1] >> 2)) &* 16777619
            hs = (hs ^ UInt32(buf[i + 2] >> 2)) &* 16777619
            x += 3
        }
        return hs
    }
}

// next[r] == prev[r + s] olacak şekilde kaydırma miktarı s (satır). 0: kare değişmedi. nil: eşleşme yok.
func findShift(_ p: [UInt32], _ n: [UInt32], expected: Int) -> Int? {
    let h = p.count
    guard n.count == h, h > 20 else { return nil }
    var same = 0
    for i in 0..<h where p[i] == n[i] { same += 1 }
    if Double(same) >= 0.999 * Double(h) { return 0 }
    let maxS = Int(Double(h) * 0.85)
    var scores = [Double](repeating: 0, count: maxS + 1), best = 0.0
    for s in 1...maxS {
        let ov = h - s
        var m = 0
        for r in 0..<ov where n[r] == p[r + s] { m += 1 }
        scores[s] = Double(m) / Double(ov); best = max(best, scores[s])
    }
    guard best >= 0.85 else { return nil }   // sabit üst/alt çubuklar skoru biraz düşürür, o yüzden %100 aranmaz
    return (1...maxS).filter { scores[$0] >= best - 0.01 }.min { abs($0 - expected) < abs($1 - expected) }
}

func makeContext(_ w: Int, _ h: Int, _ cs: CGColorSpace?) -> CGContext? {
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
}

// Kareleri geldikçe birleştirir ve her kareden sadece YENİ satırları (bağımsız kopya olarak) saklar:
// 40 tam kareyi bellekte tutmak büyük pencerelerde yüzlerce MB tutuyordu.
final class Stitcher {
    private var strips: [CGImage] = []
    private var prevHash: [UInt32] = []
    private var height = 0
    var prevS: Int            // beklenen kaydırma (piksel); ilk karede ayarlanır, sonra son ölçülen değer
    let maxHeight: Int
    var isEmpty: Bool { strips.isEmpty }

    init(expected: Int, maxHeight: Int = 24000) { prevS = expected; self.maxHeight = maxHeight }

    private func copyRows(_ img: CGImage, from y: Int, rows: Int) -> CGImage? {
        guard let c = img.cropping(to: CGRect(x: 0, y: y, width: img.width, height: rows)),
              let ctx = makeContext(c.width, c.height, img.colorSpace) else { return nil }
        ctx.draw(c, in: CGRect(x: 0, y: 0, width: c.width, height: c.height))
        return ctx.makeImage()
    }

    // false: yakalama durmalı (sayfa sonu, eşleşme yok ya da yükseklik sınırı)
    func add(_ img: CGImage, hashes: [UInt32]) -> Bool {
        if strips.isEmpty {
            guard let c = copyRows(img, from: 0, rows: img.height) else { return false }
            strips = [c]; prevHash = hashes; height = img.height
            return true
        }
        guard let s = findShift(prevHash, hashes, expected: prevS), s > 0,
              let strip = copyRows(img, from: img.height - s, rows: s) else { return false }   // karenin alt s satırı yeni içerik
        prevS = s; prevHash = hashes; strips.append(strip); height += s
        return height < maxHeight
    }

    func finish() -> CGImage? {
        guard let first = strips.first, let ctx = makeContext(first.width, height, first.colorSpace) else { return nil }
        var y = height
        for s in strips { y -= s.height; ctx.draw(s, in: CGRect(x: 0, y: y, width: first.width, height: s.height)) }
        return ctx.makeImage()
    }
}

func stitchFrames(_ frames: [CGImage], expected: Int) -> CGImage? {
    let st = Stitcher(expected: expected)
    for f in frames where !st.add(f, hashes: rowHashes(f)) { break }
    return st.finish()
}

enum ScrollCapture {
    static func grab(_ r: CGRect) -> CGImage? {
        let path = NSTemporaryDirectory() + "lightshot-scroll-\(UUID().uuidString).tiff"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "tiff", "-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", path]
        try? p.run(); p.waitUntilExit()
        defer { try? FileManager.default.removeItem(atPath: path) }
        return (try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).flatMap { NSBitmapImageRep(data: $0)?.cgImage }
    }

    // g: seçimin global (Cocoa) dikdörtgeni. Fare seçimin ortasına gider ve sayfa tekerlekle kaydırılır.
    static func run(_ g: NSRect, done: @escaping (NSBitmapImageRep?, String) -> Void) {
        // olay göndermek (kaydırma) Erişilebilirlik izni ister
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            done(nil, "Erişilebilirlik izni gerekli: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik → LightShot'ı aç, sonra tekrar dene"); return
        }
        Toast.show("Kaydırmalı yakalama başlıyor… fareye ve klavyeye dokunma")
        let primaryH = NSScreen.screens[0].frame.height
        let cg = CGRect(x: g.minX.rounded(), y: (primaryH - g.maxY).rounded(), width: g.width.rounded(), height: g.height.rounded())
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            DispatchQueue.main.sync { Toast.panel?.close() }   // bildirim görüntüye girmesin
            Thread.sleep(forTimeInterval: 0.3)
            CGWarpMouseCursorPosition(CGPoint(x: cg.midX, y: cg.midY)); Thread.sleep(forTimeInterval: 0.3)
            let st = Stitcher(expected: 0)
            let step = Int(cg.height * 0.6)
            for _ in 0..<40 {
                guard let img = grab(cg) else { break }
                if st.isEmpty { st.prevS = Int(CGFloat(step) * CGFloat(img.width) / cg.width) }   // piksel/nokta oranı ilk kareden
                if !st.add(img, hashes: rowHashes(img)) { break }   // sayfa sonu: kare değişmedi
                CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-step), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.7)   // kaydırma animasyonu bitsin
            }
            let out = st.finish().map { NSBitmapImageRep(cgImage: $0) }
            DispatchQueue.main.async { done(out, out == nil ? "Kaydırmalı yakalama başarısız (Ekran Kaydı izni?)" : "") }
        }
    }
}
