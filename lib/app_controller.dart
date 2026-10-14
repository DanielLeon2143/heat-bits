import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  Future<void> start() async {
    _revData[uiRev] = syncPart(store.local);
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
    await store.saveNow();
    await host?.stop();
    await client?.stop();
    await ui.stop();
  }

  // ---------------- data from the page ----------------

  void onPageSave(Map<String, dynamic> state, int? rev) {
    final current = syncPart(store.local);
    var incoming = syncPart(state);
    final stale = rev != null && rev != uiRev;
    if (stale && _revData.containsKey(rev)) {
      // the page hadn't applied the latest synced data yet: keep both
      incoming = asMap(merge3(_revData[rev], current, incoming, preferB: true));
    }
    final changed = !deepEq(incoming, current);
    store.local = {...state, ...incoming};
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

  // ---------------- data from the other device ----------------

  void applyNetworkData(Map<String, dynamic> part) {
    store.local = {...store.local, ...part};
    if (isHost) {
      store.version++;
      host?.notifyChanged();
    }
    store.scheduleSave();
    _pushToPage();
  }

  void _pushToPage() {
    uiRev++;
    _revData[uiRev] = syncPart(store.local);
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

  Future<String> exportFile(String name, String text) async {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$safe');
      await f.writeAsString(text);
      await Share.shareXFiles([XFile(f.path)], subject: safe);
      return safe;
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$safe');
    await f.writeAsString(text);
    return f.path;
  }
}
