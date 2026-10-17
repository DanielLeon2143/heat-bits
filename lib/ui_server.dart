import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart' show MethodChannel, rootBundle;

import 'app_controller.dart';
import 'merge.dart';
import 'net_util.dart';
import 'qr_svg.dart';
import 'store.dart';

/// Serves the Heat-Bits interface to the app's own web view, on 127.0.0.1 only.
///
///   GET  /                 the page, with the saved data injected (window.__HB_BOOT_STATE__)
///   GET  /api/events       live updates for the page (server-sent events: "state", "status")
///   POST /api/save         the page saved its data
///   GET  /api/sync/status  pairing / connection status for Settings → Devices & sync
///   POST /api/sync/resolve the user's picks for same-named habits before the first sync
///   POST /api/alerts       the alarms/notifications this device should schedule (see alerts.dart)
///   POST /api/desktop      PC: tray, global quick-note hotkey and the popup's colours (tool/windows/hb_desktop.cpp)
///   POST /api/files?id=…   a picture for a note or canvas (raw bytes); `GET /files/ID?k=…` shows it
///   /api/data/*            Settings → Data & storage: info, pick, check, move, open
///   /api/vault/*           notes <-> Obsidian on the PC: read a picked vault, write into a picked folder
///   ...and the pairing buttons in that card (see _api below)
///
/// Every /api call must carry the per-launch key, so other programs on the
/// computer can't read or change the data through this port.
class UiServer {
  UiServer(this.app);

  final AppController app;
  final String key = randomHex(16);
  late HttpServer _server;
  final List<HttpResponse> _streams = [];
  String _html = '<!doctype html><title>Heat-Bits</title>';
  Timer? _keepAlive;

  int get port => _server.port;

