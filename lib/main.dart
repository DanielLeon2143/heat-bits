import 'dart:io';

import 'package:flutter/material.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  final app = AppController(store: store, isHost: !Platform.isAndroid, navKey: navKey);
  await app.start();
  runApp(HeatBitsApp(app: app));
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  Widget build(BuildContext context) {
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
