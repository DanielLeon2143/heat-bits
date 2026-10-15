# Heat-Bits (Flutter: Windows + Android)

Habit heat maps, calendar and to-dos. One Flutter app for Windows and Android that wraps a single web UI
and adds file storage plus two-way sync over the home Wi-Fi (PC = host, phone = client).

## The big picture

- **All UI lives in `assets/web/index.html`** (~370 KB, one file, vanilla JS). It's the same page as
  the web version of Heat-Bits. Screen/UX changes go there, not in Dart.
- **`lib/` only does storage, the local bridge and LAN sync.** There are no Flutter widgets apart from
  the web view (`main.dart`) and the QR camera (`scan_screen.dart`).
- `isHost = !Platform.isAndroid`: Windows runs `SyncHost`, Android runs `SyncClient`.

```
page (InAppWebView) <-> UiServer <-> AppController <-> SyncHost (PC) | SyncClient (phone)
                                          |
                                        Store (heatbits.json)
```

| File | Role |
|---|---|
| `lib/main.dart` | Boot: opens `Store`, starts `AppController`, shows the web view at `http://127.0.0.1:<uiPort>/`. External links are blocked. Back button and lifecycle handling (save on pause, sync on resume). |
| `lib/app_controller.dart` | Hub. `onPageSave` / `applyNetworkData` / `_pushToPage`. Uses `uiRev` + `_revData` so a save made from a stale page gets merged instead of overwriting newer synced data. |
| `lib/ui_server.dart` | Localhost-only HTTP for the page: `GET /` (HTML with boot data injected), SSE `/api/events` (`state`, `status`), `/api/save`, `/api/sync/*`, `/api/pair/*`, `/api/devices/remove`, `/api/export`. Every `/api/*` needs the per-launch key (`x-hb-key` header or `?k=`). |
| `lib/sync_host.dart` | PC: `GET /hb/hello`, `POST /hb/pair` (6-char code → token), `POST /hb/sync` (Bearer token, 3-way merge), `GET /hb/ws` (pushes `{"type":"changed"}`), UDP discovery reply. |
| `lib/sync_client.dart` | Phone: pairing (QR or manual), finds the PC (last host → known hosts → UDP broadcast), WebSocket with backoff (5s→60s), debounced sync (700 ms), offline-first. |
| `lib/merge.dart` | `merge3(base, a, b)`, `deepEq`, `syncKeys`, `syncPart`. Pure Dart, so it's the main unit-test target. |
| `lib/store.dart` | One JSON file `heatbits.json` in the app support dir: `{local, base, version, meta}`. Saves are debounced (300 ms) and atomic (`.tmp` + rename). An unreadable file is kept as `.broken-<ts>`. |
| `lib/net_util.dart` | Ports, `localAddresses()` (skips virtual adapters), `httpJson`, `discoverHost`. |
| `lib/qr_svg.dart` | Pairing QR as SVG (served at `/api/pair/qr.svg`). |
| `tool/prepare.dart` | Patches the generated `android/` and `windows/` files: permissions, cleartext HTTP, camera feature, minSdk ≥ 21, app name and window size. Safe to re-run. |

### Ports
- `47811` TCP: PC sync server (HTTP + WebSocket, all interfaces)
- `47812` UDP: discovery (`HEATBITS_DISCOVER <serverId>` → `HEATBITS_HERE <serverId> <port>`)
- `47813` TCP: UI server, loopback only (falls back to a random port if taken)

### Page ↔ app contract (keep both sides in step)
- `index.html` line 4 holds `<!--HB_BOOT-->`. `UiServer._page` replaces it with
  `window.__HB_HOST__ = {key, role, platform, rev}` and `window.__HB_BOOT_STATE__`.
- When `__HB_HOST__` is missing, the page runs standalone on `localStorage`. Keep that path working, because
  the same file is the web version.
- The page saves through `/api/save` with `{rev, state}` and listens on `/api/events`. If you rename an
  endpoint or field, change both `ui_server.dart` and the page (search for `hbApi(` in index.html).

### Sync model
- Only `syncKeys = ['habits', 'todos', 'activities', 'payments']` sync ("payments" are called reminders
  in the UI). Settings, theme, layout etc. stay per device.
