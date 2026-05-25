# Paster

A tiny clipboard manager for macOS. Lives in the menu bar, remembers what you copy (text, images, PDFs), brings it back when you hit `⌘⇧V`.

Built because I got tired of paying for Paste every year.

![Paster popover](screenshots/popover.png)

## Download

Grab the latest `.pkg` from the [Releases page](../../releases/latest).

### Install

1. Right-click `Paster.pkg` → **Open**
   *(Double-click won't work — macOS blocks unsigned apps.)*
2. Click **Open** on the warning dialog.
3. Continue → Continue → Install. Enter your password.

Done. The icon appears in your menu bar. Press `⌘⇧V` from anywhere to open it.

## Features

- Text, images (PNG / JPG / HEIC / GIF / TIFF / WEBP / BMP) and PDFs
- Inline search — type to filter the same list you're already looking at
- Global hotkey `⌘⇧V`, works in fullscreen apps
- AES-256-GCM encryption, key stored in macOS Keychain
- Localized (English / Russian) with native time formatting
- Universal binary (Apple Silicon + Intel)
- Under 1 MB total

## Limits

| | |
|---|---|
| Text history | 30 MB / 14 days |
| Single image | 10 MB |
| Single PDF | 25 MB |
| Total blobs | 300 MB / 14 days |

Everything lives in `~/.paster/`. Encrypted at rest. Nothing leaves your machine.

## Build from source

```bash
git clone https://github.com/USERNAME/paster.git
cd paster/swift
./build.sh           # produces build/Paster.app
./package_pkg.sh     # produces build/Paster.pkg
```

Requires Xcode Command Line Tools (`xcode-select --install`). No Xcode app needed.

## Tech notes

- Swift 6 / AppKit + SwiftUI for the popover
- `RegisterEventHotKey` (Carbon) for the global hotkey — no Accessibility permission needed
- `SMAppService` for launch-at-login
- `CryptoKit` for AES-GCM
- `sqlite3` C API directly (no ORM)
- Custom `NSPanel` instead of `NSPopover` to position correctly in fullscreen

## License

MIT. See [LICENSE](LICENSE).
