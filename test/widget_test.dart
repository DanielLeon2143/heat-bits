// (kept so `flutter create` doesn't add its default counter-app test)
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_bits/merge.dart';

void main() {
  test('only habits, to-dos, activities and reminders sync', () {
    final part = syncPart({'habits': [], 'settings': {'theme': 'dark'}, 'selectedId': 'x'});
    expect(part.keys.toSet(), {'habits', 'todos', 'activities', 'payments'});
  });
}
