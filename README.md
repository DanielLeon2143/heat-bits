# Heat-Bits

Habit tracker (heat maps), calendar, to-dos, Markdown notes and alarms for **Windows** and **Android**, built as one
Flutter app. The PC and the phone sync directly over the local network: the PC runs the sync server, the phone is
the client. There is no internet server, account or cloud storage.

Releases: [latest](https://github.com/DanielLeon2143/heat-bits/releases/latest). `Heat-Bits-Windows.zip` (unzip, run
`heat_bits.exe`) and `Heat-Bits.apk` (sideload). Every push to `main` builds both (see [CI](#ci)).

---

## Architecture

```
page (InAppWebView) <-> UiServer <-> AppController <-> SyncHost (PC) | SyncClient (phone)
                                          |
                                        Store (heatbits.json) + Attachments (attachments/)
```

- **The whole UI is one web page**, `assets/web/index.html` (vanilla JS, no framework, no build step), shown in a
  web view (`flutter_inappwebview`; WebView2 on Windows). The same file runs standalone in a browser on
  `localStorage` when the app isn't there (`window.__HB_HOST__` missing).
- **Dart (`lib/`) does storage, the page bridge, LAN sync, alerts and the Windows desktop parts.** The only Flutter
  widgets are the web view, the QR scanner and the Android alarm screen.
- Role: `isHost = !Platform.isAndroid`. Windows runs `SyncHost`, Android runs `SyncClient`.

| File | Role |
|---|---|
| `assets/web/index.html` | The entire interface: habits, calendar, to-dos, notes, canvases, graphs, settings, tour |
| `lib/main.dart` | Boot, web view, Android back button, lifecycle (save on pause, sync on resume), clean close on Windows |
| `lib/app_controller.dart` | Hub between page, store and sync. Data folder moves, Obsidian folder import/export, exports |
| `lib/ui_server.dart` | Loopback HTTP server for the page (`127.0.0.1:47813`): page + boot data, SSE events, `/api/*` |
| `lib/sync_host.dart` | PC: pairing, `/hb/sync` (3-way merge), `/hb/ws` change pushes, picture transfer, UDP discovery |
| `lib/sync_client.dart` | Phone: pairing (QR/manual), host discovery, WebSocket with backoff, debounced offline-first sync |
| `lib/merge.dart` | Pure-Dart three-way merge, settings merge, habit/note clash detection (main unit-test target) |
| `lib/store.dart` | `heatbits.json` persistence, debounced atomic writes, custom data folder |
| `lib/files.dart` | Picture attachments: save/serve/list/copy, unused-picture cleanup |
| `lib/alerts.dart` | Alarms and notifications via `flutter_local_notifications` (scheduled with the OS) |
| `lib/net_util.dart` | Ports, LAN addresses (skips virtual adapters), JSON over HTTP, discovery |
| `lib/qr_svg.dart`, `lib/scan_screen.dart` | Pairing QR (SVG) and the camera scanner |
| `tool/windows/hb_desktop.cpp/.h` | Native Win32: tray icon, global Ctrl+Shift+Q quick-note popup, folder picker |
| `tool/prepare.dart` | Patches the generated `android/` and `windows/` projects (see [Building](#building)) |

## Features

- **Habits:** yes/no or measurable, per-weekday schedules and times, heat maps (calendar year, rolling or centered on
  today), streaks, an initial-goal counter, sub-trackers with their own heat maps.
- **Calendar:** month and week views (hour grid with drag/resize), plus an **Alarms** view: a clock-style list of
  everything that can ring, sorted by time, with on/off switches.
- **To-dos, activities, reminders** (one-off or repeating, monthly reminders).
- **Notes:** Markdown with a live editor, `[[links]]`, backlinks, folders (habit/tracker folders are derived from the
  habits), canvases (cards and arrows), pictures, to-do chips. Habit pages show the habit's description note and its
  other notes as tiles. Collapsible note list (Ctrl+\\).
- **Obsidian import/export:** a vault folder, a `.zip` or loose `.md`/`.canvas` files in; a `.zip` or a folder out.
  Links, embeds and JSON Canvas files are converted both ways.
- **Graphs:** habit charts, time on the calendar, and a force-directed **notes graph** (links, embeds, canvas cards).
- **Alerts:** notification or looping alarm on any habit/activity/to-do/reminder, plus standalone alarms. Each one is
  set to PC, phone or both, and fires while the app is closed.
- **Windows desktop:** tray icon (the close button hides to the tray), global **Ctrl+Shift+Q** quick-note popup, one
  instance at a time.
- **Settings:** themes and custom colours, fonts, sound, layout, data folder, export/import (JSON backup, CSV history).

---

## Data and storage

- **One JSON file**, `heatbits.json`: `{local, base, version, meta}`.
  - `local`: the full page state.
  - `base`: on the phone, the last state both devices agreed on.
  - `version`: on the PC, bumped on every change.
  - `meta`: device id, pairing, devices, scheduled alerts, pending note clashes.
- Default location: the app support directory (Windows: `%APPDATA%\com.heatbits\Heat-Bits`). On the PC it can be
  moved in **Settings → Data & storage**. The chosen folder is kept in `data-folder.txt` in the default location.
  If that folder is missing at start-up, the app falls back to the default and says so.
- Writes are debounced (300 ms) and atomic (`.tmp` + rename). An unreadable file is kept as `heatbits.json.broken-<ts>`.
- **Pictures** are files in `attachments/` next to the JSON (ids like `img-<uid>.jpg`, resized to at most 2000 px when
  added). The synced data only lists them (`files`). Pictures no note or canvas references are deleted when the app
  closes or starts.
- **Synced keys:** `habits`, `todos`, `activities`, `payments` (reminders), `alarms`, `notes`, `noteFolders`, `files`.
  Everything else is per device, apart from settings (below).

## Sync

| Port | Protocol | Use |
|---|---|---|
| `47811` | TCP (HTTP + WebSocket), all interfaces | PC sync server |
| `47812` | UDP | Discovery: `HEATBITS_DISCOVER <serverId>` → `HEATBITS_HERE <serverId> <port>` |
| `47813` | TCP, loopback only | Page ↔ app (random port if taken) |

- **Pairing:** the PC shows a QR code, `heatbits://pair?h=<ip,ip>&p=<port>&c=<CODE>&id=<serverId>&n=<name>`. The phone
  posts the 6-character code to `POST /hb/pair` and gets a bearer token. Manual entry (address + code) also works.
- **Finding the PC:** the phone tries the last host, then known hosts, then a UDP broadcast. It keeps a WebSocket open
  (`/hb/ws`, backoff 5 s → 60 s). The PC pushes `{"type":"changed"}`, and the phone syncs (debounced 700 ms).
- **Merge:** the phone sends `{base, doc}` to `POST /hb/sync`, and the PC runs `merge3(base, pc, phone)`:
  - A change on one side wins.
  - Maps merge key by key, and lists of `{id}` items merge item by item.
  - Delete vs. untouched → deleted. Delete vs. edit → the edit is kept.
  - A remaining clash takes the phone's value.
- **First sync:** the first sync after pairing keeps everything from both sides. Habits with the same name but
  different ids are shown to the user first (keep the PC's, keep the phone's, or keep both with one renamed).
- **Note clashes:** a note whose title or text changed differently on both devices isn't merged. The PC keeps its
  text, and the phone asks which version to keep (PC's, phone's, or both as separate notes). Older phones that don't
  send `caps: ['noteClashes']` keep the old behaviour (the phone wins).
- **Settings** sync while **Sync settings** is on on both devices, except per-device ones (tutorial, sounds-due,
  tray, hotkey). The PC wins clashes on the first sync.
- **Pictures** transfer after each sync (`/hb/file/<id>`): the phone uploads what the PC lacks and downloads what it
  lacks.
- The phone works offline and syncs when it can reach the PC. Heat-Bits must be running on the PC (the tray counts).

## Security

- The page server listens on loopback only, and every `/api/*` call needs a per-launch random key (`x-hb-key`).
- Sync calls need the per-phone bearer token issued at pairing. Phones can be removed on the PC.
- **LAN traffic is plain HTTP/WebSocket (no TLS).** It is meant for a trusted home network, so don't pair over
  public Wi-Fi.
- Picture ids and Obsidian folder paths are validated, so nothing reads or writes outside its folder.

## Alerts

- The page builds this device's alert list for the next 14 days (`alertList()`) and posts it to `/api/alerts`.
  `alerts.dart` diffs it against what's scheduled and uses `zonedSchedule` with UTC times.
- **Android:** exact alarms, the alarm audio stream, `FLAG_INSISTENT`, a full-screen intent and Snooze/Stop actions.
  An alarm set on the PC reaches the phone at its next sync.
- **Windows:** toasts, using `scenario="alarm"` with a looping sound for alarms.
  - On start-up the app writes `HKCU\Software\Classes\CLSID\{guid}\LocalServer32`, so a toast button can start it.
  - Windows drops every *scheduled* toast from an app that has never shown one immediately ("Element not found" in
    `Microsoft-Windows-PushNotification-Platform/Operational`). The app registers itself on start-up with one
    silent toast.

## Windows specifics

- Closing the window while the WebView2 engine is alive crashes Flutter (`0xC000041D`). So `WM_CLOSE` goes to Dart
  first: it flushes the page, removes the web view, stops the servers, then destroys the window (with a 5 s fallback).
- With **Keep running when closed** on, the close button minimizes and then hides the window. Minimizing first keeps
  WebView2's own input window from staying over the desktop. **Quit** in the tray menu does a real close.
- Single instance: the `HeatBits.Running` mutex. A second launch shows the first window.
- Global hotkey Ctrl+Shift+Q (`RegisterHotKey`): a native popup when another app is focused, the page's own quick
  note when Heat-Bits is. Both can be turned off in Settings → Layout.

---

## Install and pair

1. **PC (Windows 10/11):** unzip `Heat-Bits-Windows.zip`, keep the folder together, run `heat_bits.exe`. Allow it on
   **Private networks** at the firewall prompt, or phones can't connect. Requires WebView2, which comes with
   Windows 10/11; otherwise install the Evergreen runtime.
2. **Phone (Android 5+):** scan **Get the Android app** in the PC's Settings → Devices & sync, or download the APK
   from Releases, then install it, allowing installs from the browser.
3. **Pair:** phone and PC on the same Wi-Fi (guest networks usually isolate devices). On the phone: Settings →
   Devices & sync → **Scan QR code**, or type the PC's address and code.

**Updating:** replace the Windows folder and install the new APK. If Android refuses ("App not installed"),
uninstall first and pair again. The data comes back from the PC.

## Troubleshooting

- **Phone can't find the PC:** check both are on the same network, Heat-Bits is running on the PC, and the firewall
  allows `heat_bits` on Private networks. Only one PC instance can bind `47811`; a second one shows "port already in
  use" in Settings.
- **No notifications on Windows:** check Windows notification settings for Heat-Bits and Do Not Disturb. The event log
  above shows dropped toasts.
- **Blank window on Windows:** WebView2 is missing.
- **Corrupt data file:** look for `heatbits.json.broken-<ts>` next to it. Export/import (JSON) is the manual backup.

---

## Building

Platform folders (`android/`, `windows/`, …) are generated and gitignored. Create them once:

```
flutter create --platforms=windows,android --org com.heatbits --project-name heat_bits .
dart run tool/prepare.dart
flutter pub get
```

`prepare.dart` is safe to re-run. Native changes go there, never in the generated folders. It patches:

- Android: permissions (network, camera, notifications, exact alarms, full-screen intent), cleartext HTTP,
  `minSdk ≥ 21`, the notification plugin's receivers, `showWhenLocked`, core library desugaring and the status-bar icon.
- Windows: app name and window size, the `heatbits/window` close channel, copying `tool/windows/hb_desktop.*` into the
  runner, the single-instance mutex, and `-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` (needed with
  MSVC 14.5x / VS 2026).

Commands:

- Run: `flutter run -d windows` or `flutter run -d <android device>`
- Tests: `flutter test` (pure Dart: merge, clash detection, picture cleanup)
- Lint: `flutter analyze`
- Release build of both: `powershell -ExecutionPolicy Bypass -File build.ps1`
- Inspect the page on Windows: build with `--dart-define=HB_DEVTOOLS=true` (DevTools protocol on `127.0.0.1:9222`).
  Don't ship that build.

**Requirements:**

- Flutter **3.47.7**.
- Windows: Visual Studio Build Tools with *Desktop development with C++* and the **C++ ATL** component (the
  notifications plugin includes `atlbase.h`). A fresh `build/` needs `nuget.exe` on `PATH`, because the WebView plugin
  downloads NuGet packages.
- Android: the Android SDK and **JDK 17**.

**Pinned:** `flutter_inappwebview: 6.2.0-beta.3`, exact and for the whole family. 6.1.5's Android part uses
`proguard-android.txt`, which AGP 9 rejects, and `^` pulls mixed versions.

## CI

`.github/workflows/build.yml` runs on every push to `main`/`master`. It runs `flutter test`, builds the APK and the
Windows zip, and publishes them as a GitHub release.

## Repo docs

- `CLAUDE.md`: detailed developer notes, including the page ↔ app contract, the sync model, notes, alerts, the tray,
  dragging and the phone layout.
- `heat-bits-tutorial-context.md`: every screen, selector and guided-tour step.
