import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'merge.dart';

/// Everything the app keeps on disk, in one JSON file:
///   local   – the full Heat-Bits state, exactly as the page saved it
///   base    – (phone) the last data the phone and PC agreed on
///   version – (PC) bumps on every data change so phones know to sync
///   meta    – device id, pairing info, paired phones
///
/// The file lives in the app support dir unless the user picked another folder in
/// Settings → Data & storage. That choice is kept in `data-folder.txt` in the app support dir,
/// because it has to be read before the data file can be found.
///
/// Once a day the file is copied to `backups/heatbits-<date>.json` next to it (the last
/// [keepBackups] days are kept), so a bad sync or a slip can be undone by hand.
class Store {
  Store._(this.file);

  File file;
  Map<String, dynamic> local = {};
  Map<String, dynamic>? base;
  int version = 0;
  Map<String, dynamic> meta = {};

  Timer? _timer;
  bool _writing = false, _again = false;
  String? _backupDay;

  /// Set when the chosen folder couldn't be reached at start (a USB drive that's out, say),
  /// so the data is in the app's own folder for now. Shown in Settings → Data & storage.
  String? folderProblem;

  static const fileName = 'heatbits.json';
  static const keepBackups = 7;

  Directory get dir => file.parent;

  static Future<Directory> defaultDir() => getApplicationSupportDirectory();

  static Future<File> _pointer() async => File('${(await defaultDir()).path}${Platform.pathSeparator}data-folder.txt');

  static File fileIn(Directory d) => File('${d.path}${Platform.pathSeparator}$fileName');

  static Future<Store> open() async {
    final def = await defaultDir();
    await def.create(recursive: true);
    var dir = def;
    String? problem;
    try {
      final p = await _pointer();
      final custom = await p.exists() ? (await p.readAsString()).trim() : '';
      if (custom.isNotEmpty) {
        if (await canWrite(Directory(custom))) {
          dir = Directory(custom);
        } else {
          problem = "Can't reach $custom, so Heat-Bits is using its own folder for now. "
              'Plug in the drive (or check the folder still exists) and restart Heat-Bits.';
        }
      }
    } catch (_) {}
    final s = Store._(fileIn(dir))..folderProblem = problem;
    try {
      if (await s.file.exists()) {
        s._apply(await readFile(s.file));
        await s._backupIfDue(); // only a file that reads fine is worth keeping
      }
    } catch (_) {
      // unreadable file: keep a copy instead of silently losing it
      try {
        await s.file.copy('${s.file.path}.broken-${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
    }
    s.meta['deviceId'] ??= randomHex(12);
    return s;
  }

  void _apply(Map<String, dynamic> j) {
    local = asMap(j['local']);
    base = j['base'] is Map ? asMap(j['base']) : null;
    version = (j['version'] as num?)?.toInt() ?? 0;
    meta = asMap(j['meta']);
  }

  /// Throws if the file isn't Heat-Bits data.
  static Future<Map<String, dynamic>> readFile(File f) async {
    final j = jsonDecode(await f.readAsString());
    if (j is! Map) throw const FormatException('not Heat-Bits data');
    return asMap(j);
  }

  static Future<bool> canWrite(Directory d) async {
    try {
      await d.create(recursive: true);
      final t = File('${d.path}${Platform.pathSeparator}.heatbits-write-test');
      await t.writeAsString('ok', flush: true);
      await t.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// From now on, keep the data in [d]. With [data] (the contents of a heatbits.json already there),
  /// load that instead of this one; this device's pairing and identity ([meta]) stay as they are.
  Future<void> switchTo(Directory d, {Map<String, dynamic>? data}) async {
    await saveNow();
    file = fileIn(d);
    if (data != null) {
      final keepMeta = meta, keepVersion = version;
      _apply(data);
      meta = keepMeta;
      version = (version > keepVersion ? version : keepVersion) + 1; // phones see a change and sync
    }
    folderProblem = null;
    await saveNow();
    final p = await _pointer();
    if (samePath(d.path, (await defaultDir()).path)) {
      if (await p.exists()) await p.delete();
    } else {
      await p.writeAsString(d.path, flush: true);
    }
  }

  Future<void> _backupIfDue() async {
    final now = DateTime.now(), day = dayKey(now);
    if (_backupDay == day) return;
    _backupDay = day;
    await backup(file, now);
  }

  void scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), saveNow);
  }

  Future<void> saveNow() async {
    _timer?.cancel();
    if (_writing) {
      _again = true;
      return;
    }
    _writing = true;
    try {
      // the PC can stay open for days in the tray, so check again on the first save of each day
      await _backupIfDue();
      do {
        _again = false;
        final text = jsonEncode({'local': local, 'base': base, 'version': version, 'meta': meta});
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        try {
          await tmp.rename(file.path);
        } catch (_) {
          if (await file.exists()) await file.delete();
          await tmp.rename(file.path);
        }
      } while (_again);
    } catch (_) {
      // disk full / locked: the next save tries again
    } finally {
      _writing = false;
    }
  }
}

String dayKey(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Copies [f] to `backups/heatbits-<day>.json` next to it, unless today's copy is already
/// there, then deletes all but the newest [keep]. Best effort: a failed backup never stops a save.
Future<void> backup(File f, DateTime now, {int keep = Store.keepBackups}) async {
  try {
    if (!await f.exists()) return;
    final dir = Directory('${f.parent.path}${Platform.pathSeparator}backups');
    await dir.create(recursive: true);
    final today = File('${dir.path}${Platform.pathSeparator}heatbits-${dayKey(now)}.json');
    if (!await today.exists()) await f.copy(today.path);
    final name = RegExp(r'^heatbits-\d{4}-\d{2}-\d{2}\.json$');
    final old = <File>[];
    await for (final e in dir.list()) {
      if (e is File && name.hasMatch(e.uri.pathSegments.last)) old.add(e);
    }
    old.sort((a, b) => b.path.compareTo(a.path)); // the date sorts as text, newest first
    for (final x in old.skip(keep)) {
      try {
        await x.delete();
      } catch (_) {}
    }
  } catch (_) {}
}

/// Same folder, ignoring slash style, a trailing slash and (on Windows) case.
bool samePath(String a, String b) {
  String n(String p) {
    var x = p.replaceAll(r'\', '/');
    while (x.length > 1 && x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return Platform.isWindows ? x.toLowerCase() : x;
  }

  return n(a) == n(b);
}

String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
