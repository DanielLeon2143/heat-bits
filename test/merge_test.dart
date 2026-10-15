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
}
