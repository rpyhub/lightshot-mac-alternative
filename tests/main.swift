// LightShotMac testleri. main.swift'teki uygulama koduna bağlı olmamak için gereken küçük parçalar burada taklit edilir.
import Cocoa

let defaults = UserDefaults(suiteName: "lightshot.tests")!
func logFailure(_ s: String) {}
func formatLink(_ s: String) -> String { s }

let app = NSApplication.shared
var fails = 0
func check(_ name: String, _ ok: Bool, _ extra: String = "") { print(ok ? "OK    " : "HATA  ", name, extra); if !ok { fails += 1 } }

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); body(); NSGraphicsContext.restoreGraphicsState()
}

// 1) AWS belgelerindeki resmi imza örnekleri (S3 yüklemesi bunlara dayanır)
let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
let r1 = sigV4(method: "GET", uri: "/test.txt", query: "",
    headers: [("host", "examplebucket.s3.amazonaws.com"), ("range", "bytes=0-9"), ("x-amz-content-sha256", emptyHash), ("x-amz-date", "20130524T000000Z")],
    payloadHash: emptyHash, secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1", amzDate: "20130524T000000Z")
check("SigV4 GET örneği", r1.signature == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
let q = "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host"
let r2 = sigV4(method: "GET", uri: "/test.txt", query: q, headers: [("host", "examplebucket.s3.amazonaws.com")], payloadHash: "UNSIGNED-PAYLOAD",
    secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1", amzDate: "20130524T000000Z")
check("SigV4 presign örneği", r2.signature == "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")

// 2) Kaydırmalı yakalama: uzun sentetik sayfa → pencereler → birleştir → orijinalle birebir aynı olmalı
let W = 600, H = 3000, win = 1000, step = 400
let tall = bitmap(W, H)
var seed: UInt64 = 42
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / CGFloat(1 << 24) }
draw(into: tall) {
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    for i in 0..<120 {
        NSColor(calibratedHue: rnd(), saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
        NSRect(x: rnd() * 200, y: CGFloat(i) * 25, width: 100 + rnd() * 300, height: 10 + rnd() * 8).fill()
        ("Satır \(i) \(Int(rnd() * 9999))" as NSString).draw(at: NSPoint(x: 20, y: CGFloat(i) * 25 + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
    }
}
let tallCG = tall.cgImage!
var frames: [CGImage] = []
var off = 0
while true { let o = min(off, H - win); frames.append(tallCG.cropping(to: CGRect(x: 0, y: o, width: W, height: win))!); if o == H - win { break }; off += step }
frames.append(frames.last!)   // sayfa sonunda aynı kare tekrar gelir
let out = stitchFrames(frames, expected: step)!
check("birleştirme: yükseklik", out.height == H, "\(out.height)/\(H)")
check("birleştirme: piksel eşitliği", rowHashes(out) == rowHashes(tallCG))
var sticky: [CGImage] = []
for f in frames.dropLast() {   // üstte 80 piksellik sabit çubuk (sticky header)
    let ctx = CGContext(data: nil, width: W, height: win, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(f, in: CGRect(x: 0, y: 0, width: W, height: win)); ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: win - 80, width: W, height: 80))
    sticky.append(ctx.makeImage()!)
}
check("birleştirme: sabit çubuklu sayfa", abs(stitchFrames(sticky, expected: step)!.height - H) <= 80)

// 3) OCR (Türkçe karakterler ve rakamlar)
let t = bitmap(700, 140)
draw(into: t) {
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 700, height: 140).fill()
    ("Merhaba Dünya, şifre 12345" as NSString).draw(at: NSPoint(x: 20, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
}
var ocrText = ""; var ocrDone = false
recognizeText(t) { ocrText = $0; ocrDone = true }
while !ocrDone { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
check("OCR", ocrText.contains("Merhaba") && ocrText.contains("12345"), "'\(ocrText)'")

// 4) Çizim şekilleri: tıklama ve taşıma
let line = Shape(tool: .line, pts: [NSPoint(x: 0, y: 0), NSPoint(x: 100, y: 0)], color: .red)
check("çizgi tıklama", line.hit(NSPoint(x: 50, y: 3)) && !line.hit(NSPoint(x: 50, y: 30)))
var rc = Shape(tool: .rect, pts: [NSPoint(x: 0, y: 0), NSPoint(x: 100, y: 100)], color: .red)
check("boş dikdörtgen: kenar evet, iç hayır", rc.hit(NSPoint(x: 0, y: 50)) && !rc.hit(NSPoint(x: 50, y: 50)))
rc.fill = true
check("dolu dikdörtgen: iç evet", rc.hit(NSPoint(x: 50, y: 50)))
var mv = line; mv.move(10, 5)
check("şekil taşıma", mv.pts[0] == NSPoint(x: 10, y: 5) && mv.pts[1] == NSPoint(x: 110, y: 5))

// 5) Güvenilmez linkler: sadece http(s) açılır
check("güvenli link: https/http geçer", safeLink("https://iili.io/a.png") != nil && safeLink("http://a.b/c") != nil)
check("güvenli link: file/javascript/özel şema/boş reddedilir",
      safeLink("file:///etc/passwd") == nil && safeLink("javascript:alert(1)") == nil && safeLink("x-apple.systempreferences:") == nil && safeLink("https://") == nil && safeLink(nil) == nil)

// 6) Bellek sızıntısı: Session, görünümleri ve pencereleri bırakılınca serbest kalmalı (her yakalama onlarca MB tutuyordu)
weak var weakSession: Session?
autoreleasepool {
    let rep = bitmap(400, 300)
    let img = NSImage(size: NSSize(width: 400, height: 300)); img.addRepresentation(rep)
    var s: Session? = Session(full: img, U: NSRect(x: 0, y: 0, width: 400, height: 300), scale: 1)
    var win: NSWindow? = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
    s!.views.append(OverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), session: s!, off: .zero))
    win!.contentView = s!.views[0]
    weakSession = s
    win = nil; s = nil
}
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
check("sızıntı yok: Session serbest kalıyor", weakSession == nil)

// 7) Kodlama: ayara göre PNG/JPG, tek sefer (önbellek)
let shot = Shot(t)
defaults.set("png", forKey: "format")
let e1 = shot.encoded, e2 = shot.encoded
check("kodlama: PNG ve önbellek", e1?.ext == "png" && e1?.data == e2?.data)
defaults.set("jpg", forKey: "format"); defaults.set(0.8, forKey: "quality")
let jshot = Shot(t)
check("kodlama: JPG doğrudan", jshot.encoded?.ext == "jpg" && jshot.encoded?.mime == "image/jpeg" && (jshot.encoded?.data.count ?? 0) > 100)

print(fails == 0 ? "TÜMÜ GEÇTİ" : "\(fails) HATA")
exit(fails == 0 ? 0 : 1)
