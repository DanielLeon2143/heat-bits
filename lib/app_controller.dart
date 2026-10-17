import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'alerts.dart';
import 'files.dart';
import 'merge.dart';
import 'net_util.dart';
import 'scan_screen.dart';
import 'store.dart';
import 'sync_client.dart';
import 'sync_host.dart';
import 'ui_server.dart';

/// Ties the pieces together:
///   page (web view) <-> UiServer <-> AppController <-> SyncHost (PC) / SyncClient (phone)
///
/// "rev" keeps the page and the app in step: every time the app sends the page
/// new data it bumps uiRev, and the page sends back the rev it last saw with each
/// save. If the page saved before it had applied the newest data, its edits are
/// merged on top instead of overwriting what just arrived.
class AppController {
  AppController({required this.store, required this.isHost, required this.navKey});

  final Store store;
  final bool isHost;
  final GlobalKey<NavigatorState> navKey;

  late final UiServer ui = UiServer(this);
  late final Alerts alerts = Alerts(store);
  late Attachments files;
  SyncHost? host;
  SyncClient? client;

  int uiRev = 0;
  final Map<int, Map<String, dynamic>> _revData = {};

  String get deviceName {
    if (Platform.isAndroid) return 'Android phone';
    try {
      final n = Platform.localHostname;
      if (n.isNotEmpty) return n;
    } catch (_) {}
    return 'PC';
  }

  /// What the page and the app keep in step: the synced data plus the settings that can sync.
  static Map<String, dynamic> _pagePart(Map<String, dynamic> state) => {...syncPart(state), '_prefs': sharedPrefs(state)};

  Future<void> start() async {
    files = await Attachments.open(store.file.parent);
    await cleanUpPictures(); // also catches up after Android simply killed the app
    _revData[uiRev] = _pagePart(store.local);
    await alerts.init();
    await ui.start();
    if (isHost) {
      host = SyncHost(this);
      await host!.start();
    } else {
      client = SyncClient(this);
      await client!.start();
    }
  }

  Future<void> stop() async {
    await cleanUpPictures();
    await store.saveNow();
    await host?.stop();
    await client?.stop();
    await ui.stop();
  }

  // ---------------- data from the page ----------------

  void onPageSave(Map<String, dynamic> state, int? rev) {
    final current = _pagePart(store.local);
    var incoming = _pagePart(state);
    final stale = rev != null && rev != uiRev;
    if (stale && _revData.containsKey(rev)) {
      // the page hadn't applied the latest synced data yet: keep both
      incoming = asMap(merge3(_revData[rev], current, incoming, preferB: true));
    }
    // turning "Sync settings" on or off counts as a change, so the other device catches up
    final changed = !deepEq(incoming, current) || syncsSettings(state) != syncsSettings(store.local);
    final data = Map<String, dynamic>.of(incoming)..remove('_prefs');
    store.local = withSharedPrefs({...state, ...data}, asMap(incoming['_prefs']));
    store.scheduleSave();
    if (stale) {
      if (changed) _pushToPage();
    } else {
      _revData[uiRev] = incoming;
    }
    if (!changed) return;
    if (isHost) {
      store.version++;
      host?.notifyChanged();
    } else {
      client?.localChanged();
    }
  }

