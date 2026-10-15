import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_controller.dart';
import 'merge.dart';
import 'net_util.dart';

/// Runs on the phone. Finds the paired PC on the Wi-Fi, keeps a live
/// connection to it, and syncs whenever either side changes something.
/// Works offline too: edits are kept and sent the next time the PC is reachable.
class SyncClient {
  SyncClient(this.app);

  final AppController app;
  String? _host;
  WebSocket? _ws;
  Timer? _debounce, _retry;
  bool _syncing = false, _again = false, _connecting = false;
  int _backoff = 5;

  bool connected = false;
  String? error;
  int? lastSync;

  /// Habits with the same name on the phone and the PC, found before the first
  /// sync. Nothing merges until the user picks or renames (see [resolve]).
  List<Map<String, dynamic>>? conflicts;

  Map<String, dynamic>? get _pair => app.store.meta['pair'] is Map ? asMap(app.store.meta['pair']) : null;
  bool get paired => _pair != null;
  String? get peerName => _pair?['serverName']?.toString();

  Future<void> start() async {
    lastSync = (app.store.meta['lastSync'] as num?)?.toInt();
    if (paired) unawaited(connect());
  }

  Future<void> stop() async {
    _retry?.cancel();
    _debounce?.cancel();
    await _ws?.close();
  }

  // ---------------- pairing ----------------

