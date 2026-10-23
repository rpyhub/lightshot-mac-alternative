// LightShotMac — Lightshot benzeri: kısayol → alan seç → çiz → yükle / ara / OCR / sabitle / kaydet / kaydır
import Cocoa
import Carbon
import ServiceManagement

let defaults = UserDefaults.standard
defaults.register(defaults: [
    "keyCode": kVK_ANSI_1, "mods": controlKey, "label": "⌃1",
    "keyCode2": kVK_ANSI_2, "mods2": controlKey, "label2": "⌃2",
    "keyCode3": kVK_ANSI_3, "mods3": controlKey, "label3": "⌃3",
    "keyCode4": kVK_ANSI_4, "mods4": controlKey, "label4": "⌃4",
    "format": "png", "quality": 0.85, "autosave": false, "loupe": true,
    "folder": NSHomeDirectory() + "/Pictures/LightShot",
    "linkFormat": 0, "recordFormat": "mov", "s3.ttlDays": 0,
])

// Kısayollar: anahtar eki (UserDefaults) ve ayar ekranındaki adı. Sıra = kısayol kimliği - 1
let hotKeys = [("", "Ekran görüntüsü al"), ("2", "Tam ekranı kaydet"), ("3", "Tam ekranı yükle"), ("4", "Son alanı tekrarla")]
let linkFormats = ["Düz link", "Markdown", "HTML", "BBCode"]

func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    (f.contains(.control) ? controlKey : 0) | (f.contains(.option) ? optionKey : 0) |
    (f.contains(.shift) ? shiftKey : 0) | (f.contains(.command) ? cmdKey : 0)
}

