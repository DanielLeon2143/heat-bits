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
| `lib/store.dart` | One JSON file `heatbits.json`: `{local, base, version, meta}`. Saves are debounced (300 ms) and atomic (`.tmp` + rename). An unreadable file is kept as `.broken-<ts>`. It lives in the app support dir unless `data-folder.txt` there names another folder (Settings → **Data & storage** `#dataCard`, PC only: `AppController.checkFolder` / `moveData`, `/api/data/*`, native picker `pickFolder` → `folderPicked` in hb_desktop.cpp). Moving copies heatbits.json + `attachments/` and leaves the old copy; "use" loads the file already there but keeps this device's `meta` (pairing), and the page reloads. A missing custom folder falls back to the default with `store.folderProblem`. |
| `lib/net_util.dart` | Ports, `localAddresses()` (skips virtual adapters), `httpJson`, `discoverHost`. |
| `lib/qr_svg.dart` | Pairing QR as SVG (served at `/api/pair/qr.svg`). |
| `lib/files.dart` | Pictures in notes/canvases: `Attachments` keeps them in `attachments/` next to heatbits.json (`save`, `serve`, `list`, `validId`). |
| `lib/alerts.dart` | Alarms/notifications via `flutter_local_notifications`: `apply()` diffs the page's list against `meta['alerts']`, `test()`, Snooze/Stop handling, Android background handler `alertBackgroundResponse`. The alarm screen (`AlarmScreen`) is in `main.dart`. |
| `tool/windows/hb_desktop.cpp` / `.h` | PC only, native C++: the tray icon (the X hides the window), Ctrl+Shift+Q from any program, and the quick-note popup. `prepare.dart` copies it into `windows/runner` and hooks it into `flutter_window.cpp`. |
| `tool/prepare.dart` | Patches the generated `android/` and `windows/` files: permissions, cleartext HTTP, camera feature, minSdk ≥ 21, app name and window size, plus for alerts: notification/exact-alarm/full-screen permissions, the plugin's receivers, `showWhenLocked`, core library desugaring and the status-bar icon `ic_stat_heatbits`. Safe to re-run. |

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
- The data is `syncKeys = ['habits', 'todos', 'activities', 'payments', 'alarms', 'notes', 'noteFolders', 'files']` ("payments" are called reminders in the UI).
- **Pictures** never go inside the synced data. `files` only lists them (`{id, name, type, w, h, size, created}`, id like
  `img-<uid>.jpg`). The page uploads the bytes to `POST /api/files?id=` and shows them from `GET /files/<id>?k=<key>`.
  Each `/hb/sync` reply carries `files` (the ids on the PC's disk). Afterwards `SyncClient._syncFiles` POSTs the phone's
  missing ones to `/hb/file/<id>` and GETs the ones it lacks (Bearer token). Arrivals send the page a `files` event, and
  `retryMissingImages()` reloads images that failed. In a browser, pictures live in localStorage (`heat-bits-files`).
  Notes write them as `![[img-….jpg]]` / `![[…|300]]`; canvases use cards `{type: "image", file}`. Unused files aren't cleaned up.
  The page has the same list as `HB_SYNC_KEYS`.
- Settings sync too while **Sync settings** (`settings.syncSettings`, a switch in Devices & sync, on by default) is on
  on *both* devices. `sharedPrefs()` = `settings` minus `localSettings` (tutorialSeen, demoAdded, soundDueDay,
  syncSettings, closeToTray, globalHotkey; the page has the same list as `HB_LOCAL_SETTINGS`) plus `allColor`. The phone sends `prefs` and
  `prefsBase` (kept in `meta.prefsBase`) with each sync; the PC merges them with `mergePrefs` (the PC wins clashes the
  first time) and answers with `prefs`. The page applies settings it's sent in `hbApplyRemote` and calls `applySettings()`.
  `AppController._pagePart` adds `_prefs` to what the rev mechanism compares, so a stale page save can't undo synced settings.
- Three-way merge: a change on one side wins. Changes on both sides merge maps key by key and merge
  lists of `{id: …}` maps item by item. A real clash takes `b` (the incoming side, `preferB: true`).
  Delete vs. untouched → deleted. Delete vs. edit → the edit is kept.
- **Notes edited on both:** a note's `title`/`body` changed differently on both sides since `base` (`noteClashes` in
  merge.dart) isn't settled by the merge. A phone that sends `caps: ['noteClashes']` gets the PC's text kept for those notes
  (`keepPcText`; other fields still merge) plus `noteClashes` in the reply. It saves its own version in `meta.noteClashes`,
  reports them as `status.noteConflicts`, and the page asks (`#noteClashBackdrop`, also a **Choose** button in Devices & sync):
  keep the PC's, keep the phone's, or both (the phone's becomes a new note, "(phone)" after its title), → `/api/sync/notes`
  → `SyncClient.resolveNotes`. A phone without the cap gets the old behaviour (its text wins).
- The phone stores `base` (last agreed state). The PC bumps `store.version` on every change.
- A first sync after pairing (`base == null`) keeps everything on both devices (`firstMerge`). Before it, the phone
  peeks at the PC's data (`/hb/sync` with `peek: true`). Habits with the same name but different ids
  (`habitNameClashes`) go to the page as `status.conflicts`, and nothing syncs until the user picks in the dialog
  (`#clashModalBackdrop` → `/api/sync/resolve`): keep the PC's (the phone's is removed), keep the phone's (the PC's id goes
  in `meta.firstDrop` and the PC drops it), or keep both with the phone's renamed.
