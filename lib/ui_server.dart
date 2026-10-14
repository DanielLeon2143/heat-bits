import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'app_controller.dart';
import 'merge.dart';
import 'net_util.dart';
import 'store.dart';

/// Serves the Heat-Bits interface to the app's own web view, on 127.0.0.1 only.
///
///   GET  /                 the page, with the saved data injected (window.__HB_BOOT_STATE__)
///   GET  /api/events       live updates for the page (server-sent events: "state", "status")
///   POST /api/save         the page saved its data
///   GET  /api/sync/status  pairing / connection status for Settings → Devices & sync
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
    if (path.startsWith('/api/')) {
      final k = req.headers.value('x-hb-key') ?? req.uri.queryParameters['k'];
      if (k != key) {
        await sendJson(req, {'error': 'forbidden'}, status: 403);
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
      case '/api/pair/forget':
        await app.client?.unpair();
        await sendJson(req, {'ok': true});
        return;
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
