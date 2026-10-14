# Heat-Bits for Windows + Android

One codebase for both: the Heat-Bits interface (`assets/web/index.html`, the same page as the web version)
inside a small Flutter app that adds file storage and **two-way sync over your home Wi-Fi**.

- The **PC** keeps the main copy and runs a tiny sync server on your network.
- The **phone** pairs with the PC once (scan a QR code), then stays in sync: tick a habit on either one and it
  shows up on the other within a second or two.
- The phone works offline too. Changes are kept and sent the next time it's on the same Wi-Fi as the PC.
- Edits on both at once are merged item by item, so nothing gets overwritten. Habits, to-dos, activities and
  reminders sync; settings (theme, font, layout) stay separate on each device.

---

## 1. Get the apps (easiest: let GitHub build them)

You don't need to install anything for this.

1. Create a free account at [github.com](https://github.com) if you don't have one.
2. Click **New repository**, name it `heat-bits`, choose **Private**, and create it.
3. On the new repository page, click **uploading an existing file**, drag in **everything inside this folder**
   (including the hidden `.github` folder, see the tip below), and click **Commit changes**.
4. Open the **Actions** tab. A build called **Build Heat-Bits** starts by itself (takes about 10–15 minutes).
5. When it has a green tick, open it and scroll to **Artifacts**:
   - **Heat-Bits-Windows** → unzip, then run `heat_bits.exe` (keep the whole folder together).
   - **Heat-Bits-Android** → unzip to get `Heat-Bits.apk`; copy it to your phone and open it.
     Android asks to allow installing from this source the first time; allow it.

> **Tip: the `.github` folder.** Windows hides folders starting with a dot in some upload dialogs. If the
> Actions tab says there are no workflows, click **Add file → Create new file**, type
> `.github/workflows/build.yml` as the name, and paste in the contents of that file from this folder.

Every time you upload a change, GitHub builds new versions. Use **Actions → Build Heat-Bits → Run workflow**
to build again without changing anything.

## 2. Pair your phone (one time)

1. Open Heat-Bits on the **PC**. The first time, Windows asks whether to let it use the network. Tick
   **Private networks** and click **Allow**. This is how the phone reaches it.
2. On the PC, go to **Settings → Devices & sync**. You'll see a QR code.
3. Make sure the phone is on the **same Wi-Fi** as the PC.
4. Open Heat-Bits on the **phone**, go to **Settings → Devices & sync**, and tap **Scan QR code**
   (allow the camera). Point it at the code on the PC screen.

That's it. The PC's habits appear on the phone, and from then on both stay in sync. No camera? Type the PC
address and the 6-letter code shown under the QR code instead.

After pairing:
- The phone finds the PC again by itself, even if the PC's address changes.
- **Settings → Devices & sync** shows whether they're connected, has a **Sync now** button, and lets you remove a phone
  (on the PC) or unpair (on the phone).
- The PC has to be on, with Heat-Bits open, for syncing to happen. Close it any time; the phone catches up later.

## 3. Moving your data from the old Heat-Bits desktop app

The new app keeps its data in its own place. To bring your history across:

1. In the **old** app: sidebar → **Export / import** → **Full backup (JSON)**.
2. In the **new** app on the PC: sidebar → **Export / import** → **Import from a file** → pick that backup →
   **Replace my data** (or **Merge** if you've already added things).
3. Pair the phone afterwards (or press **Sync now**). The phone gets everything.

---

## Build on your own PC (optional)

If you'd rather not use GitHub:

1. Install Flutter for Windows: https://docs.flutter.dev/get-started/install/windows/desktop
   (includes Visual Studio with **Desktop development with C++**).
2. For the phone app, also install Android Studio: https://developer.android.com/studio,
   then run `flutter doctor --android-licenses` and accept.
3. In this folder, run:
   ```
   powershell -ExecutionPolicy Bypass -File build.ps1
   ```
   It builds `build\windows\x64\runner\Release\heat_bits.exe` and `Heat-Bits.apk`.

To try it straight from the source while editing: `flutter run -d windows`, or with the phone plugged in (USB
debugging on) `flutter run -d <your phone>`. (Run `flutter create --platforms=android,windows .` and
`dart run tool/prepare.dart` once first. `build.ps1` does that for you.)

## Changing the app

All the screens are in **`assets/web/index.html`**. It's the same file as the web version, so a change
there shows up on Windows and Android after the next build. The Dart code in `lib/` only handles storage and syncing:

| File | What it does |
|---|---|
| `lib/main.dart` | Starts everything and shows the page in a web view |
| `lib/app_controller.dart` | Passes data between the page, the file on disk and the other device |
| `lib/ui_server.dart` | Serves the page to the web view (this device only, `127.0.0.1:47813`) |
| `lib/sync_host.dart` | PC: pairing, sync server (`47811`), "where are you?" replies (`47812` UDP) |
| `lib/sync_client.dart` | Phone: finds the PC, keeps a live connection, syncs, works offline |
| `lib/merge.dart` | The three-way merge that keeps edits from both devices |
| `lib/store.dart` | Saves everything to one JSON file in the app's data folder |
| `tool/prepare.dart` | Adds Android permissions (network, camera) and the app name after `flutter create` |

## If something doesn't work

- **Phone says it can't find the PC.** Both must be on the same Wi-Fi (not a guest network, which usually blocks
  devices from seeing each other). Heat-Bits must be open on the PC. If you clicked **Cancel** on the Windows
  network prompt: Windows Security → Firewall & network protection → Allow an app through firewall → tick
  **heat_bits** for Private.
- **"That code doesn't match."** The code changes if someone pressed **New code** on the PC. Scan again.
- **Phone shows "removed this phone".** It was removed on the PC. Pair again.
- **The Windows app opens to a blank window.** It uses Microsoft's WebView2, which comes with Windows 10 and 11.
  If it's missing, install the "Evergreen Bootstrapper" from https://developer.microsoft.com/microsoft-edge/webview2/.
- **Dragging on the phone.** Moving and stretching boxes on the week calendar works with a mouse on the PC. On the
  phone, use taps (double-tap a box to edit it).
- **Sync status at a glance:** the line at the bottom of the PC's sidebar says how many phones are connected.
  On the phone, Settings → Devices & sync says when it last synced.
