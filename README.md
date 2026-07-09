# SimpleMounter

A lightweight macOS menu-bar app to mount **SFTP, FTP/FTPS, OneDrive and Google Drive**
as volumes in Finder, powered by [rclone](https://rclone.org) and its built-in NFS mount
(no macFUSE, no kernel extension, no reboot).

SimpleMounter is **freeware**, created by **Buscarruidos** in 2026.

## Features
- Menu-bar app (no Dock icon) with a per-connection status: 🟢 mounted / 🟡 connecting / ⚪️ not mounted
- One-click mount / unmount, "Open in Finder", and per-connection logs
- Native **Add connection** form — no Terminal needed
  - SFTP / FTP / FTPS with explicit or implicit TLS
  - Google Drive / OneDrive via in-app browser OAuth
- **Edit** any connection (host, user, port, password, TLS) from the menu or Preferences
- Each service has its own color — OneDrive dark blue, Google Drive yellow-orange,
  FTP red, SFTP teal — shown bright when mounted and dimmed when not
- Auto host-key pinning for new SFTP connections (TOFU, protects against MITM)
- Auto-remount watchdog: connections that drop are remounted in the background
- Free-space display per mounted connection
- Mount settings tuned for snappy Finder browsing: full VFS read cache, long directory
  cache with change polling (Drive/OneDrive), kernel attribute caching, read-ahead
- Preferences: open at login, notifications, auto-mount per connection, custom mounts folder
- Universal binary — runs natively on Apple Silicon and Intel

## Requirements
- macOS 13 or later
- [rclone](https://rclone.org) — `brew install rclone`
  (the app finds it under `/opt/homebrew/bin` on Apple Silicon or `/usr/local/bin` on Intel)

## Build
```bash
./package.sh        # builds a universal binary and produces SimpleMounter.app
open SimpleMounter.app
```
A sky-blue drive icon appears in the menu bar.

## Usage
1. **Add connection…** → choose the type and fill in the details.
   - SFTP / FTP / FTPS: host, user, port, password (and TLS mode for FTP).
   - Google Drive / OneDrive: click **Connect with browser** and authorize in your browser.
2. Each connection shows up in the menu with a status dot.
3. Per-connection submenu: **Mount**, **Unmount**, **Open in Finder**, **Edit…**, **View log**,
   **Reconnect** (cloud accounts), **Remove…**.
4. Volumes are mounted under `~/Mounts/<name>`.

## Notes
- Per-mount logs live at `~/Library/Logs/SimpleMounter/<name>.log`.
- Credentials and OAuth tokens are stored by rclone in `~/.config/rclone/rclone.conf`
  (obscured, and readable only by your user) — not by this app. SimpleMounter never
  passes secrets as process arguments, so they can't be snooped via `ps`.
- The read cache lives in `~/Library/Caches/rclone` (capped at 5 GB per mount).
- Changes made from another machine can take up to ~30 s to appear on Drive/OneDrive
  (change polling) and up to 15 min on SFTP/FTP (directory cache lifetime).
- The app is ad-hoc signed. On first launch on another Mac, right-click → Open, or allow it
  under System Settings → Privacy & Security.
- Versioning: releases are numbered `0.MMDD` from the build date (e.g. `0.0707` for
  July 7). `package.sh` stamps it automatically — don't edit versions by hand.

## Start at login
Toggle **Open at login** in Preferences (uses `SMAppService`), or add `SimpleMounter.app`
under System Settings → General → Login Items.

## Tech
Swift + AppKit (menu bar) and SwiftUI (windows). rclone does the heavy lifting: backends,
authentication, and the NFS mount. This app is a thin, native layer on top.

## License
Freeware — released under the [MIT license](LICENSE). © 2026 Buscarruidos.