func modLabel(_ f: NSEvent.ModifierFlags) -> String {
    (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") +
    (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
}

// Panoya kopyalanan link: ayarlardaki biçime göre
func formatLink(_ l: String) -> String {
    switch defaults.integer(forKey: "linkFormat") {
    case 1: return "![görüntü](\(l))"
    case 2: return "<img src=\"\(l)\" alt=\"\">"
    case 3: return "[img]\(l)[/img]"
    default: return l
    }
}

// MARK: Yükleme siteleri

enum HostKind { case form, s3 }

// linkPath: JSON yanıtında linkin yolu (sözlük anahtarı ya da dizi sırası)
struct Host {
    let name: String, note: String, url: String, fileField: String
    var fields: [String: String] = [:]
    var keyField: String? = nil    // kullanıcı anahtarı form alanında gider (ImgBB)
    var keyHeader: String? = nil   // kullanıcı anahtarı Authorization başlığında gider (Imgur)
    let linkPath: [Any]
    var kind: HostKind = .form
    var needsKey: Bool { keyField != nil || keyHeader != nil }
}

let hosts = [
    // freeimage.host anahtarı sitenin API belgelerindeki herkese açık anahtar
    Host(name: "freeimage.host", note: "Kalıcı, anahtar gerekmez.", url: "https://freeimage.host/api/1/upload",
         fileField: "source", fields: ["key": "6d207e02198a847aa98d0a2a901485a5", "action": "upload", "format": "json"],
         linkPath: ["image", "url"]),
    Host(name: "pixhost.to", note: "Kalıcı, anahtar gerekmez. Link bir sayfa açar (prnt.sc gibi).",
         url: "https://api.pixhost.to/images", fileField: "img", fields: ["content_type": "0"], linkPath: ["show_url"]),
    Host(name: "uguu.se (geçici)", note: "Anahtar gerekmez. Dosya 3 saat sonra silinir.",
         url: "https://uguu.se/upload", fileField: "files[]", linkPath: ["files", 0, "url"]),
    Host(name: "ImgBB", note: "Kalıcı. Ücretsiz anahtar: api.imgbb.com", url: "https://api.imgbb.com/1/upload",
         fileField: "image", keyField: "key", linkPath: ["data", "url"]),
    Host(name: "Imgur", note: "Kalıcı. Ücretsiz Client-ID: api.imgur.com/oauth2/addclient", url: "https://api.imgur.com/3/image",
         fileField: "image", keyHeader: "Client-ID ", linkPath: ["data", "link"]),
    Host(name: "Özel sunucu (S3/R2)", note: "Kendi bucket'ın (Cloudflare R2, AWS S3, MinIO…). Ayarlar için aşağıdaki düğmeyi kullan.",
         url: "", fileField: "", linkPath: [], kind: .s3),
]

func dig(_ j: Any?, _ path: [Any]) -> String? {
    var cur = j
    for k in path {
        if let k = k as? String { cur = (cur as? [String: Any])?[k] }
        else if let i = k as? Int, let a = cur as? [Any], a.indices.contains(i) { cur = a[i] } else { return nil }
    }
    return cur as? String
}
assert(dig(["files": [["url": "u"]]] as [String: Any], ["files", 0, "url"]) == "u" && dig([:] as [String: Any], ["a", 0]) == nil)

var currentHost: Host { hosts.first { $0.name == defaults.string(forKey: "host") } ?? hosts[0] }
func savedKey(_ h: Host) -> String { defaults.string(forKey: "key.\(h.name)") ?? "" }
func usable(_ h: Host) -> Bool { h.kind == .s3 ? s3Configured : (!h.needsKey || !savedKey(h).isEmpty) }

func logFailure(_ s: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LightShot.log")
    let line = "\(Date()) \(s)\n\n"
    if ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) > 256_000 { try? FileManager.default.removeItem(at: url) }   // log sonsuz büyümesin
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

func post(_ h: Host, _ d: Data, _ ext: String, _ mime: String, _ done: @escaping (String?) -> Void) {
    if h.kind == .s3 { s3Upload(d, ext, mime, done); return }
    var req = URLRequest(url: URL(string: h.url)!, timeoutInterval: 25)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let p = h.keyHeader { req.setValue(p + savedKey(h), forHTTPHeaderField: "Authorization") }
    let boundary = "----LS\(UUID().uuidString)"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    var fields = h.fields
    if let k = h.keyField { fields[k] = savedKey(h) }
    var body = Data()
    for (k, v) in fields {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
    }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(h.fileField)\"; filename=\"screenshot.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
    body.append(d)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    req.httpBody = body

    URLSession.shared.dataTask(with: req) { data, resp, err in
        let link = safeLink(dig(data.flatMap { try? JSONSerialization.jsonObject(with: $0) }, h.linkPath))
        if link == nil {
            logFailure("\(h.name) HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0) \(err?.localizedDescription ?? "")\n\(String(data: data ?? Data(), encoding: .utf8)?.prefix(4000) ?? "")")
        }
        DispatchQueue.main.async { done(link) }
    }.resume()
}

// Seçili siteyi dener, olmazsa kullanılabilir diğer siteleri sırayla dener. Kodlama arka planda (ana iş parçacığı takılmaz).
var hostFailedAt: [String: Date] = [:]   // son başarısızlık: takılan site her yüklemede 25 sn bekletmesin

func upload(_ shot: Shot, then done: @escaping (String?) -> Void) {
    Toast.show("Hazırlanıyor…")
    DispatchQueue.global().async {
        let enc = shot.encoded
        DispatchQueue.main.async {
            guard let enc else { done(nil); return }
            let all = ([currentHost] + hosts.filter { $0.name != currentHost.name }).filter(usable)
            func recent(_ h: Host) -> Bool { hostFailedAt[h.name].map { Date().timeIntervalSince($0) < 600 } ?? false }
            let order = all.filter { !recent($0) } + all.filter(recent)   // son 10 dakikada başarısız olanlar en sona
            func attempt(_ i: Int) {
                guard i < order.count else { done(nil); return }
                let h = order[i]
                Toast.show(i == 0 ? "\(h.name) sitesine yükleniyor…" : "\(order[i - 1].name) olmadı, \(h.name) deneniyor…")
                post(h, enc.data, enc.ext, enc.mime) { link in
                    if let link { hostFailedAt[h.name] = nil; addHistory(link, h.name); done(link) }
                    else { hostFailedAt[h.name] = Date(); attempt(i + 1) }
                }
            }
            attempt(0)
        }
    }
}

// MARK: Geçmiş

func addHistory(_ link: String, _ host: String) {
    var h = defaults.array(forKey: "history") as? [[String: String]] ?? []
    h.insert(["link": link, "host": host, "date": ISO8601DateFormatter().string(from: Date())], at: 0)
    defaults.set(Array(h.prefix(20)), forKey: "history")
    (NSApp.delegate as? App)?.rebuildHistory()
}

// MARK: Ayar formu yardımcısı

final class Form {
    let view: NSView
    var y: CGFloat
    init(height: CGFloat) { view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: height)); y = height }

    func header(_ t: String) {
        y -= 34
        let l = NSTextField(labelWithString: t); l.font = .boldSystemFont(ofSize: 13)
        l.frame = NSRect(x: 12, y: y, width: 390, height: 20); view.addSubview(l)
    }
    func row(_ gap: CGFloat, _ label: String? = nil) {
        y -= gap
        if let t = label { let l = NSTextField(labelWithString: t); l.frame = NSRect(x: 12, y: y + 4, width: 128, height: 20); view.addSubview(l) }
    }
    @discardableResult func add<T: NSView>(_ v: T, x: CGFloat = 142, w: CGFloat, h: CGFloat, dy: CGFloat = 0) -> T {
        v.frame = NSRect(x: x, y: y + dy, width: w, height: h); view.addSubview(v); return v
    }
}

// MARK: Uygulama

