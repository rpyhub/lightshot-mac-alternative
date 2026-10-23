#!/bin/sh
# LightShot.app'i derler, imzalar ve /Applications'a kurar.
#   ./build.sh                  derle + sabit sertifikayla imzala + kur (önerilen: Ekran Kaydı izni güncellemelerde korunur)
#   ADHOC=1 ./build.sh          sertifika/anahtarlık kullanmadan geçici imza (izin her derlemede yeniden sorulur)
#   NO_INSTALL=1 ./build.sh     sadece derle, /Applications'a kopyalama
set -e
cd "$(dirname "$0")"
APP=LightShot.app
VERSION=1.0.1
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Xcode lisansı onaylı değilse Command Line Tools ile derle
[ -d /Library/Developer/CommandLineTools ] && export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swiftc -O -wmo -target arm64-apple-macos13 main.swift Overlay.swift Features.swift -o "$APP/Contents/MacOS/LightShot"
cp assets/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LightShot</string>
<key>CFBundleIdentifier</key><string>local.lightshotmac</string>
<key>CFBundleName</key><string>LightShot</string>
<key>CFBundleDisplayName</key><string>LightShot</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF

CERT="LightShot Local"
if [ -n "$ADHOC" ]; then
  codesign --force -s - "$APP"; echo "İmza: geçici (ADHOC): Ekran Kaydı izni her derlemede yeniden sorulur"
else
  # Sabit imza: her derlemede aynı sertifika kullanılır, böylece Ekran Kaydı izni korunur.
  # Sertifika yoksa bir kez oluşturulup giriş anahtarlığına eklenir (güven ayarı değiştirilmez).
  if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
    echo "İlk kurulum: giriş anahtarlığına '$CERT' imza sertifikası ekleniyor (macOS izin isteyebilir)."
    T=$(mktemp -d)
    printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=%s\n[v3]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$CERT" > "$T/o.cnf"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k.pem" -out "$T/c.pem" -days 3650 -config "$T/o.cnf" -extensions v3 2>/dev/null
    openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/c.p12" -passout pass:ls \
      -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
    security import "$T/c.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P ls -T /usr/bin/codesign >/dev/null
    rm -rf "$T"
  fi
  # macOS anahtarlık izin penceresi açarsa codesign sonsuza dek bekler: 30 sn sonra durdur ve ne yapılacağını söyle
  codesign --force -s "$CERT" "$APP" 2>/dev/null &
  CS=$!; i=0
  while kill -0 $CS 2>/dev/null && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  if kill -0 $CS 2>/dev/null; then
    kill $CS
    echo "DURDU: ekranda '$CERT' anahtarı için bir macOS izin penceresi açık olabilir."
    echo "Pencerede 'Her Zaman İzin Ver'e bas (gerekirse Mac şifreni gir), sonra ./build.sh'ı tekrar çalıştır."
    echo "(Geçici imza ATILMADI: imza değişirse Ekran Kaydı izni yeniden sorulur. Anahtarlığa dokunmak istemezsen: ADHOC=1 ./build.sh)"
    exit 1
  fi
  if wait $CS; then echo "İmza: $CERT (sabit)"
  else codesign --force -s - "$APP"; echo "UYARI: sabit sertifika kullanılamadı, geçici imza atıldı (izin her derlemede sorulur)"; fi
fi

[ -n "$NO_INSTALL" ] && { echo "Derlendi: $PWD/$APP"; exit 0; }
rm -rf "/Applications/$APP"; cp -R "$APP" /Applications/
echo "Kuruldu: /Applications/$APP"