  /// From the QR code: heatbits://pair?h=ip1,ip2&p=47811&c=CODE&id=…&n=PC%20name
  Future<String?> pairFromUri(String text) async {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'heatbits') return "That isn't a Heat-Bits pairing code.";
    final q = uri.queryParameters;
    final hosts = (q['h'] ?? '').split(',').where((h) => h.trim().isNotEmpty).toList();
    final port = int.tryParse(q['p'] ?? '') ?? syncPort;
    return _pairWith(hosts, port, q['c'] ?? '');
  }

  /// From the form in Settings: the PC's address and the code shown next to the QR.
  Future<String?> pairManual(String hostText, String code) async {
    var host = hostText.trim();
    var port = syncPort;
    final m = RegExp(r'^(.+):(\d+)$').firstMatch(host);
    if (m != null) {
      host = m.group(1)!;
      port = int.parse(m.group(2)!);
    }
    return _pairWith([host], port, code);
  }

  Future<String?> _pairWith(List<String> hosts, int port, String code) async {
    if (hosts.isEmpty) return 'No PC address in that code. Make sure the PC is on Wi-Fi.';
    String? lastError;
    for (final h in hosts) {
      try {
        final r = await httpJson('POST', h, port, '/hb/pair',
            body: {'code': code.trim().toUpperCase(), 'deviceId': app.store.meta['deviceId'], 'deviceName': app.deviceName},
            timeout: const Duration(seconds: 6));
        app.store.meta['pair'] = {
          'serverId': r['serverId'],
          'serverName': r['serverName'],
          'token': r['token'],
          'port': (r['port'] as num?)?.toInt() ?? port,
          'hosts': hosts,
          'lastHost': h,
        };
        app.store.base = null; // first sync: merge what's on both
        app.store.meta.remove('firstDrop');
        conflicts = null;
        await app.store.saveNow();
        error = null;
        _backoff = 5;
        await connect();
        return null;
      } on HttpFail catch (e) {
        lastError = e.status == 403
            ? "That code doesn't match. Check the code shown on your PC (it changes if you press New code)."
            : 'Your PC answered with an error (${e.status}).';
        if (e.status == 403) break;
      } catch (_) {
        lastError = "Couldn't reach your PC at $h. Check that both are on the same Wi-Fi and Heat-Bits is open on the PC.";
      }
    }
    error = lastError;
    app.notifyStatus();
    return lastError;
  }

  Future<void> unpair() async {
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    app.store.meta.remove('pair');
    app.store.meta.remove('firstDrop');
    app.store.base = null;
    conflicts = null;
    connected = false;
    error = null;
    _host = null;
    await app.store.saveNow();
    await ws?.close();
    app.notifyStatus();
  }

  // ---------------- connecting ----------------

  Future<void> connect() async {
    if (!paired || _connecting) return;
    _connecting = true;
    _retry?.cancel();
    try {
      final h = await _findHost();
      if (h == null) {
        connected = false;
        error = "Can't find ${peerName ?? 'your PC'} on this Wi-Fi. Is Heat-Bits open on it?";
        _scheduleRetry();
        return;
      }
      _host = h;
      final p = _pair!;
      if (p['lastHost'] != h) {
        p['lastHost'] = h;
        app.store.meta['pair'] = p;
        app.store.scheduleSave();
      }
      await sync();
      if (_host != null && _ws == null) await _openSocket();
    } finally {
      _connecting = false;
      app.notifyStatus();
    }
  }

  Future<String?> _findHost() async {
    final p = _pair;
    if (p == null) return null;
    final port = (p['port'] as num?)?.toInt() ?? syncPort;
    final candidates = <String>{
      if (p['lastHost'] != null) p['lastHost'].toString(),
      ...((p['hosts'] as List?) ?? const []).map((e) => e.toString()),
    };
    for (final h in candidates) {
      if (await _isOurPc(h, port)) return h;
    }
    // the PC's address changed (new router lease, other network card…): ask around
    final found = await discoverHost((p['serverId'] ?? '').toString());
    if (found != null && await _isOurPc(found, port)) return found;
    return null;
  }

  Future<bool> _isOurPc(String host, int port) async {
    try {
      final r = await httpJson('GET', host, port, '/hb/hello', timeout: const Duration(seconds: 2));
      return r['app'] == 'heat-bits' && r['id'] == _pair?['serverId'];
    } catch (_) {
      return false;
    }
  }

  Future<void> _openSocket() async {
    final p = _pair;
    if (p == null || _host == null) return;
    final port = (p['port'] as num?)?.toInt() ?? syncPort;
    try {
      final ws = await WebSocket.connect('ws://$_host:$port/hb/ws?token=${Uri.encodeQueryComponent(p['token'].toString())}')
          .timeout(const Duration(seconds: 5));
      ws.pingInterval = const Duration(seconds: 15);
      _ws = ws;
      connected = true;
      _backoff = 5;
      app.notifyStatus();
      ws.listen((m) {
        try {
          final j = jsonDecode(m as String);
          if (j is Map && j['type'] == 'changed') unawaited(sync());
        } catch (_) {}
      }, onDone: () => _socketClosed(ws), onError: (Object _) => _socketClosed(ws), cancelOnError: true);
    } catch (_) {
      _socketClosed(null);
    }
  }

  void _socketClosed(WebSocket? ws) {
    if (ws != null && !identical(ws, _ws)) return;
    _ws = null;
    if (!paired) return;
    connected = false;
    app.notifyStatus();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), () => connect());
    _backoff = min(_backoff * 2, 60);
  }

  /// Called when the app comes back to the foreground.
  Future<void> wake() async {
    if (!paired) return;
    if (_ws == null) {
      _backoff = 5;
      await connect();
    } else {
      await sync();
    }
  }

  // ---------------- syncing ----------------

  /// The page saved a change: send it shortly (edits made in quick succession go together).
  void localChanged() {
    if (!paired) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (_host == null) {
        unawaited(connect());
      } else {
        unawaited(sync());
      }
    });
  }

  Future<void> sync() async {
    final p = _pair;
    if (p == null || _host == null) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    final port = (p['port'] as num?)?.toInt() ?? syncPort;
    try {
      do {
        _again = false;
        final first = app.store.base == null;
        final drop = _firstDrop;
        if (first) {
          // look at the PC's habits first: same-named ones need the user to decide
          final peek = await httpJson('POST', _host!, port, '/hb/sync',
              body: {'peek': true}, token: p['token'].toString(), timeout: const Duration(seconds: 15));
          final clashes = habitNameClashes(syncPart(app.store.local), syncPart(asMap(peek['doc'])), skipPc: drop);
          conflicts = clashes.isEmpty ? null : clashes;
          if (conflicts != null) {
            error = null;
            connected = true;
            return;
          }
        }
        final sent = syncPart(app.store.local);
        final r = await httpJson('POST', _host!, port, '/hb/sync',
            body: {'first': first, if (first) 'drop': drop, 'base': app.store.base ?? <String, dynamic>{}, 'doc': sent},
            token: p['token'].toString(),
            timeout: const Duration(seconds: 15));
        final merged = syncPart(asMap(r['doc']));
        app.store.base = merged;
        if (first) app.store.meta.remove('firstDrop');
        // edits made on the phone while that request was in flight are layered on top
        final current = syncPart(app.store.local);
        final next = deepEq(current, sent) ? merged : asMap(merge3(sent, merged, current, preferB: true));
        if (!deepEq(next, current)) app.applyNetworkData(next);
        if (!deepEq(next, merged)) _again = true; // still something the PC hasn't got
        lastSync = DateTime.now().millisecondsSinceEpoch;
        app.store.meta['lastSync'] = lastSync;
        app.store.scheduleSave();
        error = null;
        connected = true;
      } while (_again);
    } on HttpFail catch (e) {
      if (e.status == 401) {
        error = '${peerName ?? 'Your PC'} removed this phone. Pair again from Settings.';
        await unpair();
        error = '${peerName ?? 'Your PC'} removed this phone. Pair again to keep syncing.';
      } else {
        error = 'Sync failed (${e.status}). Trying again soon.';
        _dropConnection();
      }
    } catch (_) {
      _dropConnection();
    } finally {
      _syncing = false;
      app.notifyStatus();
    }
  }

  List<String> get _firstDrop =>
      app.store.meta['firstDrop'] is List ? (app.store.meta['firstDrop'] as List).map((e) => e.toString()).toList() : <String>[];

  /// The user's answers for [conflicts]: keep the PC's habit, keep the phone's,
  /// or keep both with the phone's one renamed. Then the first sync goes ahead.
  Future<void> resolve(List choices) async {
    final habits = ((app.store.local['habits'] as List?) ?? const []).toList();
    final drop = _firstDrop;
    for (final c in choices.whereType<Map>()) {
      final phoneId = c['phoneId']?.toString(), pcId = c['pcId']?.toString();
      final i = habits.indexWhere((h) => h is Map && h['id']?.toString() == phoneId);
      switch (c['keep']) {
        case 'pc':
          if (i != -1) habits.removeAt(i);
        case 'phone':
          if (pcId != null && !drop.contains(pcId)) drop.add(pcId);
        case 'both':
          final name = (c['name'] ?? '').toString().trim();
          if (i != -1 && name.isNotEmpty) habits[i] = {...asMap(habits[i]), 'name': name};
      }
    }
    app.store.meta['firstDrop'] = drop;
    conflicts = null;
    app.applyNetworkData({...syncPart(app.store.local), 'habits': habits});
    await app.store.saveNow();
    app.notifyStatus();
    await wake();
  }

  void _dropConnection() {
    _host = null;
    connected = false;
    final ws = _ws;
    _ws = null;
    ws?.close();
    _scheduleRetry();
  }

  Map<String, dynamic> status() => {
        'paired': paired,
        'peerName': peerName,
        'connected': connected,
        'lastSync': lastSync,
        'error': error,
        'conflicts': conflicts,
      };
}
