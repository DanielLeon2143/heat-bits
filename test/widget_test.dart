// (kept so `flutter create` doesn't add its default counter-app test)
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_bits/merge.dart';

void main() {
  test('only habits, to-dos, activities, reminders, alarms and notes sync', () {
    final part = syncPart({'habits': [], 'settings': {'theme': 'dark'}, 'selectedId': 'x', 'notesUi': {}});
    expect(part.keys.toSet(), {'habits', 'todos', 'activities', 'payments', 'alarms', 'notes', 'noteFolders', 'files'});
  });
}
