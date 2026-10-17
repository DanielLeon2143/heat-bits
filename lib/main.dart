import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_controller.dart';
import 'store.dart';

/// Heat-Bits for Windows and Android.
///
/// The interface is the same Heat-Bits page as the web version
/// (assets/web/index.html). This app adds what a web page can't do:
/// it keeps the data in a file, and keeps the PC and the phone in sync
/// over the local Wi-Fi (the PC runs a small server, the phone connects to it).
final navKey = GlobalKey<NavigatorState>();

/// Build with `--dart-define=HB_DEVTOOLS=true` to inspect the page on Windows
/// (Edge/Chrome DevTools protocol at http://127.0.0.1:9222). Off in normal builds.
const _devTools = bool.fromEnvironment('HB_DEVTOOLS');
WebViewEnvironment? _webEnv;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_devTools && Platform.isWindows) {
    _webEnv = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(additionalBrowserArguments: '--remote-debugging-port=9222'));
  }
  final store = await Store.open();
  final app = AppController(store: store, isHost: !Platform.isAndroid, navKey: navKey);
  await app.start();
  app.alerts.onAlarmOpened = (id, payload) => _showAlarm(app, id, payload);
  runApp(HeatBitsApp(app: app));
  // opened by an alert (a ringing alarm on a locked phone, or Snooze on the PC)
  WidgetsBinding.instance.addPostFrameCallback((_) => app.alerts.handleLaunch());
}

bool _alarmShowing = false;

void _showAlarm(AppController app, int id, Map<String, dynamic> payload) {
  final nav = navKey.currentState;
  if (nav == null || _alarmShowing) return;
  _alarmShowing = true;
  nav
      .push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AlarmScreen(
          title: (payload['t'] ?? 'Alarm').toString(),
          body: (payload['b'] ?? '').toString(),
          onStop: () => app.alerts.stop(id),
          onSnooze: () async {
            await app.alerts.stop(id);
            await app.alerts.snooze(payload);
          },
        ),
      ))
      .whenComplete(() => _alarmShowing = false);
}

/// Shown over everything while an alarm rings on the phone.
class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key, required this.title, required this.body, required this.onStop, required this.onSnooze});

  final String title, body;
  final Future<void> Function() onStop, onSnooze;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now().format(context);
    Future<void> act(Future<void> Function() f) async {
      await f();
      if (context.mounted) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: false, // back doesn't silence it: Stop or Snooze does
      child: Scaffold(
        backgroundColor: const Color(0xFF14161C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                Text(now, style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w300)),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(onPressed: () => act(onStop), child: const Text('Stop', style: TextStyle(fontSize: 18))),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => act(onSnooze),
                    child: const Text('Snooze 10 min', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HeatBitsApp extends StatelessWidget {
  const HeatBitsApp({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Heat-Bits',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF4C68D6)),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF4C68D6)),
      home: WebHome(app: app),
    );
  }
}

class WebHome extends StatefulWidget {
  const WebHome({super.key, required this.app});

  final AppController app;

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> with WidgetsBindingObserver {
  InAppWebViewController? _web;
  bool _closing = false;

  /// The Windows runner hands the window close to us first (tool/prepare.dart), and sends
  /// the quick notes made with Ctrl+Shift+Q (tool/windows/hb_desktop.cpp).
  static const _window = MethodChannel('heatbits/window');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      _window.setMethodCallHandler((call) async {
        if (call.method == 'close') await _close();
        if (call.method == 'hotkey') await _quickNote(null, null);
        if (call.method == 'folderPicked') widget.app.folderPicked(call.arguments?.toString());
        if (call.method == 'quickNote') {
          final a = call.arguments is Map ? call.arguments as Map : const {};
          await _quickNote((a['title'] ?? '').toString(), (a['body'] ?? '').toString());
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.app.syncNow(); // phone back in the foreground: catch up
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      widget.app.store.saveNow();
    }
  }

  /// Ctrl+Shift+Q: inside the app (title null) the page opens a new quick note; from the
  /// popup the note is saved straight away, even with the window hidden in the tray.
  Future<void> _quickNote(String? title, String? body) async {
    try {
      await _web?.callAsyncJavaScript(
        functionBody: 'if (window.__hbQuickNote) window.__hbQuickNote(title, body); if (window.__hbFlush) await window.__hbFlush();',
        arguments: {'title': title, 'body': body},
      );
    } catch (_) {}
  }

  /// The window is closing (PC). Collect the page's last edit and save, then take
  /// the web view down before the window goes: closing with it still up crashes.
  Future<void> _close() async {
    if (_closing) return;
    try {
      await _web
          ?.callAsyncJavaScript(functionBody: 'if (window.__hbFlush) await window.__hbFlush();')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (mounted) setState(() => _closing = true);
    await WidgetsBinding.instance.endOfFrame;
    await widget.app.stop();
    await _window.invokeMethod<void>('destroy');
  }

  @override
  Widget build(BuildContext context) {
    if (_closing) return const Scaffold();
    final url = 'http://127.0.0.1:${widget.app.ui.port}/';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        // Android back button: step back inside the page if it can, otherwise leave the app
        if (didPop) return;
        final web = _web;
        if (web != null && await web.canGoBack()) {
          await web.goBack();
        } else {
          await widget.app.store.saveNow();
          if (Platform.isAndroid) exit(0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: InAppWebView(
            webViewEnvironment: _webEnv,
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              supportZoom: false,
              useHybridComposition: true,
              transparentBackground: false,
              allowFileAccess: false,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (c) => _web = c,
            // the page's links (e.g. help) open in the normal browser, not inside the app
            shouldOverrideUrlLoading: (controller, action) async {
              final u = action.request.url;
              if (u == null) return NavigationActionPolicy.ALLOW;
              if (u.host == '127.0.0.1' || u.scheme == 'about' || u.scheme == 'data' || u.scheme == 'blob') {
                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.CANCEL;
            },
            onReceivedError: (controller, request, error) {
              // the local server isn't up yet (very first frame): try again
              if (request.isForMainFrame ?? false) {
                Future.delayed(const Duration(milliseconds: 400), () => controller.reload());
              }
            },
          ),
        ),
      ),
    );
  }
}
