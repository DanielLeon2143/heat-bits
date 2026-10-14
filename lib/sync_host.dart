import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_controller.dart';
import 'merge.dart';
import 'net_util.dart';
import 'qr_svg.dart';
import 'store.dart';

/// Runs on the PC. Phones on the same Wi-Fi pair with it and sync through it.
///
///   GET  /hb/hello   who are you? (no key needed; lets a phone confirm it found the right PC)
///   POST /hb/pair    {code, deviceId, deviceName} -> {token, serverId, serverName}
///   POST /hb/sync    {first, base, doc} -> {doc, version}       (needs the token)
///   GET  /hb/ws      WebSocket: the PC says "changed" so phones sync right away
///   UDP  47812       answers `HEATBITS_DISCOVER <id>` so a phone can find the PC after its IP changes
class SyncHost {
  SyncHost(this.app);

  final AppController app;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  final Map<WebSocket, String> _sockets = {};
  List<String> addresses = [];
  String? error;
  Timer? _addrTimer;

  Store get _store => app.store;
  String get serverId => (_store.meta['serverId'] ??= randomHex(8)) as String;
  String get code => (_store.meta['pairCode'] ??= _newCode()) as String;
  int get port => _server?.port ?? syncPort;

  Map<String, dynamic> get _devices {
    final d = _store.meta['devices'];
    if (d is Map<String, dynamic>) return d;
    final m = asMap(d);
    _store.meta['devices'] = m;
    return m;
  }

  static String _newCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O or 1/I/L mix-ups
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> start() async {
    serverId; // make sure we have one
    code;
    addresses = await localAddresses();
    _addrTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = await localAddresses();
      if (now.join(',') != addresses.join(',')) {
        addresses = now;
        app.notifyStatus();
      }
    });
    try {
      // first time this runs, Windows asks whether to allow it on the network: choose "Allow"
      _server = await HttpServer.bind(InternetAddress.anyIPv4, syncPort);
      _server!.listen((req) {
        _handle(req).catchError((Object _) {
          try {
            req.response.statusCode = 500;
            req.response.close();
          } catch (_) {}
        });
      });
    } catch (e) {
      error = 'Phone sync is off: port $syncPort is already in use (is Heat-Bits already open?).';
    }
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
      _udp = udp;
      udp.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null) return;
        final msg = utf8.decode(d.data, allowMalformed: true).trim();
        if (msg.startsWith('HEATBITS_DISCOVER')) {
          final parts = msg.split(' ');
          if (parts.length < 2 || parts[1] == serverId) {
            try {
              udp.send(utf8.encode('HEATBITS_HERE $serverId $port'), d.address, d.port);
            } catch (_) {}
          }
        }
      });
    } catch (_) {
      // discovery is a convenience; the saved address and the QR still work
    }
  }

  Future<void> stop() async {
    _addrTimer?.cancel();
    for (final ws in List.of(_sockets.keys)) {
      await ws.close();
    }
    _udp?.close();
    await _server?.close(force: true);
  }

  String pairUri() {
    final q = {
      'h': addresses.join(','),
      'p': '$port',
      'c': code,
      'id': serverId,
      'n': app.deviceName,
    };
    return 'heatbits://pair?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  String qrSvgText() => qrSvg(pairUri());

  void newCode() {
    _store.meta['pairCode'] = _newCode();
    _store.scheduleSave();
    app.notifyStatus();
  }

  void removeDevice(String id) {
    _devices.remove(id);
    _store.scheduleSave();
    for (final e in List.of(_sockets.entries)) {
      if (e.value == id) e.key.close();
    }
    app.notifyStatus();
  }

  List<Map<String, dynamic>> deviceList() => _devices.entries.map((e) {
        final d = asMap(e.value);
        return {
          'id': e.key,
          'name': d['name'] ?? 'Phone',
          'lastSeen': d['lastSeen'],
          'connected': _sockets.values.contains(e.key),
        };
      }).toList();

  /// Tells every connected phone that the PC's data changed.
  void notifyChanged() {
    final msg = jsonEncode({'type': 'changed', 'version': _store.version});
    for (final ws in List.of(_sockets.keys)) {
      try {
        ws.add(msg);
      } catch (_) {}
    }
  }

  String? _deviceFor(HttpRequest req) {
    final auth = req.headers.value('authorization') ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7) : (req.uri.queryParameters['token'] ?? '');
    if (token.isEmpty) return null;
    for (final e in _devices.entries) {
      if (asMap(e.value)['token'] == token) return e.key;
    }
    return null;
  }

  void _seen(String id) {
    // a removed phone's socket closes after it's gone: don't bring it back
    if (!_devices.containsKey(id)) return;
    final d = asMap(_devices[id]);
    d['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
    _devices[id] = d;
    _store.scheduleSave();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;

    if (path == '/hb/hello') {
      await sendJson(req, {'app': 'heat-bits', 'id': serverId, 'name': app.deviceName});
      return;
    }

    if (path == '/hb/pair' && req.method == 'POST') {
      final j = asMap(jsonDecode(await readBody(req)));
      final given = (j['code'] ?? '').toString().trim().toUpperCase();
      if (given != code) {
        await sendJson(req, {'error': 'wrong code'}, status: 403);
        return;
      }
      final id = (j['deviceId'] ?? randomHex(8)).toString();
      final token = randomHex(24);
      _devices[id] = {
        'name': (j['deviceName'] ?? 'Phone').toString(),
        'token': token,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      };
      await _store.saveNow();
      app.notifyStatus();
      await sendJson(req, {'token': token, 'serverId': serverId, 'serverName': app.deviceName, 'port': port});
      return;
    }

    final device = _deviceFor(req);
    if (device == null) {
      await sendJson(req, {'error': 'not paired'}, status: 401);
      return;
    }

    if (path == '/hb/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.pingInterval = const Duration(seconds: 15);
      _sockets[ws] = device;
      _seen(device);
      app.notifyStatus();
      ws.listen((_) {}, onDone: () {
        _sockets.remove(ws);
        _seen(device);
        app.notifyStatus();
      }, onError: (Object _) {
        _sockets.remove(ws);
        app.notifyStatus();
      }, cancelOnError: true);
      return;
    }

    if (path == '/hb/sync' && req.method == 'POST') {
      final j = asMap(jsonDecode(await readBody(req)));
      final clientDoc = syncPart(asMap(j['doc']));
      final serverDoc = syncPart(app.store.local);
      Map<String, dynamic> merged;
      if (j['first'] == true) {
        // a newly paired phone takes the PC's habits (unless the PC has none yet)
        merged = hasContent(serverDoc) ? serverDoc : clientDoc;
      } else {
        merged = asMap(merge3(j['base'], serverDoc, clientDoc, preferB: true));
      }
      if (!deepEq(merged, serverDoc)) app.applyNetworkData(merged);
      _seen(device);
      await sendJson(req, {'doc': merged, 'version': _store.version});
      return;
    }

    await sendJson(req, {'error': 'not found'}, status: 404);
  }
}
