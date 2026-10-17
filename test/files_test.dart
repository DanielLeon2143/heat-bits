import 'package:flutter_test/flutter_test.dart';
import 'package:heat_bits/files.dart';

void main() {
  Map<String, dynamic> meta(String id) => {'id': id, 'name': id, 'type': 'image/jpeg'};

  test('pictures still in a note or canvas are kept, the rest are unused', () {
    final state = <String, dynamic>{
      'files': [meta('img-a.jpg'), meta('img-b.png'), meta('img-c.jpg'), meta('img-gone.jpg')],
      'notes': [
        {'id': 'n1', 'title': 'Trip', 'body': 'Look ![[img-a.jpg|300]] here'},
        {
          'id': 'n2',
          'kind': 'canvas',
          'cards': [
            {'id': 'c1', 'type': 'image', 'file': 'img-b.png'},
            {'id': 'c2', 'type': 'text', 'text': '![[img-c.jpg]]'},
          ],
        },
      ],
    };
    final unused = unusedFileIds(state, {'img-a.jpg', 'img-b.png', 'img-c.jpg', 'img-gone.jpg', 'img-stray.webp'});
    expect(unused, {'img-gone.jpg', 'img-stray.webp'});
  });

  test('no notes at all: every picture is unused', () {
    expect(unusedFileIds({'files': [meta('img-a.jpg')]}, {'img-a.jpg'}), {'img-a.jpg'});
  });
}