final class App: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var statusItem: NSStatusItem!
    var overlays: [NSWindow] = []
    var session: Session?
    var hotKeyRefs: [EventHotKeyRef?] = []
    var captureItem: NSMenuItem!, repeatItem: NSMenuItem!, historyItem: NSMenuItem!, recItem: NSMenuItem!
    var settings: NSWindow?, s3Window: NSWindow?
    var shortcutButtons: [NSButton] = []
    var recording = -1
    var keyMonitor: Any?
    var hostPopup: NSPopUpButton!, hostNote: NSTextField!, keyField: NSTextField!
    var qualitySlider: NSSlider!, qualityLabel: NSTextField!, folderLabel: NSTextField!
    var s3Fields: [String: NSTextField] = [:], s3Secret: NSSecureTextField!, s3Ttl: NSPopUpButton!
    var recProcess: Process?, recPath = ""
    var capturing = false   // yakalama başlatıldı ama pencereler henüz açılmadı: ikinci basış yok sayılır

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "LightShot")
        let menu = NSMenu()
        captureItem = menu.addItem(withTitle: "", action: #selector(capture), keyEquivalent: "")
        repeatItem = menu.addItem(withTitle: "", action: #selector(repeatLast), keyEquivalent: "")
        let delay = menu.addItem(withTitle: "Gecikmeli yakala", action: nil, keyEquivalent: "")
        delay.submenu = NSMenu()
        for s in [3, 5, 10] {
            let it = delay.submenu!.addItem(withTitle: "\(s) saniye sonra", action: #selector(delayedCapture(_:)), keyEquivalent: "")
            it.tag = s; it.target = self
        }
        recItem = menu.addItem(withTitle: "■ Kaydı durdur", action: #selector(stopRecording), keyEquivalent: "")
        recItem.isHidden = true
        historyItem = menu.addItem(withTitle: "Son yüklemeler", action: nil, keyEquivalent: "")
        historyItem.submenu = NSMenu()
        menu.addItem(withTitle: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        rebuildHistory()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, ctx in
            var hk = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.hotKey(Int(hk.id)) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        registerHotKeys()

        s3Sweep()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in s3Sweep() }
    }

    func hotKey(_ id: Int) {
        switch id {
        case 1: capture()
        case 2: fullScreen("instantSave")
        case 3: fullScreen("upload")
        default: repeatLast()
        }
    }

    func registerHotKeys() {
        hotKeyRefs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        hotKeyRefs = []
        var failed: [String] = []
        for (i, hk) in hotKeys.enumerated() {
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(UInt32(defaults.integer(forKey: "keyCode" + hk.0)), UInt32(defaults.integer(forKey: "mods" + hk.0)),
                                         EventHotKeyID(signature: OSType(0x4C534854), id: UInt32(i + 1)),
                                         GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
            if st != noErr { failed.append(defaults.string(forKey: "label" + hk.0)!) }
        }
        captureItem.title = "Ekran görüntüsü al (\(defaults.string(forKey: "label")!))"
        repeatItem.title = "Son alanı tekrarla (\(defaults.string(forKey: "label4")!))"
        if !failed.isEmpty {
            let a = NSAlert()
            a.messageText = "\(failed.joined(separator: ", ")) kısayolu kullanılamıyor"
            a.informativeText = "Başka bir uygulama bu kısayolu kullanıyor olabilir. Ayarlar'dan farklı bir kısayol seçin."
            a.runModal()
        }
    }

    // MARK: Geçmiş menüsü

    func rebuildHistory() {
        guard let m = historyItem?.submenu else { return }
        m.removeAllItems()
        let h = defaults.array(forKey: "history") as? [[String: String]] ?? []
        if h.isEmpty { m.addItem(withTitle: "Henüz yükleme yok", action: nil, keyEquivalent: "").isEnabled = false; return }
        let iso = ISO8601DateFormatter()
        for e in h {
            let when = iso.date(from: e["date"] ?? "")?.formatted(date: .abbreviated, time: .shortened) ?? ""
            let link = e["link"] ?? ""
            let it = m.addItem(withTitle: "\(when)  ·  \(link.replacingOccurrences(of: "https://", with: "").prefix(40))",
                               action: #selector(historyClick(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = link
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Geçmişi temizle", action: #selector(clearHistory), keyEquivalent: "").target = self
    }

    @objc func historyClick(_ it: NSMenuItem) {
        guard let link = it.representedObject as? String else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(formatLink(link), forType: .string)
        Toast.show("Link kopyalandı ✓", link: link)
    }

    @objc func clearHistory() { defaults.removeObject(forKey: "history"); rebuildHistory() }

    // MARK: Ayarlar

    @objc func openSettings() {
        if settings == nil { buildSettings() }
        for (i, hk) in hotKeys.enumerated() { shortcutButtons[i].title = defaults.string(forKey: "label" + hk.0)! }
        hostPopup.selectItem(withTitle: currentHost.name); hostChanged()
        NSApp.activate(ignoringOtherApps: true)
        settings!.makeKeyAndOrderFront(nil)
    }

    func buildSettings() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "LightShot Ayarları"; w.isReleasedWhenClosed = false
        let tv = NSTabView(frame: NSRect(x: 10, y: 10, width: 420, height: 420))
        func tab(_ title: String, _ f: Form) {
            let it = NSTabViewItem(identifier: title); it.label = title; it.view = f.view; tv.addTabViewItem(it)
        }

        // — Genel
        let g = Form(height: 350)
        g.header("Kısayollar")
        for (i, hk) in hotKeys.enumerated() {
            g.row(34, hk.1 + ":")
            let b = NSButton(title: "", target: self, action: #selector(recordShortcut(_:)))
            b.bezelStyle = .rounded; b.tag = i
            g.add(b, w: 250, h: 28, dy: -2); shortcutButtons.append(b)
        }
        g.header("Yakalama")
        g.row(26)
        let loupe = NSButton(checkboxWithTitle: "Seçerken büyüteç ve renk göster (C: rengi kopyala)", target: self, action: #selector(loupeChanged(_:)))
        loupe.state = defaults.bool(forKey: "loupe") ? .on : .off
        g.add(loupe, x: 12, w: 390, h: 20)
        g.header("Sistem")
        g.row(26)
        let login = NSButton(checkboxWithTitle: "Mac açılınca otomatik başlat", target: self, action: #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        g.add(login, x: 12, w: 390, h: 20)
        tab("Genel", g)

        // — Yükleme
        let u = Form(height: 350)
        u.header("Yükleme sitesi")
        u.row(32, "Site:")
        hostPopup = u.add(NSPopUpButton(frame: .zero), w: 250, h: 26)
        hostPopup.addItems(withTitles: hosts.map(\.name))
        hostPopup.target = self; hostPopup.action = #selector(hostChanged)
        u.row(40)
        hostNote = u.add(NSTextField(wrappingLabelWithString: ""), w: 252, h: 36)
        hostNote.font = .systemFont(ofSize: 11); hostNote.textColor = .secondaryLabelColor
        u.row(30, "API anahtarı:")
        keyField = u.add(NSTextField(frame: .zero), x: 144, w: 250, h: 24, dy: 2)
        keyField.delegate = self
        u.row(34, "Özel sunucu:")
        u.add(NSButton(title: "S3 / R2 ayarları…", target: self, action: #selector(openS3)), w: 160, h: 28, dy: -2).bezelStyle = .rounded
        u.header("Link")
        u.row(32, "Kopyalanan biçim:")
        let lf = u.add(NSPopUpButton(frame: .zero), w: 160, h: 26)
        lf.addItems(withTitles: linkFormats); lf.selectItem(at: defaults.integer(forKey: "linkFormat"))
        lf.target = self; lf.action = #selector(linkFormatChanged(_:))
        tab("Yükleme", u)

        // — Görüntü ve kayıt
        let k = Form(height: 350)
        k.header("Görüntü")
        k.row(32, "Biçim:")
        let fmt = k.add(NSPopUpButton(frame: .zero), w: 120, h: 26)
        fmt.addItems(withTitles: ["PNG", "JPG"]); fmt.selectItem(withTitle: (defaults.string(forKey: "format") ?? "png").uppercased())
        fmt.target = self; fmt.action = #selector(formatChanged(_:))
        k.row(30, "JPG kalitesi:")
        qualitySlider = k.add(NSSlider(value: defaults.double(forKey: "quality"), minValue: 0.5, maxValue: 1, target: self, action: #selector(qualityChanged)),
                              w: 200, h: 20, dy: 2)
        qualityLabel = k.add(NSTextField(labelWithString: ""), x: 348, w: 50, h: 20, dy: 2)
        qualitySlider.isEnabled = fmt.titleOfSelectedItem == "JPG"; qualityChanged()
        k.header("Kayıt")
        k.row(26)
        let auto = NSButton(checkboxWithTitle: "Her ekran görüntüsünü otomatik kaydet", target: self, action: #selector(autosaveChanged(_:)))
        auto.state = defaults.bool(forKey: "autosave") ? .on : .off
        k.add(auto, x: 12, w: 390, h: 20)
        k.row(32, "Klasör:")
        folderLabel = k.add(NSTextField(labelWithString: ""), w: 190, h: 20, dy: 4)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.stringValue = (defaults.string(forKey: "folder")! as NSString).abbreviatingWithTildeInPath
        k.add(NSButton(title: "Seç…", target: self, action: #selector(pickFolder)), x: 336, w: 64, h: 28).bezelStyle = .rounded
        k.row(20)
        let note = k.add(NSTextField(labelWithString: "Ekran kayıtları ve tam ekran kaydı da buraya gider."), w: 270, h: 16)
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        k.header("Ekran kaydı")
        k.row(32, "Kayıt biçimi:")
        let rf = k.add(NSPopUpButton(frame: .zero), w: 160, h: 26)
        rf.addItems(withTitles: ["MOV (video)", "GIF"]); rf.selectItem(at: defaults.string(forKey: "recordFormat") == "gif" ? 1 : 0)
        rf.target = self; rf.action = #selector(recordFormatChanged(_:))
        tab("Görüntü ve kayıt", k)

        w.contentView!.addSubview(tv)
        w.center()
        settings = w
    }

    @objc func hostChanged() {
        defaults.set(hostPopup.titleOfSelectedItem, forKey: "host")
        let h = currentHost
        hostNote.stringValue = h.note + " Olmazsa diğer siteler otomatik denenir."
        keyField.isEnabled = h.needsKey
        keyField.placeholderString = h.needsKey ? "\(h.name) anahtarını yapıştırın" : "Bu site için gerekmez"
        keyField.stringValue = h.needsKey ? savedKey(h) : ""
    }

    // shortcut: ücretsiz API anahtarları UserDefaults'ta düz metin; S3 gizli anahtarı ise Anahtarlık'ta
    func controlTextDidChange(_ n: Notification) {
        defaults.set(keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "key.\(currentHost.name)")
    }

    @objc func linkFormatChanged(_ s: NSPopUpButton) { defaults.set(s.indexOfSelectedItem, forKey: "linkFormat") }
    @objc func recordFormatChanged(_ s: NSPopUpButton) { defaults.set(s.indexOfSelectedItem == 1 ? "gif" : "mov", forKey: "recordFormat") }
    @objc func loupeChanged(_ b: NSButton) { defaults.set(b.state == .on, forKey: "loupe") }

    @objc func formatChanged(_ s: NSPopUpButton) {
        defaults.set(s.titleOfSelectedItem!.lowercased(), forKey: "format")
        qualitySlider.isEnabled = s.titleOfSelectedItem == "JPG"
    }

    @objc func qualityChanged() {
        defaults.set(qualitySlider.doubleValue, forKey: "quality")
        qualityLabel.stringValue = "\(Int(qualitySlider.doubleValue * 100))%"
    }

    @objc func autosaveChanged(_ b: NSButton) { defaults.set(b.state == .on, forKey: "autosave") }

    @objc func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: defaults.string(forKey: "folder")!)
        if p.runModal() == .OK, let u = p.url {
            defaults.set(u.path, forKey: "folder")
            folderLabel.stringValue = (u.path as NSString).abbreviatingWithTildeInPath
        }
    }

    // MARK: S3 / R2 ayar penceresi

    @objc func openS3() {
        if s3Window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Özel sunucu (S3 / R2)"; w.isReleasedWhenClosed = false
            let f = Form(height: 360); f.y = 340
            func field(_ key: String, _ label: String, _ ph: String) {
                f.row(34, label)
                let t = f.add(NSTextField(frame: .zero), x: 144, w: 280, h: 24, dy: 2); t.placeholderString = ph; s3Fields[key] = t
            }
            field("endpoint", "Adres:", "https://<hesap>.r2.cloudflarestorage.com")
            field("bucket", "Bucket:", "ekran-goruntuleri")
            field("region", "Bölge:", "auto (R2) / eu-central-1 …")
            field("access", "Erişim anahtarı:", "")
            f.row(34, "Gizli anahtar:")
            s3Secret = f.add(NSSecureTextField(frame: .zero), x: 144, w: 280, h: 24, dy: 2)
            field("public", "Genel URL:", "isteğe bağlı: https://cdn.siten.com")
            f.row(34, "Otomatik sil:")
            s3Ttl = f.add(NSPopUpButton(frame: .zero), w: 200, h: 26)
            s3Ttl.addItems(withTitles: ["Silme", "1 gün sonra", "7 gün sonra", "30 gün sonra"])
            f.row(56)
            let note = f.add(NSTextField(wrappingLabelWithString: "Genel URL boşsa 7 gün geçerli imzalı link üretilir. Gizli anahtar Anahtarlık'ta saklanır. Otomatik silme LightShot açıkken saatlik çalışır."),
                             x: 14, w: 410, h: 44)
            note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
            f.row(40)
            let save = f.add(NSButton(title: "Kaydet", target: self, action: #selector(saveS3)), x: 324, w: 100, h: 30)
            save.bezelStyle = .rounded; save.keyEquivalent = "\r"
            w.contentView!.addSubview(f.view); w.center()
            s3Window = w
        }
        for (k, t) in s3Fields { t.stringValue = defaults.string(forKey: "s3." + k) ?? "" }
        s3Secret.stringValue = kcGet("s3.secret")
        s3Ttl.selectItem(at: [0, 1, 7, 30].firstIndex(of: defaults.integer(forKey: "s3.ttlDays")) ?? 0)
        NSApp.activate(ignoringOtherApps: true)
        s3Window!.makeKeyAndOrderFront(nil)
    }

    @objc func saveS3() {
        for (k, t) in s3Fields { defaults.set(t.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "s3." + k) }
        kcSet("s3.secret", s3Secret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        defaults.set([0, 1, 7, 30][s3Ttl.indexOfSelectedItem], forKey: "s3.ttlDays")
        s3Window?.close()
        if s3Configured { Toast.show("S3 ayarları kaydedildi ✓", seconds: 2) }
        else { Toast.show("Eksik alan var: adres https:// ile başlamalı, bucket ve anahtarlar dolu olmalı", seconds: 5) }
    }

    // MARK: Kısayol kaydı

    @objc func recordShortcut(_ b: NSButton) {
        if recording >= 0 { finishRecording() }
        recording = b.tag
        b.title = "Yeni tuşa basın… (Esc: iptal)"
        hotKeyRefs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }; hotKeyRefs = [] // kayıt sırasında eski kısayollar tetiklenmesin
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let sfx = hotKeys[self.recording].0
            if e.keyCode == UInt16(kVK_Escape) {
                self.finishRecording()
            } else if carbonMods(f) != 0 { // en az bir değiştirici tuş şart (⌃⌥⇧⌘)
                defaults.set(Int(e.keyCode), forKey: "keyCode" + sfx)
                defaults.set(carbonMods(f), forKey: "mods" + sfx)
                defaults.set(modLabel(f) + (e.charactersIgnoringModifiers ?? "?").uppercased(), forKey: "label" + sfx)
                self.finishRecording()
            } else { NSSound.beep() }
            return nil
        }
    }

    func finishRecording() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        recording = -1
        for (i, hk) in hotKeys.enumerated() { shortcutButtons[i].title = defaults.string(forKey: "label" + hk.0)! }
        registerHotKeys()
    }

    @objc func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Yakalama

    // screencapture -D numarası 1'den başlar ve aktif ekran listesi sırasını izler
    func displayIndex(_ s: NSScreen) -> Int {
        let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return (ids.prefix(Int(n)).firstIndex(of: id) ?? 0) + 1
    }

    // TIFF: PNG kodlama/çözme yok (ekran başına yüzlerce ms kazanç). 'mapped' okuma kopya yapmaz.
    static func grab(_ display: Int) -> NSBitmapImageRep? {
        let path = NSTemporaryDirectory() + "lightshot-\(UUID().uuidString).tiff"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "tiff", "-D", "\(display)", path]
        try? p.run(); p.waitUntilExit()
        defer { try? FileManager.default.removeItem(atPath: path) }
        return (try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).flatMap { NSBitmapImageRep(data: $0) }
    }

    @objc func capture() { startCapture(preselect: false) }
    @objc func repeatLast() { startCapture(preselect: true) }

    @objc func delayedCapture(_ it: NSMenuItem) {
        var n = it.tag
        Toast.show("Yakalama \(n)…")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            n -= 1
            if n > 0 { Toast.show("Yakalama \(n)…"); return }
            t.invalidate(); Toast.panel?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture() }   // bildirim görüntüye girmesin
        }
    }

    // Tüm ekranlar AYNI ANDA yakalanır (sırayla almak ekran sayısı kadar yavaştı)
    func startCapture(preselect: Bool) {
        guard overlays.isEmpty, !capturing else { return }
        capturing = true
        let hadToast = Toast.panel?.isVisible == true
        if hadToast { Toast.panel?.close() }
        let screens = NSScreen.screens.map { ($0, displayIndex($0)) }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + (hadToast ? 0.2 : 0)) {
            final class Box { var reps: [NSBitmapImageRep?]; let lock = NSLock(); init(_ n: Int) { reps = Array(repeating: nil, count: n) } }
            let box = Box(screens.count)
            DispatchQueue.concurrentPerform(iterations: screens.count) { i in
                let r = App.grab(screens[i].1)
                box.lock.lock(); box.reps[i] = r; box.lock.unlock()
            }
            let shots = zip(screens, box.reps).compactMap { sc, r in r.map { (sc.0, $0) } }
            DispatchQueue.main.async { self.showOverlays(shots, preselect: preselect) }
        }
    }

    func showOverlays(_ shots: [(NSScreen, NSBitmapImageRep)], preselect: Bool) {
        capturing = false
        guard !shots.isEmpty else { Toast.show("Ekran alınamadı (Ekran Kaydı izni?)"); return }
        let U = shots.map { $0.0.frame }.reduce(NSRect.null) { $0.union($1) }
        let full = NSImage(size: U.size)
        let scale: CGFloat
        if shots.count == 1, let (_, r) = shots.first {   // tek ekran: birleştirme kopyası (onlarca MB) yok
            r.size = U.size; scale = CGFloat(r.pixelsWide) / U.width; full.addRepresentation(r)
        } else {
            scale = shots.map { $0.0.backingScaleFactor }.max()!
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(U.width * scale), pixelsHigh: Int(U.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = U.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            for (s, r) in shots {
                r.size = s.frame.size
                r.draw(in: NSRect(x: s.frame.minX - U.minX, y: s.frame.minY - U.minY, width: s.frame.width, height: s.frame.height))
            }
            NSGraphicsContext.restoreGraphicsState()
            full.addRepresentation(rep)
        }

        let session = Session(full: full, U: U, scale: scale)
        session.windowRects = windowRects(U: U)
        session.onAction = { [weak self] action, shot, rect in
            guard let self else { return }
            let keep = self.session   // Session kendi metodunun içindeyken serbest kalmasın: bırakma bir sonraki turda
            self.overlays.forEach { $0.orderOut(nil) }; self.overlays = []; self.session = nil
            DispatchQueue.main.async { _ = keep }
            guard action != "close", let r = rect else { return }
            defaults.set([r.minX, r.minY, r.width, r.height], forKey: "lastRect")
            self.handle(action, shot, r)
        }
        self.session = session
        _ = session.sideSize; _ = session.bottomSize   // araç çubuğu boyutlarını sürüklemeden önce hesapla (ilk fare olayı takılmasın)
        let mouse = NSEvent.mouseLocation
        session.cursor = NSPoint(x: mouse.x - U.minX, y: mouse.y - U.minY)
        session.hoverRect = session.windowRects.first { $0.contains(session.cursor!) }
        NSApp.activate(ignoringOtherApps: true)
        for (screen, _) in shots {
            // dikkat: init(screen:) konumu o ekranın köşesine göre yorumlar; negatif koordinattaki (sol/üst) ekranlarda pencere ekran dışına düşer
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1) // menü çubuğunun üstünde, renk menüsünün altında
            w.isReleasedWhenClosed = false; w.hasShadow = false; w.acceptsMouseMovedEvents = true
            let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), session: session,
                                off: NSPoint(x: screen.frame.minX - U.minX, y: screen.frame.minY - U.minY))
            session.views.append(v)
            w.contentView = v
            if NSMouseInRect(mouse, screen.frame, false) { w.makeKeyAndOrderFront(nil) } else { w.orderFront(nil) }
            w.makeFirstResponder(v)
            overlays.append(w)
        }
        session.redraw()   // ilk karartma / pencere vurgusu / büyüteç katmanlara yansısın
        if preselect, let l = defaults.array(forKey: "lastRect") as? [Double], l.count == 4 {
            let r = NSRect(x: l[0] - U.minX, y: l[1] - U.minY, width: l[2], height: l[3]).intersection(session.ub)
            if !r.isNull, r.width > 3, r.height > 3 { session.sel = r; session.layoutBars(); session.redraw() }
        }
    }

    // Tam ekran kısayolları: fare hangi ekrandaysa onu al
    func fullScreen(_ action: String) {
        guard overlays.isEmpty, !capturing else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let idx = displayIndex(screen)
        DispatchQueue.global(qos: .userInteractive).async {
            let r = App.grab(idx)
            DispatchQueue.main.async {
                if let r { r.size = screen.frame.size; self.handle(action, Shot(r), nil) }
                else { Toast.show("Ekran alınamadı (Ekran Kaydı izni?)") }
            }
        }
    }

    // MARK: Eylemler

    func handle(_ action: String, _ shot: Shot?, _ rect: NSRect?) {
        if defaults.bool(forKey: "autosave"), let s = shot, ["upload", "search", "copy", "save", "print", "pin"].contains(action) { saveToFolder(s) }
        switch action {
        case "upload":
            guard let s = shot else { return }
            upload(s) { link in
                guard let link else { Toast.show("Yükleme başarısız (ayrıntı: ~/Library/Logs/LightShot.log)", seconds: 5); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(formatLink(link), forType: .string)
                Toast.show("Yüklendi, link kopyalandı ✓", link: link)
            }
        case "search":  // Google Lens görüntüyü bir linkten okur, bu yüzden önce yüklenir (görüntü herkese açık olur)
            guard let s = shot else { return }
            upload(s) { link in
                guard let link, let q = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                      let u = URL(string: "https://lens.google.com/uploadbyurl?url=" + q) else {
                    Toast.show("Arama için yükleme başarısız", seconds: 4); return
                }
                Toast.panel?.close(); NSWorkspace.shared.open(u)
            }
        case "ocr":
            guard let s = shot else { return }
            Toast.show("Yazı okunuyor…")
            recognizeText(s.rep) { text in
                if text.isEmpty { Toast.show("Yazı bulunamadı", seconds: 3); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                Toast.show("Yazı kopyalandı (\(text.count) karakter) ✓", seconds: 3)
            }
        case "pin": if let s = shot { Pins.add(s.image, rect: rect) }
        case "record": if let r = rect { startRecording(r) }
        case "scroll":
            if let r = rect {
                ScrollCapture.run(r) { rep, err in
                    if let rep { self.handle("upload", Shot(rep), nil) } else { Toast.show(err, seconds: 7) }
                }
            }
        case "copy":
            guard let s = shot else { return }
            DispatchQueue.global().async {
                let png = s.rep.representation(using: .png, properties: [:])
                DispatchQueue.main.async {
                    guard let png else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png, forType: .png)
                    Toast.show("Görüntü panoya kopyalandı ✓")
                }
            }
        case "save": if let s = shot { savePanel(s) }
        case "print": if let s = shot { printImage(s) }
        case "instantSave":
            if let s = shot { saveToFolder(s) { url in if let url { Toast.show("Kaydedildi: \(url.lastPathComponent) ✓", seconds: 4) } } }
        default: break
        }
    }

    // Kodlama ve disk yazma arka planda; bitince (varsa) then ana iş parçacığında çağrılır
    func saveToFolder(_ shot: Shot, then: ((URL?) -> Void)? = nil) {
        DispatchQueue.global().async {
            var url: URL?, err: Error?
            if let enc = shot.encoded {
                let dir = URL(fileURLWithPath: defaults.string(forKey: "folder")!)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
                let u = dir.appendingPathComponent("Screenshot \(f.string(from: Date())).\(enc.ext)")
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try enc.data.write(to: u); url = u
                } catch { err = error }
            }
            DispatchQueue.main.async {
                if let err { Toast.show("Kaydedilemedi: \(err.localizedDescription)", seconds: 5) }
                then?(url)
            }
        }
    }

    func savePanel(_ shot: Shot) {
        let ext = defaults.string(forKey: "format") == "jpg" ? "jpg" : "png"
        let sp = NSSavePanel()
        sp.allowedContentTypes = [ext == "jpg" ? .jpeg : .png]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        sp.nameFieldStringValue = "Screenshot \(f.string(from: Date())).\(ext)"
        sp.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard sp.runModal() == .OK, let url = sp.url else { return }
        DispatchQueue.global().async { if let d = shot.encoded?.data { try? d.write(to: url) } }
    }

    func printImage(_ shot: Shot) {
        let img = shot.image
        let iv = NSImageView(frame: NSRect(origin: .zero, size: img.size)); iv.image = img
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.isHorizontallyCentered = true; info.isVerticallyCentered = true
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        NSApp.activate(ignoringOtherApps: true)
        NSPrintOperation(view: iv, printInfo: info).run()
    }

    // MARK: Ekran kaydı (screencapture -v; SIGINT ile durdurulur ve dosya yazılır)

    func startRecording(_ g: NSRect) {
        guard recProcess == nil else { return }
        let primaryH = NSScreen.screens[0].frame.height
        var w = Int(g.width), h = Int(g.height); w -= w % 2; h -= h % 2   // H.264 çift boyut ister
        recPath = NSTemporaryDirectory() + "lightshot-rec-\(UUID().uuidString).mov"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-v", "-x", "-R", "\(Int(g.minX)),\(Int(primaryH - g.maxY)),\(w),\(h)", recPath]
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.finishVideo() } }
        do { try p.run() } catch { Toast.show("Kayıt başlatılamadı: \(error.localizedDescription)", seconds: 5); return }
        recProcess = p
        recItem.isHidden = false
        statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Kayıt")
        statusItem.button?.contentTintColor = .systemRed
        Toast.show("Kayıt başladı — durdurmak için menü çubuğundaki kırmızı simge → Kaydı durdur", seconds: 5)
    }

    @objc func stopRecording() { recProcess?.interrupt() }

    func finishVideo() {
        recProcess = nil; recItem.isHidden = true
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "LightShot")
        statusItem.button?.contentTintColor = nil
        guard FileManager.default.fileExists(atPath: recPath) else { Toast.show("Kayıt dosyası oluşmadı (Ekran Kaydı izni?)", seconds: 5); return }
        let dir = URL(fileURLWithPath: defaults.string(forKey: "folder")!)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let mov = dir.appendingPathComponent("Kayıt \(f.string(from: Date())).mov")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(atPath: recPath, toPath: mov.path)
        } catch { Toast.show("Kayıt kaydedilemedi: \(error.localizedDescription)", seconds: 5); return }
        guard defaults.string(forKey: "recordFormat") == "gif" else { Toast.show("Kayıt kaydedildi ✓", link: mov.absoluteString); return }
        Toast.show("GIF hazırlanıyor…")
        let gif = mov.deletingPathExtension().appendingPathExtension("gif")
        DispatchQueue.global().async {
            let ok = convertToGIF(mov, gif)
            DispatchQueue.main.async {
                if ok { try? FileManager.default.removeItem(at: mov); Toast.show("GIF kaydedildi ✓", link: gif.absoluteString) }
                else { Toast.show("GIF oluşturulamadı, video dosyası duruyor", link: mov.absoluteString) }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock'ta görünmez, sadece menü çubuğunda
app.run()
