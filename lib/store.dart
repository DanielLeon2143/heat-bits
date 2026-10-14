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
class Store {
  Store._(this.file);

  final File file;
  Map<String, dynamic> local = {};
  Map<String, dynamic>? base;
  int version = 0;
  Map<String, dynamic> meta = {};

  Timer? _timer;
  bool _writing = false, _again = false;

  static Future<Store> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final s = Store._(File('${dir.path}${Platform.pathSeparator}heatbits.json'));
    try {
      if (await s.file.exists()) {
        final j = asMap(jsonDecode(await s.file.readAsString()));
        s.local = asMap(j['local']);
        s.base = j['base'] is Map ? asMap(j['base']) : null;
        s.version = (j['version'] as num?)?.toInt() ?? 0;
        s.meta = asMap(j['meta']);
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

String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
