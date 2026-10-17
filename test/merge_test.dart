import 'package:flutter_test/flutter_test.dart';
import 'package:heat_bits/merge.dart';

void main() {
  test('edits on both devices to different items are both kept', () {
    final base = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true}}
      ],
      'todos': []
    };
    final pc = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true, '2026-10-11': true}}
      ],
      'todos': []
    };
    final phone = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true, '2026-10-12': true}}
      ],
      'todos': [
        {'id': 't1', 'text': 'Milk'}
      ]
    };
    final m = merge3(base, pc, phone) as Map;
    final c = ((m['habits'] as List).first as Map)['completions'] as Map;
    expect(c.keys.toSet(), {'2026-10-10', '2026-10-11', '2026-10-12'});
    expect((m['todos'] as List).length, 1);
  });

  test('notes: new notes from both devices are kept, and an edit on one side wins', () {
    final base = {
      'notes': [
        {'id': 'n1', 'title': 'Plan', 'body': 'old', 'folder': ''}
      ],
      'noteFolders': []
    };
    final pc = {
      'notes': [
        {'id': 'n1', 'title': 'Plan', 'body': 'old', 'folder': ''},
        {'id': 'n2', 'title': 'PC note', 'body': '', 'folder': 'h:walk'}
      ],
      'noteFolders': [
        {'id': 'f1', 'name': 'Ideas', 'parent': ''}
      ]
    };
    final phone = {
      'notes': [
        {'id': 'n1', 'title': 'Plan', 'body': 'new from phone', 'folder': 'f1'},
        {'id': 'n3', 'title': 'Phone note', 'body': 'See [[Plan]]', 'folder': ''}
      ],
      'noteFolders': []
    };
    final m = merge3(base, pc, phone) as Map;
    final notes = {for (final n in (m['notes'] as List).cast<Map>()) n['id']: n};
    expect(notes.keys.toSet(), {'n1', 'n2', 'n3'});
    expect(notes['n1']!['body'], 'new from phone');
    expect(notes['n1']!['folder'], 'f1');
    expect((m['noteFolders'] as List).length, 1);
  });

  test('deleted on one side and untouched on the other stays deleted', () {
    final base = {'todos': [{'id': 'a'}, {'id': 'b'}]};
    final pc = {'todos': [{'id': 'a'}]};
    final phone = {'todos': [{'id': 'a'}, {'id': 'b'}]};
    expect(deepEq(merge3(base, pc, phone), {'todos': [{'id': 'a'}]}), isTrue);
  });

  test('first sync after pairing keeps the habits on both devices', () {
    final pc = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true}}
      ],
      'todos': [],
      'activities': [],
      'payments': []
    };
    final phone = {
      'habits': [
        {'id': 'h2', 'name': 'Read', 'completions': {'2026-10-11': true}}
      ],
      'todos': [
        {'id': 't1', 'text': 'Milk'}
      ],
      'activities': [],
      'payments': []
    };
    final m = firstMerge(pc, phone);
    expect((m['habits'] as List).map((h) => (h as Map)['name']).toList(), ['Walk', 'Read']);
    expect((m['todos'] as List).length, 1);
  });

  test('first sync merges a habit both devices already share, and drops the PC habits the user swapped out', () {
    final pc = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true}},
        {'id': 'h3', 'name': 'Gym', 'completions': {}}
      ]
    };
    final phone = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-12': true}},
        {'id': 'h4', 'name': 'Gym', 'completions': {'2026-10-12': true}}
      ]
    };
    final m = firstMerge(pc, phone, dropPc: ['h3']);
    final habits = (m['habits'] as List).cast<Map>();
    expect(habits.map((h) => h['id']).toList(), ['h1', 'h4']);
    expect((habits.first['completions'] as Map).keys.toSet(), {'2026-10-10', '2026-10-12'});
  });

  test('same-named habits on the phone and the PC are found, ignoring case and spaces', () {
    final pc = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {'2026-10-10': true, '2026-10-11': true}},
        {'id': 'h2', 'name': 'Read', 'completions': {}}
      ]
    };
    final phone = {
      'habits': [
        {'id': 'h1', 'name': 'Walk', 'completions': {}},
        {'id': 'p1', 'name': ' read ', 'completions': {'2026-10-12': 3}},
        {'id': 'p2', 'name': 'Swim', 'completions': {}}
      ]
    };
    final c = habitNameClashes(phone, pc);
    expect(c.length, 1);
    expect(c.first['phone']['id'], 'p1');
    expect(c.first['pc']['id'], 'h2');
    expect(c.first['phone']['days'], 1);
    expect(habitNameClashes(phone, pc, skipPc: ['h2']), isEmpty);
  });

  test('settings that sync leave out the device-only ones, and keep them when applied', () {
    final pc = {
      'allColor': '#111111',
      'settings': {'theme': 'dark', 'fontScale': 1.2, 'tutorialSeen': true, 'syncSettings': true}
    };
    final shared = sharedPrefs(pc);
    expect(shared, {
      'settings': {'theme': 'dark', 'fontScale': 1.2},
      'allColor': '#111111'
    });
    final phone = {
      'habits': [],
      'allColor': '#222222',
      'settings': {'theme': 'light', 'demoAdded': true, 'soundDueDay': '2026-10-14'}
    };
    final next = withSharedPrefs(phone, shared);
    expect(next['allColor'], '#111111');
    expect(next['settings'], {'theme': 'dark', 'fontScale': 1.2, 'demoAdded': true, 'soundDueDay': '2026-10-14'});
    expect(syncsSettings(phone), isTrue);
    expect(syncsSettings({'settings': {'syncSettings': false}}), isFalse);
  });

  test('the first settings sync keeps the PC\'s on a clash; after that, changes on either side win', () {
    final pc = {'settings': {'theme': 'dark', 'font': 'serif'}};
    final phone = {'settings': {'theme': 'light', 'sound': false}};
    final first = mergePrefs(null, pc, phone);
    expect(first['settings'], {'theme': 'dark', 'font': 'serif', 'sound': false});

    final phoneLater = {'settings': {'theme': 'dark', 'font': 'serif', 'sound': true}};
    final pcLater = {'settings': {'theme': 'paper', 'font': 'serif', 'sound': false}};
    final m = mergePrefs(first, pcLater, phoneLater);
    expect(m['settings'], {'theme': 'paper', 'font': 'serif', 'sound': true});
  });

  group('notes edited on both devices', () {
    Map<String, dynamic> doc(List notes) => {'notes': notes};
    final base = doc([
      {'id': 'n1', 'title': 'Plan', 'body': 'a', 'folder': ''},
      {'id': 'n2', 'title': 'Other', 'body': 'x', 'folder': ''},
    ]);

    test('the same text changed differently on both is a clash', () {
      final pc = doc([{'id': 'n1', 'title': 'Plan', 'body': 'a + pc', 'folder': ''}, {'id': 'n2', 'title': 'Other', 'body': 'x', 'folder': ''}]);
      final phone = doc([{'id': 'n1', 'title': 'Plan', 'body': 'a + phone', 'folder': ''}, {'id': 'n2', 'title': 'Other', 'body': 'x2', 'folder': ''}]);
      final c = noteClashes(base, pc, phone);
      expect(c.map((x) => x['id']), ['n1']); // n2 changed on the phone only
      expect((c.first['pc'] as Map)['body'], 'a + pc');
      expect((c.first['phone'] as Map)['body'], 'a + phone');
    });

    test('no clash: one side only, both the same, or different fields', () {
      final pc = doc([{'id': 'n1', 'title': 'Plan', 'body': 'same', 'folder': ''}, {'id': 'n2', 'title': 'Renamed', 'body': 'x', 'folder': ''}]);
      final phone = doc([{'id': 'n1', 'title': 'Plan', 'body': 'same', 'folder': ''}, {'id': 'n2', 'title': 'Other', 'body': 'x2', 'folder': ''}]);
      expect(noteClashes(base, pc, phone), isEmpty);
    });

    test('a note new on both, or deleted on one side, is not a clash', () {
      final pc = doc([{'id': 'n3', 'title': 'New', 'body': 'p'}]);
      final phone = doc([{'id': 'n1', 'title': 'Plan', 'body': 'edited'}, {'id': 'n3', 'title': 'New', 'body': 'q'}]);
      expect(noteClashes(base, pc, phone), isEmpty);
    });

    test('keepPcText keeps the PC text but still merges other changes', () {
      final pc = doc([{'id': 'n1', 'title': 'Plan', 'body': 'a + pc', 'folder': ''}, {'id': 'n2', 'title': 'Other', 'body': 'x', 'folder': ''}]);
      final phone = doc([{'id': 'n1', 'title': 'Plan', 'body': 'a + phone', 'folder': 'f1'}, {'id': 'n2', 'title': 'Other', 'body': 'x2', 'folder': ''}]);
      final merged = asMap(merge3(base, pc, phone, preferB: true));
      final kept = keepPcText(merged, base, noteClashes(base, pc, phone));
      final notes = (kept['notes'] as List).cast<Map>();
      expect(notes.firstWhere((n) => n['id'] == 'n1')['body'], 'a + pc');
      expect(notes.firstWhere((n) => n['id'] == 'n1')['folder'], 'f1'); // the phone's move still comes through
      expect(notes.firstWhere((n) => n['id'] == 'n2')['body'], 'x2');
    });
  });
}
