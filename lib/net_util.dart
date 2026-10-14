import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ports Heat-Bits uses on the local network.
const int syncPort = 47811; // PC: pairing + sync (HTTP + WebSocket)
const int discoveryPort = 47812; // PC: answers "where are you?" broadcasts (UDP)
const int uiPort = 47813; // both: serves the interface to the app's own web view (localhost only)

/// This device's IPv4 addresses on the local network (Wi-Fi / Ethernet).
Future<List<String>> localAddresses() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>[];
    for (final i in ifs) {
      final name = i.name.toLowerCase();
      // virtual adapters (VPNs, WSL, VirtualBox, Docker) are rarely what the phone can reach
      final virtual = name.contains('vethernet') || name.contains('virtual') || name.contains('vmware') ||
          name.contains('docker') || name.contains('wsl') || name.contains('loopback') ||
          name.contains('vpn') || name.contains('hamachi') || name.contains('zerotier') ||
          name.contains('tailscale') || name.contains('wireguard');
      for (final a in i.addresses) {
        if (a.address.startsWith('169.254.')) continue;
        if (virtual) continue;
        out.add(a.address);
      }
    }
    // prefer the usual home-network ranges first
    out.sort((x, y) => _rank(x).compareTo(_rank(y)));
    return out;
  } catch (_) {
    return [];
  }
}

int _rank(String ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  if (ip.startsWith('172.')) return 2;
  return 3;
}

class HttpFail implements Exception {
  HttpFail(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'HTTP $status';
}

Future<Map<String, dynamic>> httpJson(String method, String host, int port, String path,
    {Map<String, dynamic>? body, String? token, Duration timeout = const Duration(seconds: 8)}) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await c.open(method, host, port, path).timeout(timeout);
    if (token != null) req.headers.set('authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(timeout);
    final text = await utf8.decoder.bind(res).join().timeout(timeout);
    if (res.statusCode != 200) throw HttpFail(res.statusCode, text);
    final j = jsonDecode(text);
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  } finally {
    c.close(force: true);
  }
}

Future<String> readBody(HttpRequest req) => utf8.decoder.bind(req).join();

Future<void> sendJson(HttpRequest req, Object data, {int status = 200}) async {
  final res = req.response;
  res.statusCode = status;
  res.headers.contentType = ContentType.json;
  res.headers.set('cache-control', 'no-store');
  res.add(utf8.encode(jsonEncode(data)));
  await res.close();
}

/// Asks the local network where the PC with [serverId] is. Returns its IP or null.
Future<String?> discoverHost(String serverId) async {
  RawDatagramSocket? s;
  try {
    s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    final found = Completer<String?>();
    final sock = s;
    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = sock.receive();
      if (d == null) return;
      final parts = utf8.decode(d.data, allowMalformed: true).trim().split(' ');
      if (parts.length >= 3 && parts[0] == 'HEATBITS_HERE' && parts[1] == serverId && !found.isCompleted) {
        found.complete(d.address.address);
      }
    });
    final targets = <String>{'255.255.255.255'};
    for (final ip in await localAddresses()) {
      final p = ip.split('.');
      if (p.length == 4) targets.add('${p[0]}.${p[1]}.${p[2]}.255');
    }
    final msg = utf8.encode('HEATBITS_DISCOVER $serverId');
    for (var i = 0; i < 4 && !found.isCompleted; i++) {
      for (final t in targets) {
        try {
          sock.send(msg, InternetAddress(t), discoveryPort);
        } catch (_) {}
      }
      await Future.any([found.future, Future<void>.delayed(const Duration(milliseconds: 600))]);
    }
    return found.isCompleted ? await found.future : null;
  } catch (_) {
    return null;
  } finally {
    s?.close();
  }
}
