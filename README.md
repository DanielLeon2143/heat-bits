# Heat-Bits

**Habit heat maps, a calendar and to-dos for Windows and Android, kept in sync over your home Wi-Fi.**

No account, no cloud, no subscription. Your data lives on your own PC and phone, and they talk to each other
directly on your network.

**[⬇ Download the latest version](https://github.com/DanielLeon2143/heat-bits/releases/latest)**:
`Heat-Bits-Windows.zip` for the PC, `Heat-Bits.apk` for an Android phone.

---

## What it does

- **Habits with heat maps.** Track yes/no habits ("Went for a run") or measurable ones ("Pages read: 30").
  Every day fills in a square, so your streaks and gaps show at a glance.
- **Calendar.** Week and month views with an hour grid. Put habits, activities and reminders on it, and drag
  them around.
- **To-dos.** A task list next to your week, so today's plans and today's habits are in one place.
- **Trackers and graphs.** See how each habit is going over weeks and months.
- **Reminders** for things that come back regularly, like bills or appointments.
- **Make it yours.** Themes, colours, fonts and layout, set separately on each device.
- **Backups.** Export everything to a file and import it again whenever you like.

## How the sync works

- The **PC** keeps the main copy. The **phone** pairs with it once by scanning a QR code.
- After that, tick a habit on either one and it shows up on the other within a second or two.
- The phone works offline too. Changes are kept and sent the next time it's on the same Wi-Fi as the PC.
- Edits made on both at once are merged item by item, so nothing gets overwritten.
- Habits, to-dos, activities and reminders sync. Settings (theme, font, layout) stay separate on each device.
- Nothing leaves your home network. There's no server on the internet.

---

## Get started

### 1. Install on the PC (Windows 10 or 11)

1. Download **`Heat-Bits-Windows.zip`** from the [latest release](https://github.com/DanielLeon2143/heat-bits/releases/latest).
2. Unzip it somewhere you'll keep it (for example `Documents\Heat-Bits`) and run **`heat_bits.exe`**.
   Keep the whole folder together.
3. The first time, Windows asks whether to let it use the network. Tick **Private networks** and click
   **Allow**. That's how the phone reaches the PC.

### 2. Install on the phone (Android)

1. On the PC, open **Settings → Devices & sync**. Under the pairing code there's a second QR code,
   **Get the Android app**.
2. Scan it with the phone's camera. It downloads **`Heat-Bits.apk`**.
3. Open the download and tap **Install**. The first time, Android asks you to allow installing apps from your
   browser. Allow it.

(Or open the [latest release](https://github.com/DanielLeon2143/heat-bits/releases/latest) on the phone and tap `Heat-Bits.apk`.)

### 3. Pair the phone (one time)

1. Make sure the phone is on the **same Wi-Fi** as the PC.
2. On the phone, open Heat-Bits, go to **Settings → Devices & sync** and tap **Scan QR code** (allow the camera).
3. Point it at the pairing code on the PC screen.

That's it. The habits from both are put together, and from then on both stay in sync. If both have a habit with
the same name, the phone asks which one to keep, or lets you keep both and rename one. No camera? Type the PC
address and the 6-letter code shown under the QR code instead.

After pairing:
- The phone finds the PC again by itself, even if the PC's address changes.
- **Settings → Devices & sync** shows whether they're connected, has a **Sync now** button, and lets you
  remove a phone (on the PC) or unpair (on the phone).
- Heat-Bits has to be open on the PC for syncing to happen. Close it any time. The phone catches up later.

### Updating

Download the newest release and replace the old files on the PC. On the phone, install the new
`Heat-Bits.apk`. If Android says **"App not installed"**, uninstall the old version first, then install the
new one and pair again. Your data comes back from the PC.

### Coming from the old Heat-Bits desktop app?

1. In the **old** app: sidebar → **Export / import** → **Full backup (JSON)**.
2. In the **new** app on the PC: sidebar → **Export / import** → **Import from a file** → pick that backup →
   **Replace my data** (or **Merge** if you've already added things).
3. Pair the phone afterwards (or press **Sync now**). The phone gets everything.

---

## If something doesn't work

- **The phone says it can't find the PC.** Both must be on the same Wi-Fi. A guest network usually won't work,
  because it stops devices from seeing each other. Heat-Bits must be open on the PC. If you clicked **Cancel**
  on the Windows network prompt, go to Windows Security → Firewall & network protection → Allow an app
  through firewall, and tick **heat_bits** for Private.
- **"That code doesn't match."** The code changes when someone presses **New code** on the PC. Scan again.
- **The phone shows "removed this phone".** It was removed on the PC. Pair again.
- **The Windows app opens to a blank window.** Heat-Bits uses Microsoft's WebView2, which comes with
  Windows 10 and 11. If it's missing, install the "Evergreen Bootstrapper" from
  https://developer.microsoft.com/microsoft-edge/webview2/.
- **Is it syncing?** The line at the bottom of the PC's sidebar says how many phones are connected. On the
  phone, Settings → Devices & sync says when it last synced.

---

## For developers

Heat-Bits is one [Flutter](https://flutter.dev) app for Windows and Android. All the screens are a single web
page (`assets/web/index.html`, plain JavaScript) shown in a web view. The Dart code adds file storage and
the Wi-Fi sync.

| File | What it does |
|---|---|
| `assets/web/index.html` | The whole interface (also runs on its own in a browser, using `localStorage`) |
| `lib/main.dart` | Starts everything and shows the page in a web view |
| `lib/app_controller.dart` | Passes data between the page, the file on disk and the other device |
| `lib/ui_server.dart` | Serves the page to the web view (this device only, `127.0.0.1:47813`) |
| `lib/sync_host.dart` | PC: pairing, sync server (`47811` TCP), discovery replies (`47812` UDP) |
| `lib/sync_client.dart` | Phone: finds the PC, keeps a live connection, syncs, works offline |
| `lib/merge.dart` | The three-way merge that keeps edits from both devices |
| `lib/store.dart` | Saves everything to one JSON file in the app's data folder |
| `tool/prepare.dart` | Patches the generated `android/` and `windows/` folders (permissions, app name, fixes) |

### Building

The `android/` and `windows/` folders are generated, not stored in the repo. Create them once:

```
flutter create --platforms=windows,android --org com.heatbits --project-name heat_bits .
dart run tool/prepare.dart
flutter pub get
```

- Run: `flutter run -d windows`, or `flutter run -d <your phone>` with USB debugging on
- Tests: `flutter test`
- Release build of both: `powershell -ExecutionPolicy Bypass -File build.ps1`

You need Flutter, Visual Studio with **Desktop development with C++** for Windows, and the Android SDK with
JDK 17 for the phone app.

Every push to `main` is built by GitHub Actions (`.github/workflows/build.yml`), which runs the tests and
publishes a new release with the APK and the Windows zip.