  /// Deletes the pictures that were taken out of every note and canvas, and drops them from
  /// state.files so the other device doesn't send them back. Runs when the app closes and starts,
  /// never while the page is open (a picture is uploaded a moment before the note that uses it is saved).
  Future<void> cleanUpPictures() async {
    try {
      final unused = unusedFileIds(store.local, await files.list());
      if (unused.isEmpty) return;
      for (final id in unused) {
        try {
          final f = files.file(id);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      final list = store.local['files'];
      if (list is List) {
        final kept = list.where((f) => !unused.contains(asMap(f)['id']?.toString())).toList();
        if (kept.length != list.length) {
          store.local = {...store.local, 'files': kept};
          if (isHost) {
            store.version++;
          } else {
            client?.localChanged();
          }
        }
      }
      store.scheduleSave();
    } catch (_) {
      // best effort: the next start tries again
    }
  }

  // ---------------- data from the other device ----------------

  /// [prefs]: settings from the other device (only while "Sync settings" is on).
  void applyNetworkData(Map<String, dynamic> part, {Map<String, dynamic>? prefs}) {
    store.local = {...store.local, ...part};
    if (prefs != null) store.local = withSharedPrefs(store.local, prefs);
    if (isHost) {
      store.version++;
      host?.notifyChanged();
    }
    store.scheduleSave();
    _pushToPage();
  }

  void _pushToPage() {
    uiRev++;
    _revData[uiRev] = _pagePart(store.local);
    _revData.removeWhere((k, _) => k < uiRev - 40);
    ui.sendState(uiRev, store.local);
  }

  // ---------------- status + actions for Settings → Devices & sync ----------------

  Map<String, dynamic> status() => {
        'role': isHost ? 'host' : 'client',
        'deviceName': deviceName,
        if (host != null) ...{
          'code': host!.code,
          'addresses': host!.addresses,
          'port': host!.port,
          'devices': host!.deviceList(),
          'error': host!.error,
          'downloadUrl': androidDownloadUrl,
        },
        if (client != null) ...client!.status(),
      };

  void notifyStatus() => ui.sendStatus(status());

  /// Pictures arrived from the other device: the page shows the ones it was waiting for.
  void filesArrived() => ui.sendFiles();

  Future<void> syncNow() async {
    if (client != null) await client!.wake();
  }

  Future<void> scanAndPair() async {
    final nav = navKey.currentState;
    if (nav == null || client == null) return;
    final result = await nav.push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (result == null) return;
    await client!.pairFromUri(result);
    notifyStatus();
  }

  // ---------------- Settings → Data & storage ----------------

  /// Moving the folder is PC only: on Android, dart:io can only write inside the app's own storage.
  bool get canMoveData => Platform.isWindows;

  static Map<String, int> _counts(Map<String, dynamic> s) {
    int n(String k) => s[k] is List ? (s[k] as List).length : 0;
    return {
      'habits': n('habits'),
      'notes': n('notes'),
      'todos': n('todos'),
      'activities': n('activities'),
      'reminders': n('payments'),
      'alarms': n('alarms'),
    };
  }

  Future<Map<String, dynamic>> dataInfo() async {
    final def = await Store.defaultDir();
    int? bytes, modified;
    try {
      final st = await store.file.stat();
      if (st.type != FileSystemEntityType.notFound) {
        bytes = st.size;
        modified = st.modified.millisecondsSinceEpoch;
      }
    } catch (_) {}
    final (pics, picBytes) = await files.stats();
    return {
      'folder': store.dir.path,
      'file': store.file.path,
      'attachments': files.dir.path,
      'defaultFolder': def.path,
      'isDefault': samePath(store.dir.path, def.path),
      'canChange': canMoveData,
      'problem': store.folderProblem,
      'bytes': bytes,
      'modified': modified,
      'counts': _counts(store.local),
      'pictures': pics,
      'pictureBytes': picBytes,
    };
  }

  Completer<String?>? _picking;

  /// Windows' own folder picker (tool/windows/hb_desktop.cpp). Null if the user cancelled.
  Future<String?> pickFolder({String? title, String? start}) async {
    if (!canMoveData || _picking != null) return null;
    final c = _picking = Completer<String?>();
    try {
      await const MethodChannel('heatbits/window').invokeMethod<void>('pickFolder', {
        'start': start ?? store.dir.path,
        'title': title ?? 'Choose where Heat-Bits keeps its data',
      });
    } catch (_) {
      if (!c.isCompleted) c.complete(null); // an older runner without the picker
    }
    try {
      return await c.future;
    } finally {
      _picking = null;
    }
  }

  /// The runner's answer to [pickFolder] ('' when cancelled).
  void folderPicked(String? path) {
    final c = _picking;
    if (c != null && !c.isCompleted) c.complete(path == null || path.isEmpty ? null : path);
  }

  /// What's in [path] before moving there: is it usable, and is there Heat-Bits data in it already?
  Future<Map<String, dynamic>> checkFolder(String path) async {
    if (!canMoveData) return {'ok': false, 'error': "The folder can't be changed on this device."};
    if (path.trim().isEmpty) return {'ok': false, 'error': 'Pick a folder first.'};
    final d = Directory(path);
    if (samePath(d.path, store.dir.path)) return {'ok': true, 'same': true, 'path': d.path};
    if (samePath(d.path, files.dir.path) || d.path.toLowerCase().startsWith('${files.dir.path.toLowerCase()}${Platform.pathSeparator}')) {
      return {'ok': false, 'error': "That's the pictures folder. Pick a different folder."};
    }
    if (!await Store.canWrite(d)) {
      return {'ok': false, 'error': "Heat-Bits can't save in that folder. Pick another one, for example one in Documents."};
    }
    final f = Store.fileIn(d);
    if (!await f.exists()) return {'ok': true, 'path': d.path, 'hasData': false};
    try {
      final j = await Store.readFile(f);
      final st = await f.stat();
      return {
        'ok': true,
        'path': d.path,
        'hasData': true,
        'readable': true,
        'counts': _counts(asMap(j['local'])),
        'modified': st.modified.millisecondsSinceEpoch,
      };
    } catch (_) {
      return {'ok': true, 'path': d.path, 'hasData': true, 'readable': false};
    }
  }

  /// Keeps the data in [path] from now on.
  ///   mode "move": copy this device's data there (a heatbits.json already there is kept as .old-<time>)
  ///   mode "use":  load the heatbits.json that's already there instead (the page then reloads)
  /// The old folder keeps its copy, so nothing is lost if the new one goes missing.
  Future<Map<String, dynamic>> moveData(String path, String mode) async {
    final check = await checkFolder(path);
    if (check['ok'] != true) return check;
    if (check['same'] == true) return {'ok': true};
    final d = Directory(check['path'] as String);
    final target = Store.fileIn(d);
    try {
      if (mode == 'use') {
        Map<String, dynamic> data;
        try {
          data = await Store.readFile(target);
        } catch (_) {
          return {'ok': false, 'error': "The Heat-Bits file in that folder can't be read. Choose to replace it instead."};
        }
        final next = await Attachments.open(d);
        await store.switchTo(d, data: data);
        files = next;
        _pushToPage();
        host?.notifyChanged();
        client?.localChanged();
        notifyStatus();
        return {'ok': true, 'reload': true};
      }
      final next = await Attachments.open(d);
      if (!await files.copyTo(next)) {
        return {'ok': false, 'error': "Couldn't copy the pictures there. Is the drive full? Nothing was changed."};
      }
      if (await target.exists()) await target.rename('${target.path}.old-${DateTime.now().millisecondsSinceEpoch}');
      await store.switchTo(d);
      files = next;
      return {'ok': true};
    } catch (_) {
      return {'ok': false, 'error': "Couldn't move the data there. Your data is still in the old folder."};
    }
  }

  Future<void> openDataFolder() async {
    if (!Platform.isWindows) return;
    try {
      await Process.start('explorer.exe', [store.dir.path]);
    } catch (_) {}
  }

  Future<String> exportFile(String name, String text) => exportBytes(name, utf8.encode(text));

  /// Saves an export: Downloads on Windows, the share sheet on Android.
  Future<String> exportBytes(String name, List<int> bytes) async {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$safe');
      await f.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(f.path)], subject: safe);
      return safe;
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$safe');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  // ---------------- notes <-> Obsidian (section "Obsidian" in index.html) ----------------
  // The page does the converting. On the PC the app adds what a page can't: reading a vault folder
  // the user picked, and writing an export straight into a folder. Only ever inside those two folders.

  Directory? _vaultIn, _vaultOut;
  static final _vaultFile = RegExp(r'\.(md|canvas|png|jpe?g|gif|webp)$', caseSensitive: false);

  /// Import: pick a vault and list its notes, canvases and pictures (not .obsidian, .trash or other dot folders).
  Future<Map<String, dynamic>> pickVaultToRead() async {
    final path = await pickFolder(title: 'Choose your Obsidian vault folder', start: _vaultIn?.path ?? '');
    if (path == null) return {'ok': false};
    final root = Directory(path);
    final files = <Map<String, dynamic>>[];
    try {
      await for (final e in root.list(recursive: true, followLinks: false).handleError((Object _) {})) {
        if (e is! File) continue;
        final rel = _relative(root, e.path);
        if (rel == null || rel.split('/').any((s) => s.startsWith('.')) || !_vaultFile.hasMatch(rel)) continue;
        try {
          final st = await e.stat();
          files.add({'path': rel, 'size': st.size, 'modified': st.modified.millisecondsSinceEpoch});
        } catch (_) {}
        if (files.length >= 50000) break;
      }
    } catch (_) {
      return {'ok': false, 'error': "Couldn't read that folder."};
    }
    _vaultIn = root;
    return {'ok': true, 'name': _baseName(root.path), 'files': files};
  }

  /// One file from the vault picked with [pickVaultToRead].
  File? vaultFile(String rel) => _inside(_vaultIn, rel);

  /// Export: pick a folder; the notes go into a "Heat-Bits notes" folder inside it.
  Future<Map<String, dynamic>> pickVaultToWrite() async {
    final path = await pickFolder(title: 'Choose where to save your notes (for example your Obsidian vault)', start: '');
    if (path == null) return {'ok': false};
    final out = Directory('${_trimSep(path)}${Platform.pathSeparator}Heat-Bits notes');
    if (!await Store.canWrite(out)) {
      return {'ok': false, 'error': "Heat-Bits can't save in that folder. Pick another one, for example one in Documents."};
    }
    _vaultOut = out;
    return {'ok': true, 'path': out.path};
  }

  /// Writes one exported file into the folder from [pickVaultToWrite], with the note's own date.
  Future<bool> writeVaultFile(String rel, Stream<List<int>> bytes, int? modified) async {
    final f = _inside(_vaultOut, rel);
    if (f == null) return false;
    try {
      await f.parent.create(recursive: true);
      final sink = f.openWrite();
      await sink.addStream(bytes);
      await sink.close();
      if (modified != null && modified > 0) {
        try {
          await f.setLastModified(DateTime.fromMillisecondsSinceEpoch(modified));
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _trimSep(String p) => p.replaceFirst(RegExp(r'[\\/]+$'), '');

  static String _baseName(String p) {
    final parts = _trimSep(p).split(RegExp(r'[\\/]'));
    return parts.isEmpty || parts.last.isEmpty ? 'Vault' : parts.last;
  }

  static String? _relative(Directory root, String path) {
    final base = _trimSep(root.path);
    if (!path.toLowerCase().startsWith(base.toLowerCase())) return null;
    return path.substring(base.length).replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  /// [rel] inside [root] only: no "..", no drive letters, no absolute paths.
  static File? _inside(Directory? root, String rel) {
    if (root == null) return null;
    final parts = rel.replaceAll(r'\', '/').split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty || parts.any((s) => s == '..' || s == '.' || s.contains(':'))) return null;
    return File([_trimSep(root.path), ...parts].join(Platform.pathSeparator));
  }
}
