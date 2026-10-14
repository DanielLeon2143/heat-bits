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
}