- Three-way merge: a change on one side wins. Changes on both sides merge maps key by key and merge
  lists of `{id: …}` maps item by item. A real clash takes `b` (the incoming side, `preferB: true`).
  Delete vs. untouched → deleted. Delete vs. edit → the edit is kept.
- The phone stores `base` (last agreed state). The PC bumps `store.version` on every change.
- A first sync after pairing (`base == null`) keeps everything on both devices (`firstMerge`). Before it, the phone
  peeks at the PC's data (`/hb/sync` with `peek: true`). Habits with the same name but different ids
  (`habitNameClashes`) go to the page as `status.conflicts`, and nothing syncs until the user picks in the dialog
  (`#clashModalBackdrop` → `/api/sync/resolve`): keep the PC's (the phone's is removed), keep the phone's (the PC's id goes
  in `meta.firstDrop` and the PC drops it), or keep both with the phone's renamed.
- QR payload: `heatbits://pair?h=<ip,ip>&p=<port>&c=<CODE>&id=<serverId>&n=<PC name>`.

### Dragging inside the app
Native HTML5 drag-and-drop never reaches the page in the app: the WebView2 composition controller
doesn't forward OLE drag, and Android doesn't start it from touch. `hbPointerDrag()` in index.html
(only when `HB` is set) runs drags on pointer events instead. It blocks the trusted `dragstart` and
replays synthetic `dragstart`/`dragover`/`dragleave`/`drop`/`dragend` with a stand-in `dataTransfer`, so the
existing drop handlers work unchanged. For any new drag source, add `draggable="true"` and a
`dragstart` that calls `setData`. For any new target, use `dragover` (preventDefault) + `drop`. Touch drags start
immediately from `.drag-handle`, and after a 350 ms hold anywhere else.
The habit/activity blocks in the hour grid still move with their own `mousedown` code, so mouse only.
While dragging near the top or bottom of the screen, the page itself scrolls (phones: task list → week grid).

### Guided tour
`startTour()` in index.html (section `guided tour`) highlights one element per step and explains it in a card.
`tourSteps()` builds the steps for the layout (PC, collapsed sidebar, phone, unpaired phone).
`heat-bits-tutorial-context.md` documents every screen, selector and step, so keep it in step with `tourSteps()`.
- It opens by itself only on a fresh start (no habits and `settings.demoAdded` not set), and is remembered in
  `settings.tutorialSeen`, which is per device and never syncs. Otherwise it's reached from **Help & tour**
  (`#helpOpenBtn`, under the New habit box), from **?** (`.help-item`) in the collapsed sidebar, or from Settings → Help.
- Example habits carry `demo: true`. The last step offers to remove them, and `settings.demoAdded` stops them coming back.
- If you rename or move an element the tour points at, update its selector in `tourSteps()`.

### Phone layout (`.app.phone`, width ≤ 700px)
- The sidebar is hidden. `renderBottomNav()` fills `#bottomNav`, a fixed tab bar: This Week, Calendar,
  Habits (2×2 grid icon), Graphs, Settings. The Habits tab opens `#habitSheetBackdrop`, a bottom sheet of
  habit tiles (All Habits, each habit, New habit). The sheet pushes a history entry, so Android's back
  button closes it (`main.dart` calls `goBack()` when the page can go back).
- Calendar: compact header, the week fits the screen (`38px repeat(7, minmax(0, 1fr))`), the grid is capped at
  60% of the screen height so the task list stays close, and sideways swipes change the month/week
  (`wireCalSwipe`). `overscroll-behavior-x: none` stops the browser treating those swipes as "back".
- Help: phones have no sidebar, so the tour is under Settings → Help → **Show the tour** (`#settingsTourBtn`).
- Preview without a phone: headless Edge with `Emulation.setDeviceMetricsOverride` (400 px wide, mobile) on a copy
  of index.html whose localStorage is seeded from `heatbits.json`'s `local`.

## Commands

Platform folders (`android/`, `windows/`, …) are **generated and gitignored**. Create them once:

```
flutter create --platforms=windows,android --org com.heatbits --project-name heat_bits .
dart run tool/prepare.dart
flutter pub get
```