- QR payload: `heatbits://pair?h=<ip,ip>&p=<port>&c=<CODE>&id=<serverId>&n=<PC name>`.

### Notes
Section `notes` in index.html: Markdown notes like Obsidian (page `NOTES`, sidebar item and 6th phone tab).
- Data: `state.notes` `[{id, title, body, folder, created, updated}]` and `state.noteFolders` `[{id, name, parent}]` (user folders).
  The `habits` folder ("Habits"), habit folders `h:<habitId>` inside it, tracker folders `t:<habitId>:<trackerId>`, and
  `quick` ("Quick notes") are **not stored**: `noteFolderList()` derives them from the habits. `quickNote()` (Ctrl+Shift+Q,
  a capture-phase listener) and the New note dialog both go through `makeNoteAndWrite(folder, title)`. Deleting a habit/tracker calls `keepHabitNotes` / `keepTrackerNotes`, which turn its folder into a user folder.
  Anything pointing at a missing folder shows at the top. `state.notesUi` (open folders, selection, mode) is per device.
- `mdRender()` is a small hand-written Markdown renderer: it escapes everything first, then adds headings, lists, tasks,
  quotes, code, bold/italic/strike, `[text](https…)` and `[[Title]]` / `[[Title|text]]`. Never let raw HTML through.
- Links resolve by title, ignoring case (`findNoteByTitle`, same folder first). A missing link creates the note. `renameNote` rewrites links.
  Ticking a task in Read mode edits the line (`data-line`). Typing `[[` shows title suggestions above the editor.
- Tree clicks, drags (`{kind: "note"}`) and drops are delegated on `document`, because the tree is redrawn often.
- **Edit is live Markdown** (`makeLiveEditor`, section `live Markdown`). It's a contenteditable div with one `.lv-line`
  per line. Each line keeps all of its raw characters (symbols are `.lv-mark`, hidden with font-size 0 except on
  `.lv-line.active`), and widgets (pictures, task boxes via `::before`) add no text, so `absPos` / `pointAt` map character
  positions both ways. The browser does plain typing and IME composition (redrawn on `compositionend`). Enter, joining
  lines, deleting a selection, paste/cut/copy (plain text only) and undo/redo (its own history) go through the text
  model in `beforeinput`/`keydown`, and the box is redrawn from the text. It mimics a textarea (`value`,
  `selectionStart`, `setSelectionRange`, `lvReplace`), so `edReplace`, `wireEditorKeys`, the `[[` suggestions and
  `putImage` work on both. `currentEditor` holds the open one. Side by side still uses the plain textarea.
