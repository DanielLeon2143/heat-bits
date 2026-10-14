// Run once after `flutter create` has generated the android/ and windows/ folders:
//   dart run tool/prepare.dart
// It adds the permissions and settings Heat-Bits needs, and sets the app's name.
// Safe to run again: it only changes what isn't already there.
import 'dart:io';

void main() {
  _android();
  _windows();
  stdout.writeln('Heat-Bits platform files are ready.');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stdout.writeln('(no android folder, skipping)');
    return;
  }
  var s = f.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
    'android.permission.CHANGE_WIFI_MULTICAST_STATE',
    'android.permission.CAMERA',
  ];
  final missing = perms.where((p) => !s.contains('"$p"')).map((p) => '    <uses-permission android:name="$p"/>\n').join();
  if (missing.isNotEmpty) s = s.replaceFirst('<application', '$missing    <application');
  // the app talks plain HTTP to itself (127.0.0.1) and to the PC on the home network
  if (!s.contains('usesCleartextTraffic')) {
    s = s.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Heat-Bits"');
  if (!s.contains('android.hardware.camera')) {
    s = s.replaceFirst('<application', '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application');
  }
  f.writeAsStringSync(s);

  // the scanner and web view need Android 5.0+ (API 21); keep at least that
  for (final name in ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
    final g = File(name);
    if (!g.existsSync()) continue;
    var t = g.readAsStringSync();
    t = t.replaceAllMapped(RegExp(r'minSdk(Version)?\s*=?\s*(\d+)'), (m) {
      final v = int.parse(m.group(2)!);
      return v < 21 ? m.group(0)!.replaceFirst(m.group(2)!, '21') : m.group(0)!;
    });
    g.writeAsStringSync(t);
  }
}

void _windows() {
  final main = File('windows/runner/main.cpp');
  if (!main.existsSync()) {
    stdout.writeln('(no windows folder, skipping)');
    return;
  }
  var s = main.readAsStringSync();
  s = s.replaceAll('L"heat_bits"', 'L"Heat-Bits"');
  s = s.replaceAll('Win32Window::Size size(1280, 720);', 'Win32Window::Size size(1400, 900);');
  main.writeAsStringSync(s);

  // flutter_inappwebview_windows still uses <experimental/coroutine>, which newer
  // Visual Studio versions (2026+) refuse to compile unless told to allow it
  final cmake = File('windows/CMakeLists.txt');
  if (cmake.existsSync()) {
    var c = cmake.readAsStringSync();
    const flag = '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS';
    if (!c.contains(flag)) {
      c = c.replaceFirst('add_definitions(-DUNICODE -D_UNICODE)', 'add_definitions(-DUNICODE -D_UNICODE -D$flag)');
      cmake.writeAsStringSync(c);
    }
  }

  // closing the window while the web view is still up crashes (flutter_inappwebview_windows),
  // so the close goes to the app first: it saves, takes the web view down, then says "destroy"
  final fw = File('windows/runner/flutter_window.cpp');
  if (fw.existsSync()) {
    var w = fw.readAsStringSync().replaceAll('\r\n', '\n'); // flutter create writes CRLF on Windows
    if (!w.contains('heatbits/window')) {
      w = w.replaceFirst('#include "flutter/generated_plugin_registrant.h"\n', '''#include "flutter/generated_plugin_registrant.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// Heat-Bits: the window close is handed to the app first (see tool/prepare.dart)
static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> hb_window_channel;
static bool hb_close_ready = false;
static const UINT_PTR kHbCloseTimer = 0x4842;
''');
      w = w.replaceFirst('  RegisterPlugins(flutter_controller_->engine());\n', '''  RegisterPlugins(flutter_controller_->engine());
  HWND hb_hwnd = GetHandle();
  hb_window_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "heatbits/window",
      &flutter::StandardMethodCodec::GetInstance());
  hb_window_channel->SetMethodCallHandler([hb_hwnd](const auto& call, auto result) {
    if (call.method_name() == "destroy") {
      hb_close_ready = true;
      PostMessage(hb_hwnd, WM_CLOSE, 0, 0);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
''');
      w = w.replaceFirst('void FlutterWindow::OnDestroy() {\n', 'void FlutterWindow::OnDestroy() {\n  hb_window_channel = nullptr;\n');
      w = w.replaceFirst('  // Give Flutter, including plugins, an opportunity to handle window messages.\n', '''  if (message == WM_CLOSE && !hb_close_ready && hb_window_channel) {
    hb_window_channel->InvokeMethod("close", nullptr);
    SetTimer(hwnd, kHbCloseTimer, 5000, nullptr);  // no answer in 5 s: close anyway
    return 0;
  }
  if (message == WM_TIMER && wparam == kHbCloseTimer) {
    KillTimer(hwnd, kHbCloseTimer);
    hb_close_ready = true;
    PostMessage(hwnd, WM_CLOSE, 0, 0);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
''');
      fw.writeAsStringSync(w);
    }
  }

  final rc = File('windows/runner/Runner.rc');
  if (rc.existsSync()) {
    var r = rc.readAsStringSync();
    r = r.replaceAll('"FileDescription", "heat_bits"', '"FileDescription", "Heat-Bits"');
    r = r.replaceAll('"ProductName", "heat_bits"', '"ProductName", "Heat-Bits"');
    rc.writeAsStringSync(r);
  }
}
