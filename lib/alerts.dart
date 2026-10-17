import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'merge.dart';
import 'store.dart';

/// Alarms and notifications, handed to the system's own scheduler so they go off
/// even when Heat-Bits is closed.
///
/// The page works out which alerts belong on this device for the next two weeks
/// and sends them here (POST /api/alerts). Each one has a stable `key`; what's
/// already scheduled is kept in store.meta['alerts'] so only changes are
/// cancelled or added (and an alarm that's ringing right now isn't cut off).
///
///   kind "notify": a normal notification with a sound
///   kind "alarm":  keeps ringing until Stop or Snooze (full screen on the phone)
class Alerts {
  Alerts(this.store);

  final Store store;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void> _queue = Future.value();
  NotificationResponse? _launch;

  /// Shows the alarm screen (set by main.dart). Gets the notification id and its payload.
  void Function(int id, Map<String, dynamic> payload)? onAlarmOpened;

  Future<void> init() async {
    try {
      if (Platform.isWindows) {
        await _registerWindowsLauncher();
        unawaited(_registerWindowsToasts());
      }
      _ready = await _plugin.initialize(
            settings: _initSettings,
            onDidReceiveNotificationResponse: _onResponse,
            onDidReceiveBackgroundNotificationResponse: alertBackgroundResponse,
          ) ??
          false;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) _launch = launch.notificationResponse;
    } catch (_) {
      _ready = false; // no notifications on this device; the rest of the app still works
    }
  }

  /// The app was opened by tapping an alert (or a ringing alarm took over the screen).
  void handleLaunch() {
    final r = _launch;
    _launch = null;
    if (r != null) _onResponse(r);
  }

  /// Replaces what's scheduled with [items] ({key, at, title, body, kind}).
  Future<Map<String, dynamic>> apply(List items) {
    final done = Completer<Map<String, dynamic>>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _apply(items));
      } catch (_) {
        done.complete({'ok': false});
      }
    });
    return done.future;
  }

  Future<Map<String, dynamic>> _apply(List items) async {
    if (!_ready) return {'ok': false, 'error': "Notifications aren't available on this device."};
    final now = DateTime.now().millisecondsSinceEpoch;
    final want = <String, Map<String, dynamic>>{};
    for (final raw in items.take(120)) {
      final a = asMap(raw);
      final key = (a['key'] ?? '').toString();
      final at = (a['at'] as num?)?.toInt() ?? 0;
      if (key.isEmpty || at <= now + 1000) continue;
      want['${_idFor(key)}'] = {
        'at': at,
        'title': (a['title'] ?? 'Heat-Bits').toString(),
        'body': (a['body'] ?? '').toString(),
        'kind': a['kind'] == 'alarm' ? 'alarm' : 'notify',
        'key': key,
      };
    }
    final had = asMap(store.meta['alerts']);
    // a notification that's already gone off is left alone: it may be ringing right now
    for (final id in had.keys) {
      final old = asMap(had[id]);
      final stillPending = ((old['at'] as num?)?.toInt() ?? 0) > now;
      if (stillPending && !deepEq(old, want[id])) await _cancel(int.parse(id));
    }
    if (want.isNotEmpty) await _askPermission(want.values.any((a) => a['kind'] == 'alarm'));
    final exact = await _canBeExact();
    final kept = <String, dynamic>{};
    for (final e in want.entries) {
      final old = had[e.key];
      final pending = old != null && ((asMap(old)['at'] as num?)?.toInt() ?? 0) > now;
      if (!(pending && deepEq(asMap(old), e.value))) {
        if (!await _schedule(int.parse(e.key), e.value, exact)) continue;
      }
      kept[e.key] = e.value;
    }
    store.meta['alerts'] = kept;
    store.scheduleSave();
    return {'ok': true, 'scheduled': kept.length};
  }

  /// "Test" button in Settings: a sample in a few seconds.
  Future<void> test(String kind) async {
    if (!_ready) return;
    await _askPermission(kind == 'alarm');
    final at = DateTime.now().millisecondsSinceEpoch + 5000;
    await _schedule(_idFor('test-$kind'), {
      'at': at,
      'title': kind == 'alarm' ? 'Test alarm' : 'Test notification',
      'body': kind == 'alarm' ? 'Rings until you stop it.' : 'This is how Heat-Bits reminds you.',
      'kind': kind == 'alarm' ? 'alarm' : 'notify',
      'key': 'test-$kind',
    }, await _canBeExact());
  }

  Future<void> stop(int id) => _cancel(id);

  Future<void> snooze(Map<String, dynamic> payload) => snoozeWith(_plugin, payload);

  // ---------------- taps and buttons ----------------

  void _onResponse(NotificationResponse r) {
    final parsed = parseResponse(r);
    if (parsed.action == 'snooze') {
      unawaited(snooze(parsed.payload));
    } else if (parsed.action == 'stop') {
      if (r.id != null) unawaited(_cancel(r.id!));
    } else if (parsed.payload['k'] == 'alarm' && Platform.isAndroid) {
      onAlarmOpened?.call(r.id ?? 0, parsed.payload);
    }
  }

  // ---------------- system calls ----------------

  Future<bool> _schedule(int id, Map<String, dynamic> a, bool exact) =>
      scheduleWith(_plugin, id, a, exact);

  Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  Future<bool> _canBeExact() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _askPermission(bool alarm) async {
    if (!Platform.isAndroid) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      if (!(await android.areNotificationsEnabled() ?? true)) await android.requestNotificationsPermission();
      // Android 14+ may need the user to allow full-screen alarms; ask once, in Settings
      if (alarm && store.meta['askedFullScreen'] != true) {
        store.meta['askedFullScreen'] = true;
        store.scheduleSave();
        await android.requestFullScreenIntentPermission();
      }
    } catch (_) {}
  }

  /// Windows only keeps a toast's buttons working while the app runs. Telling Windows
  /// where the app is lets it start Heat-Bits when Snooze is pressed after it was closed.
  Future<void> _registerWindowsLauncher() async {
    try {
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Classes\\CLSID\\{$_windowsGuid}\\LocalServer32',
        '/ve',
        '/d',
        '"${Platform.resolvedExecutable}"',
        '/f',
      ]);
    } catch (_) {}
  }
}

