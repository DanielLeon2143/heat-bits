import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_bits/store.dart';

void main() {
  test('one backup a day, only the newest 7 are kept', () async {
    final dir = await Directory.systemTemp.createTemp('hb-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final f = Store.fileIn(dir);
    final backups = Directory('${dir.path}${Platform.pathSeparator}backups');
    List<String> names() => backups.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

    await f.writeAsString('{"day": 1}');
    await backup(f, DateTime(2026, 10, 1));
    await f.writeAsString('{"day": 1, "later": true}');
    await backup(f, DateTime(2026, 10, 1)); // same day: the first copy stays
    expect(names(), ['heatbits-2026-10-01.json']);
    expect(await File('${backups.path}${Platform.pathSeparator}heatbits-2026-10-01.json').readAsString(), '{"day": 1}');

    for (var d = 2; d <= 10; d++) {
      await backup(f, DateTime(2026, 10, d));
    }
    expect(names(), [for (var d = 4; d <= 10; d++) 'heatbits-2026-10-${d.toString().padLeft(2, '0')}.json']);
  });

  test('no data file, no backup', () async {
    final dir = await Directory.systemTemp.createTemp('hb-backup-');
    addTearDown(() => dir.delete(recursive: true));
    await backup(Store.fileIn(dir), DateTime(2026, 10, 1));
    expect(Directory('${dir.path}${Platform.pathSeparator}backups').existsSync(), false);
  });
}
