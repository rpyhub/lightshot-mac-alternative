<div align="center">

<img src="docs/icon.png" width="140" alt="LightShotMac icon">

# LightShotMac

**A fast, Lightshot-style screenshot tool for macOS.**
Select an area, annotate it, and upload it, or copy text out of it, pin it, record it, or scroll-capture a long page.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-informational)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Türkçe README](README.tr.md)

<img src="docs/overlay.png" width="820" alt="Capture screen with annotation tools">

</div>

> **Heads up:** the app interface is currently **Turkish**. Translations are very welcome, see [Contributing](#contributing).

## Features

**Capture**
- Global hotkey (default **⌃1**), freezes **all monitors**; drag a selection across screens
- Hover a window and click to select it whole
- Magnifier with a **color picker** (press **C** to copy the HEX value)
- Resize handles, move the selection, repeat the last area (**⌃4**), delayed capture (3 / 5 / 10 s)
- Full-screen hotkeys: save to a folder (**⌃2**) or upload (**⌃3**)

**Annotate**
- Pen, line, arrow, rectangle (optionally filled), highlighter, text, **numbered step markers**
- **Blur / pixelate** tool to hide secrets
- Select, move and delete drawings afterwards; line thickness; color palette; undo (⌘Z)

**Share**
- One-click upload with the link copied to your clipboard (plain, Markdown, HTML or BBCode) and a **QR code**
- Hosts: freeimage.host, pixhost.to, uguu.se, ImgBB, Imgur, or **your own S3 / Cloudflare R2 bucket** (auto-delete supported)
- Automatic fallback: if a host fails, the next one is tried; hosts that failed recently are tried last
- Upload history in the menu bar, PNG or JPG output, Google Lens reverse image search, printing

**Extras**
- **OCR**: copy the text out of any area (Apple Vision, Turkish and many other languages)
- **Pin to screen**: keep a screenshot floating above other windows
- **Scroll capture**: stitches a long web page or document into one tall image
- **Screen recording** of an area to MOV or GIF
- Auto-save every capture to a folder, launch at login

## Screenshots

<table>
<tr>
<td><img src="docs/settings-genel.png" alt="Settings: General"></td>
<td><img src="docs/settings-yukleme.png" alt="Settings: Upload"></td>
<td><img src="docs/settings-goruntu.png" alt="Settings: Image and recording"></td>
</tr>
</table>

<p align="center"><img src="docs/toast.png" width="360" alt="Upload notification with link, QR and copy buttons"></p>

## Requirements

- macOS **13 Ventura or newer**
- **Apple Silicon** (M1 or newer). The build script targets `arm64`; Intel is not supported yet
- Xcode Command Line Tools: `xcode-select --install` (no full Xcode needed)

## Build and install

```bash
git clone https://github.com/rpyhub/lightshot-mac-alternative.git
cd lightshot-mac-alternative
./build.sh
open /Applications/LightShot.app
```

`build.sh` compiles the app, signs it and copies it to `/Applications`.

**Signing and permissions.** macOS ties the *Screen Recording* permission to the app's signature. By default the script creates a small self-signed certificate called **"LightShot Local"** in your login keychain (it does not change any trust settings), so the permission **survives rebuilds**. macOS may ask you once to allow `codesign` to use that key: choose *Always Allow*.
If you would rather not touch your keychain: `ADHOC=1 ./build.sh` (macOS will then ask for Screen Recording permission again after every rebuild). To only compile without installing: `NO_INSTALL=1 ./build.sh`.

### First run

1. Press **⌃1**. macOS asks for **Screen Recording** permission: open *System Settings → Privacy & Security → Screen Recording*, enable **LightShot**, then choose *Quit & Reopen*.
2. **Scroll capture** also needs **Accessibility** permission (it scrolls the page for you). macOS asks the first time you use it.

## Usage

| Shortcut | Action |
|---|---|
| **⌃1** | Capture an area (configurable) |
| **⌃2** | Save the full screen to your folder |
| **⌃3** | Upload the full screen |
| **⌃4** | Repeat the last area |

Inside the capture screen: **Enter / ⌘D** upload · **⌘C** copy · **⌘S** save · **⌘P** print · **⌘Z** undo · **Delete** remove the selected drawing · **C** copy color under the cursor · **Esc** cancel.

All shortcuts, the upload host, link format, image format, auto-save folder and more are in the menu bar icon → **Ayarlar…** (Settings).

## Privacy and security

- Screenshots stay on your Mac **until you press upload**. Uploads go to the host you chose (and to the fallback hosts if it fails). Anyone with the link can see the image.
- **Google Lens search uploads the image first**, because Lens only accepts a link.
- The **freeimage.host** key in the source is the public demo key from that site's own API documentation. Keys for ImgBB / Imgur are stored in the app's preferences; the **S3 secret key is stored in the macOS Keychain**.
- Links returned by upload hosts are only opened if they start with `http://` or `https://`.
- Failed uploads are logged (without credentials) to `~/Library/Logs/LightShot.log`, capped at about 256 KB.

## Development

```bash
./tests/run.sh        # AWS signature vectors, scroll stitching, OCR, memory leak check, ...
./scripts/make_icon.sh   # regenerate the app icon
./scripts/release.sh     # build, install and zip for a GitHub release (dist/)
```

| File | What it does |
|---|---|
| `main.swift` | App, hotkeys, settings, capture pipeline, upload hosts, recording |
| `Overlay.swift` | Capture screen: selection, annotation tools, magnifier, toolbars, notifications |
| `Features.swift` | OCR, pinning, QR, S3/R2 (AWS Signature V4), window list, GIF, scroll stitching |
| `tests/` | Self-contained test runner (no test framework needed) |

No third-party dependencies, only Apple frameworks (AppKit, Vision, CryptoKit, AVFoundation, Carbon).

## Contributing

Issues and pull requests are welcome. Good first contributions:
- **Localization** (English UI strings are the most wanted)
- Intel / universal build
- A ScreenCaptureKit capture path (faster, but see the macOS 15+ recurring permission prompt)
- Notarized releases

Please run `./tests/run.sh` before opening a pull request.

## Disclaimer

LightShotMac is an independent open-source project. It is **not affiliated with, endorsed by, or connected to Lightshot or Skillbrains**; "Lightshot" is a trademark of its respective owner. The name here only describes the workflow it is inspired by.

## License

[MIT](LICENSE)