- Tests: `flutter test` (pure Dart tests on `merge.dart`, no platform folders needed)
- Lint: `flutter analyze`
- Run: `flutter run -d windows`, or `flutter run -d <android device>`
- Release build of both: `powershell -ExecutionPolicy Bypass -File build.ps1`
- CI: `.github/workflows/build.yml` (Flutter **3.47.7**, runs `flutter test` and builds the APK and the Windows zip on push to main/master)

Native changes (manifest, gradle, runner, CMake) **go in `tool/prepare.dart`**, never in the generated folders,
because those get recreated on every CI run.

### Local toolchain on this PC
- Flutter 3.47.7 at `C:\src\flutter`, portable JDK 17 at `C:\src\jdk17` (set with `flutter config --jdk-dir`;
  the system `java` is 8, which is too old), Android SDK at `%LOCALAPPDATA%\Android\Sdk` (command-line
  tools only, no Android Studio), `nuget.exe` at `C:\src\nuget`, VS Build Tools 2026.
- `adb` is at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` and isn't on PATH.

### Why some versions are pinned
- `flutter_inappwebview: 6.2.0-beta.3` (exact). The 6.1.5 Android part uses `proguard-android.txt`, which
  AGP 9 rejects. Keep the whole inappwebview family on the same beta. Don't use `^`, because it pulls mixed versions.
- `prepare.dart` adds `-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` to `windows/CMakeLists.txt`.
  Without it, MSVC 14.5x (VS 2026) errors out on the plugin's `<experimental/coroutine>`.
- **Window close (Windows):** destroying the engine while an `InAppWebView` is alive crashes
  (`0xC000041D` in flutter_windows.dll). This reproduces with a bare app that has only a web view.
  `prepare.dart` patches `windows/runner/flutter_window.cpp` so that `WM_CLOSE` goes to Dart over the
  `heatbits/window` channel (`close`). `_WebHomeState._close` flushes the page (`window.__hbFlush`), removes
  the web view, stops the servers, then calls `destroy`. If Dart doesn't answer, a 5 s timer closes the window anyway.
  `prepare.dart` normalises CRLF to LF before patching, because `flutter create` writes CRLF.

### Testing the sync without a phone
Run the release exe, then use a script that acts as a phone. Read the key from `GET 127.0.0.1:47813/`
(`__HB_HOST__.key`) and the pair code from `/api/sync/status`. Then `POST /hb/pair`, `POST /hb/sync`
and open `ws://<ip>:47811/hb/ws?token=…`. Remove the test device afterwards with `/api/devices/remove`.

### Inspecting the page in the Windows app
`flutter build windows --release --dart-define=HB_DEVTOOLS=true` opens the DevTools protocol on
`127.0.0.1:9222`. Neither the `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` env var nor the WebView2 policy works,
because the plugin builds the environment itself. Drive it with `Runtime.evaluate` / `Input.dispatch*Event`. CDP input
skips the OS layer, so check drag/mouse changes with real input (SendInput) too. Rebuild without the
flag before shipping.

## Conventions
- Error strings and README text are written for non-technical users. Use plain sentences and say what to do next
  (e.g. "Can't find your PC on this Wi-Fi. Is Heat-Bits open on it?").
- Comments are short and explain *why*. Match the existing tone.
- Networking and disk code catches and ignores errors on purpose (best effort, retried later). Don't
  add exceptions that can crash the app.
- Dependencies are deliberately few (see `pubspec.yaml`). Prefer `dart:io` over new packages.

## Gotchas
- `index.html` is huge. Use Grep and read with offsets, never the whole file at once.
- Only one PC instance can bind 47811. A second one shows "port already in use" in Settings.
- Windows asks for firewall permission on the first run. Without it, phones can't reach the PC.
- All text files are UTF-8 without a BOM, and README/pubspec contain `—` and `→`. Windows PowerShell 5.1
  *displays* them as `â€"`, and `Get-Content | Set-Content` really corrupts them (and adds a BOM).
  Edit with the Edit tool or `sed`, never with PowerShell's Set-Content.
- Android needs `usesCleartextTraffic` (plain HTTP to 127.0.0.1 and to the PC). `prepare.dart` sets it.
