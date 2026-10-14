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

  final rc = File('windows/runner/Runner.rc');
  if (rc.existsSync()) {
    var r = rc.readAsStringSync();
    r = r.replaceAll('"FileDescription", "heat_bits"', '"FileDescription", "Heat-Bits"');
    r = r.replaceAll('"ProductName", "heat_bits"', '"ProductName", "Heat-Bits"');
    rc.writeAsStringSync(r);
  }
}