  Future<void> start() async {
    _html = await rootBundle.loadString('assets/web/index.html');
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, uiPort);
    } catch (_) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // port taken: any free one
    }
    _server.listen((req) {
      _handle(req).catchError((Object _) {
        try {
          req.response.statusCode = 500;
          req.response.close();
        } catch (_) {}
      });
    });
    _keepAlive = Timer.periodic(const Duration(seconds: 20), (_) => _sendRaw(': ping\n\n'));
  }

  Future<void> stop() async {
    _keepAlive?.cancel();
    for (final r in List.of(_streams)) {
      try {
        await r.close();
      } catch (_) {}
    }
    await _server.close(force: true);
  }

  /// Sends new data to the page (it swaps in the synced parts and redraws).
  void sendState(int rev, Map<String, dynamic> state) => _send('state', {'rev': rev, 'state': state});

  void sendStatus(Map<String, dynamic> status) => _send('status', status);

  /// New pictures are on this device (they came from the other one).
  void sendFiles() => _send('files', {'at': DateTime.now().millisecondsSinceEpoch});

  void _send(String event, Object data) => _sendRaw('event: $event\ndata: ${jsonEncode(data)}\n\n');

  void _sendRaw(String msg) {
    for (final r in List.of(_streams)) {
      try {
        r.write(msg);
      } catch (_) {
        _streams.remove(r);
      }
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
      await _page(req);
      return;
    }
    if (path.startsWith('/api/') || path.startsWith('/files/')) {
      final k = req.headers.value('x-hb-key') ?? req.uri.queryParameters['k'];
      if (k != key) {
        await sendJson(req, {'error': 'forbidden'}, status: 403);
        return;
      }
      if (path.startsWith('/files/')) {
        // a picture in a note or canvas (<img src="/files/<id>?k=…">)
        await app.files.serve(req, Uri.decodeComponent(path.substring(7)));
        return;
      }
      await _api(req, path);
      return;
    }
    req.response.statusCode = 404;
    await req.response.close();
  }

  Future<void> _page(HttpRequest req) async {
    final boot = {
      'key': key,
      'role': app.isHost ? 'host' : 'client',
      'platform': Platform.operatingSystem,
      'rev': app.uiRev,
    };
    String js(Object? o) => jsonEncode(o).replaceAll('</', '<\\/');
    final state = app.store.local.isEmpty ? null : app.store.local;
    final script = '<script>window.__HB_HOST__=${js(boot)};window.__HB_BOOT_STATE__=${js(state)};</script>';
    final html = _html.replaceFirst('<!--HB_BOOT-->', script);
    final res = req.response;
    res.headers.contentType = ContentType.html;
    res.headers.set('cache-control', 'no-store');
    res.add(utf8.encode(html));
    await res.close();
  }

  Future<void> _api(HttpRequest req, String path) async {
    Future<Map<String, dynamic>> readJson() async {
      try {
        return asMap(jsonDecode(await readBody(req)));
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    switch (path) {
      case '/api/files':
        {
          // a picture added to a note or canvas: the raw image is the body, its name is ?id=
          final id = req.uri.queryParameters['id'] ?? '';
          final ok = req.method == 'POST' && await app.files.save(id, req);
          await sendJson(req, ok ? {'ok': true} : {'ok': false, 'error': "Couldn't save that picture."}, status: ok ? 200 : 400);
          return;
        }
      case '/api/events':
        {
          final res = req.response;
          res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
          res.headers.set('cache-control', 'no-cache');
          res.bufferOutput = false;
          res.write(': connected\n\n');
          _streams.add(res);
          res.done.catchError((_) {}).whenComplete(() => _streams.remove(res));
          return; // keep the stream open
        }
      case '/api/save':
        {
          final j = await readJson();
          final state = j['state'];
          if (state is Map) app.onPageSave(asMap(state), (j['rev'] as num?)?.toInt());
          await sendJson(req, {'ok': true});
          return;
        }
      case '/api/sync/status':
        await sendJson(req, app.status());
        return;
      case '/api/sync/now':
        await app.syncNow();
        await sendJson(req, {'ok': true});
        return;
      case '/api/pair/qr.svg':
        {
          final res = req.response;
          res.headers.contentType = ContentType('image', 'svg+xml', charset: 'utf-8');
          res.headers.set('cache-control', 'no-store');
          res.add(utf8.encode(app.host?.qrSvgText() ?? '<svg xmlns="http://www.w3.org/2000/svg"/>'));
          await res.close();
          return;
        }
      case '/api/download/qr.svg':
        {
          final res = req.response;
          res.headers.contentType = ContentType('image', 'svg+xml', charset: 'utf-8');
          res.add(utf8.encode(qrSvg(androidDownloadUrl)));
          await res.close();
          return;
        }
      case '/api/pair/newcode':
        app.host?.newCode();
        await sendJson(req, {'ok': true});
        return;
      case '/api/devices/remove':
        {
          final j = await readJson();
          app.host?.removeDevice((j['id'] ?? '').toString());
          await sendJson(req, {'ok': true});
          return;
        }
      case '/api/pair/scan':
        unawaited(app.scanAndPair());
        await sendJson(req, {'ok': true});
        return;
      case '/api/pair/connect':
        {
          final j = await readJson();
          final err = await app.client?.pairManual((j['host'] ?? '').toString(), (j['code'] ?? '').toString());
          await sendJson(req, {'ok': err == null, if (err != null) 'error': err});
          return;
        }
      case '/api/sync/resolve':
        {
          final j = await readJson();
          await app.client?.resolve(j['choices'] is List ? j['choices'] as List : const []);
          await sendJson(req, {'ok': true});
          return;
        }
      case '/api/sync/notes':
        {
          // the user's picks for notes changed differently on both devices
          final j = await readJson();
          await app.client?.resolveNotes(j['choices'] is List ? j['choices'] as List : const []);
          await sendJson(req, {'ok': true});
          return;
        }
      case '/api/pair/forget':
        await app.client?.unpair();
        await sendJson(req, {'ok': true});
        return;
      case '/api/alerts':
        {
          // this device's alarms and notifications for the next two weeks, worked out by the page
          final j = await readJson();
          await sendJson(req, await app.alerts.apply(j['alerts'] is List ? j['alerts'] as List : const []));
          return;
        }
      case '/api/desktop':
        {
          final j = await readJson();
          if (Platform.isWindows) {
            try {
              await const MethodChannel('heatbits/window').invokeMethod<void>('settings', j);
            } catch (_) {}
          }
          await sendJson(req, {'ok': true});
          return;
        }
      case '/api/alerts/test':
        {
          final j = await readJson();
          await app.alerts.test((j['kind'] ?? 'notify').toString());
          await sendJson(req, {'ok': true});
          return;
        }
      // Settings → Data & storage: where the data file and pictures are, and moving them (PC only)
      case '/api/data/info':
        await sendJson(req, await app.dataInfo());
        return;
      case '/api/data/pick':
        {
          final path = await app.pickFolder();
          await sendJson(req, path == null ? {'ok': false} : {'ok': true, 'path': path});
          return;
        }
      case '/api/data/check':
        {
          final j = await readJson();
          await sendJson(req, await app.checkFolder((j['path'] ?? '').toString()));
          return;
        }
      case '/api/data/move':
        {
          final j = await readJson();
          await sendJson(req, await app.moveData((j['path'] ?? '').toString(), (j['mode'] ?? 'move').toString()));
          return;
        }
      case '/api/data/open':
        await app.openDataFolder();
        await sendJson(req, {'ok': true});
        return;
      // notes <-> Obsidian: the page converts, the app reads the picked vault / writes the picked folder (PC)
      case '/api/vault/read':
        await sendJson(req, await app.pickVaultToRead());
        return;
      case '/api/vault/file':
        {
          final f = app.vaultFile(req.uri.queryParameters['path'] ?? '');
          final res = req.response;
          if (f == null || !await f.exists()) {
            res.statusCode = 404;
            await res.close();
            return;
          }
          res.headers.contentType = ContentType.binary;
          await res.addStream(f.openRead());
          await res.close();
          return;
        }
      case '/api/vault/out':
        await sendJson(req, await app.pickVaultToWrite());
        return;
      case '/api/vault/write':
        {
          final q = req.uri.queryParameters;
          final ok = req.method == 'POST' && await app.writeVaultFile(q['path'] ?? '', req, int.tryParse(q['modified'] ?? ''));
          await sendJson(req, {'ok': ok});
          return;
        }
      case '/api/export/bytes':
        {
          // an export that isn't text (the notes .zip): the raw file is the body, its name is ?name=
          try {
            final b = BytesBuilder(copy: false);
            await for (final chunk in req) {
              b.add(chunk);
            }
            final where = await app.exportBytes(req.uri.queryParameters['name'] ?? 'heat-bits.zip', b.takeBytes());
            await sendJson(req, {'ok': true, 'path': where});
          } catch (e) {
            await sendJson(req, {'ok': false, 'error': e.toString()});
          }
          return;
        }
      case '/api/export':
        {
          final j = await readJson();
          try {
            final where = await app.exportFile((j['filename'] ?? 'heat-bits.txt').toString(), (j['text'] ?? '').toString());
            await sendJson(req, {'ok': true, 'path': where});
          } catch (e) {
            await sendJson(req, {'ok': false, 'error': e.toString()});
          }
          return;
        }
    }
    await sendJson(req, {'error': 'not found'}, status: 404);
  }
}