- `ensureHabitNotes()` (on every Notes render) gives each habit a note `hn-<habitId>` in its folder. The fixed id means
  both devices make the same note, so a sync doesn't duplicate it. `habitName` tracks renames, and `habit.noHabitNote`
  stops it coming back after the user deletes it.
- To-dos: notes write `[[todo:<id>|text]]` (`todoRefText`). `mdInline` draws it as `todoChipHtml`, and the live editor as
  `.lv-todo`, a text-free widget whose label is in `data-label`, so positions still map. Canvases use cards
  `{type: "todo", todo}`. `todoRefs(id)` (cached per tick) finds the notes and canvases that mention a to-do, and
  `buildTodoRow` adds `.todo-note-link`.
- Phone: the list fills the screen (`.main.notes-page` hides the page title), and the open note replaces it. Opening a note
  pushes `{hbNote: 1}`, so Android's back returns to the list; so do swiping right on the note (not on a canvas) and the Notes tab.
- **Obsidian** (section `notes <-> Obsidian`, options in the Export & import dialog `#obsSection`, and `#notesIoBtn` in the
  Notes list's footer). Export: one `.md` per note, one `.canvas` (JSON Canvas) per canvas, folders like the tree, pictures in
  `attachments/` under their own ids (so `![[img-….jpg]]` works in Obsidian unchanged), as a `.zip` (`obsZip`, stored, no
  compression) or, on the PC, straight into `<picked>/Heat-Bits notes` (`/api/vault/out` + `/api/vault/write`). Import: a vault
  folder (PC: native picker → `/api/vault/read` lists it, `/api/vault/file` serves files from that folder only; browser:
  `webkitdirectory`), a `.zip` (`obsUnzip`, deflate via `DecompressionStream`) or loose `.md`/`.canvas` files. Everything goes
  into one new top folder; dot folders (`.obsidian`, `.trash`) are skipped, links/pictures are resolved the way Obsidian does
  (next to the note, from the top, then by name), and only the pictures the notes show are added (`addImageFile`).
- Sorting (`notesUi.sort`, per device): name, name-desc, updated, created, manual. Manual uses a synced `order` on notes and
  user folders. A before/after drop in the list calls `freezeManualOrder()` first, so the order on screen becomes everyone's `order`.
- Canvases are notes with `kind: "canvas"`, `cards` `[{id, type: "text"|"note", x, y, w, h, text, note, color}]` and `edges`
  `[{id, from, to}]`. Both are lists of `{id}` maps, so `merge3` merges them card by card. Pan and zoom are per device
  (`notesUi.canvasView`). `renderCanvasPane()` runs its own pointer handling (move, resize, connect, pan, pinch), not `hbPointerDrag`.
  It marks the board `.busy` while dragging, and `hbBusy()` waits for that. `noteSearchText()` covers text cards for search, links and renames.

### Alarms and notifications
- Data: any habit/activity/to-do/reminder can have `alert: {before (min), kind: "notify"|"alarm", where: "both"|"pc"|"phone"}`.
  Standalone alarms are `state.alarms`: `{id, label, time, days (empty = once on date), date, kind, where, on}`. Both sync as normal data.
- The page decides *what* rings: `alertList()` (section `alarms and notifications` in index.html) builds this device's alerts for the
  next 14 days (`alertHere()` filters by `where` using `HB.role`). `hbQueueAlerts()` runs after every `saveState()`, after
  `hbApplyRemote`, on start, every 30 min and when the page becomes visible, and POSTs `/api/alerts` only when the list changed.
  Each alert has a stable `key`; `alerts.dart` hashes it to the notification id.
- The app decides *how*: `zonedSchedule` with UTC times (no time zone database needed). Alerts that already went off are never
  cancelled, so a ringing alarm survives a reschedule. Android alarms use the alarm audio stream, FLAG_INSISTENT, full-screen
  intent and Snooze/Stop actions. Windows alarms use `scenario="alarm"` with a looping sound.
- Windows: the plugin only registers its toast activator while the app runs. `alerts.dart` also writes
  `HKCU\Software\Classes\CLSID\{guid}\LocalServer32` = the exe, so a toast button can start the app after it was closed.
  Windows drops every *scheduled* toast from an app that has never shown one immediately ("A local notification failed
  to be submitted to threadpool: Element not found" in the `Microsoft-Windows-PushNotification-Platform/Operational` event
  log), and Heat-Bits only schedules. So `_registerWindowsToasts()` shows one silent toast (SuppressPopup, tag `register`,
  group `hb`) and removes it, whenever `HKCU\…\Notifications\Settings\com.heatbits.HeatBits` is missing. That event log is
  the place to look when toasts don't show.
  Unpackaged apps can't read toast history, but scheduled toasts can be listed/cancelled
  (`ToastNotificationManager::CreateToastNotifier('com.heatbits.HeatBits').GetScheduledToastNotifications()` in PowerShell).
- The phone only learns about alarms set on the PC when it syncs (app open), and alerts are scheduled 14 days ahead.

### Tray and the quick-note hotkey (Windows)
- `tool/windows/hb_desktop.cpp` is the real source (the generated runner only gets a copy). Edit it there, then re-run `prepare.dart`.
  Keep it ASCII: MSVC reads the file as ANSI, so write the escape (backslash-u00B7), not the character itself.
- The X (WM_CLOSE) hides the window while `closeToTray` is on and the tray icon exists. It minimizes before
  `SW_HIDE`, because WebView2's own invisible input popup (`Chrome_WidgetWin_1` "Heat-Bits", in msedgewebview2.exe)
  follows only the window's position, so a plain hide leaves it over the desktop catching clicks. **Quit** in the tray menu sends the
  normal close (`close` → Dart flushes → `destroy`). Clicking the icon shows the window. `TaskbarCreated` re-adds the icon.
- One copy at a time: `main.cpp` holds the mutex `HeatBits.Running`. A second launch posts `HeatBits.Show` to the first
  window (found by class + title "Heat-Bits") and quits.
- `RegisterHotKey` Ctrl+Shift+Q (`globalHotkey`). It takes the key from every program, Heat-Bits included, so when Heat-Bits
  is the foreground window the runner sends `hotkey` and `main.dart` calls `window.__hbQuickNote()` (the page's own quick note).
  Otherwise it opens the popup (a plain Win32 window with two EDIT controls, topmost, centred on the pointer's screen).
  Enter in the note sends `quickNote` {title, body}, and `__hbQuickNote(title, body)` adds the note to `quick` without
  opening it. That works with the window hidden, because the web view stays alive.
- The page sends `/api/desktop` {closeToTray, hotkey, colours, font} (`hbSendDesktop`, after `saveState` and `applySettings`,
  only when it changed). `ui_server.dart` passes it to the runner as `settings`. Web fonts that Windows lacks fall back to Segoe UI.

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

### Sounds
Section `sounds` in index.html: soft tones made with Web Audio (no sound files), switched in Settings → Sound
(`sound`, `soundVolume`, `soundPitchValue`, `soundTaps`, per device). Data sounds (complete, tracker, goal, perfect day, to-do, paid, undo)
are found in `saveState()` by `soundCheck()`, which compares a snapshot (`soundSnap()`) before and after. So a new
place that ticks something needs no extra call, as long as it calls `saveState()`. `hbApplyRemote` refreshes the snapshot
silently, so synced changes make no sound. Never play sounds from `render*`. Taps come from one capture-phase click
listener and are skipped when the same click already made a sound; drags play `pick`/`drop` in `hbPointerDrag()`
and `gridPointerDrag()`. A reminder due today chimes once a day (`soundDueDay`), after the first tap.

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
  Habits (2×2 grid icon), Notes, and ⋯ More (`#bnavMore`: Graphs, Settings). The Habits tab opens `#habitSheetBackdrop`, a bottom sheet of
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
- VS Build Tools need the **C++ ATL** component (`Microsoft.VisualStudio.Component.VC.ATL`, installed 2026-10-16):
  `flutter_local_notifications_windows` includes `atlbase.h`.
- A fresh `build/` folder needs `C:\src\nuget` on PATH: the WebView plugin downloads its NuGet packages, and without
  it CMake caches `NUGET-NOTFOUND` and keeps failing until `build/windows` is deleted.
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