/// Windows drops every *scheduled* toast from an app it hasn't seen show one straight away
/// ("A local notification failed to be submitted to threadpool: Element not found" in the
/// PushNotification-Platform log), and Heat-Bits only schedules. So when Windows has no entry for
/// the app yet, show one silently (no pop-up, no sound) and take it straight off again.
Future<void> _registerWindowsToasts() async {
  try {
    final known = await Process.run('reg', ['query', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\$_windowsAumid']);
    if (known.exitCode == 0) return;
    const script = '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
\$x = New-Object Windows.Data.Xml.Dom.XmlDocument
\$x.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Heat-Bits</text></binding></visual><audio silent="true"/></toast>')
\$t = New-Object Windows.UI.Notifications.ToastNotification \$x
\$t.SuppressPopup = \$true
\$t.Tag = 'register'
\$t.Group = 'hb'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$_windowsAumid').Show(\$t)
Start-Sleep -Milliseconds 700
[Windows.UI.Notifications.ToastNotificationManager]::History.Remove('register', 'hb', '$_windowsAumid')
''';
    await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script]);
  } catch (_) {}
}

// ---------------- shared with the background handler (Android buttons while the app is closed) ----------------

const _windowsGuid = '8f6b2c1e-4a3d-4e57-9b1a-6c2d3e4f5a61';
const _windowsAumid = 'com.heatbits.HeatBits';
const _snoozeMinutes = 10;

final _initSettings = InitializationSettings(
  android: const AndroidInitializationSettings('@drawable/ic_stat_heatbits'),
  windows: WindowsInitializationSettings(
    appName: 'Heat-Bits',
    appUserModelId: _windowsAumid,
    guid: _windowsGuid,
  ),
);

/// A stable notification id for an alert key (FNV-1a, kept positive for Android).
int _idFor(String key) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(key)) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

class ParsedResponse {
  ParsedResponse(this.action, this.payload);
  final String? action;
  final Map<String, dynamic> payload;
}

/// Android passes the button as actionId; Windows passes the button's arguments
/// as the payload ("snooze:{json}", "stop"), or the toast's own payload for a tap.
ParsedResponse parseResponse(NotificationResponse r) {
  Map<String, dynamic> decode(String? s) {
    try {
      return asMap(jsonDecode(s ?? ''));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  final p = r.payload ?? '';
  if (Platform.isWindows) {
    if (p.startsWith('snooze:')) return ParsedResponse('snooze', decode(p.substring(7)));
    if (p == 'stop') return ParsedResponse('stop', const {});
    return ParsedResponse(null, decode(p));
  }
  final a = r.actionId;
  return ParsedResponse(a == null || a.isEmpty ? null : a, decode(p));
}

Future<void> snoozeWith(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> payload) async {
  final key = '${payload['key'] ?? 'alert'}|snooze';
  await scheduleWith(plugin, _idFor(key), {
    'at': DateTime.now().add(const Duration(minutes: _snoozeMinutes)).millisecondsSinceEpoch,
    'title': (payload['t'] ?? 'Heat-Bits').toString(),
    'body': 'Snoozed: ${(payload['b'] ?? '').toString()}'.trim(),
    'kind': payload['k'] == 'alarm' ? 'alarm' : 'notify',
    'key': key,
  }, true);
}

Future<bool> scheduleWith(FlutterLocalNotificationsPlugin plugin, int id, Map<String, dynamic> a, bool exact) async {
  final alarm = a['kind'] == 'alarm';
  final payload = jsonEncode({'t': a['title'], 'b': a['body'], 'k': a['kind'], 'key': a['key']});
  final when = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, (a['at'] as num).toInt());
  final details = NotificationDetails(
    android: alarm
        ? AndroidNotificationDetails(
            'hb_alarms',
            'Alarms',
            channelDescription: 'Rings until you stop or snooze it',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
            fullScreenIntent: true,
            autoCancel: false,
            ongoing: true,
            visibility: NotificationVisibility.public,
            additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: the sound repeats until it's handled
            actions: const [
              AndroidNotificationAction('snooze', 'Snooze $_snoozeMinutes min', cancelNotification: true),
              AndroidNotificationAction('stop', 'Stop', cancelNotification: true),
            ],
          )
        : const AndroidNotificationDetails(
            'hb_notify',
            'Notifications',
            channelDescription: 'Reminders for your habits, to-dos and plans',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            actions: [
              AndroidNotificationAction('snooze', 'Snooze $_snoozeMinutes min', cancelNotification: true),
            ],
          ),
    windows: alarm
        ? WindowsNotificationDetails(
            scenario: WindowsNotificationScenario.alarm,
            audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.alarm1, shouldLoop: true),
            actions: [
              WindowsAction(content: 'Snooze $_snoozeMinutes min', arguments: 'snooze:$payload'),
              const WindowsAction(content: 'Stop', arguments: 'stop'),
            ],
          )
        : WindowsNotificationDetails(
            audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.reminder),
            actions: [WindowsAction(content: 'Snooze $_snoozeMinutes min', arguments: 'snooze:$payload')],
          ),
  );
  try {
    await plugin.zonedSchedule(
      id: id,
      title: a['title']?.toString(),
      body: a['body']?.toString(),
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Android: Snooze or Stop pressed while the app wasn't running. Runs in a
/// separate background engine, so it sets the plugin up again on its own.
@pragma('vm:entry-point')
void alertBackgroundResponse(NotificationResponse r) {
  WidgetsFlutterBinding.ensureInitialized();
  final parsed = parseResponse(r);
  if (parsed.action != 'snooze') return; // Stop: the button already took the notification away
  final plugin = FlutterLocalNotificationsPlugin();
  unawaited(plugin.initialize(settings: _initSettings).then((_) => snoozeWith(plugin, parsed.payload)).catchError((Object _) {}));
}
