import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'merge.dart';

/// Pictures in notes and canvases. They're kept as files in `attachments/` next to heatbits.json,
/// not inside the synced data, so a save or a sync doesn't carry every picture each time.
/// The data only lists them (state.files: [{id, name, type, w, h, size, created}]); the files
/// themselves go across once, after a sync, to whichever device doesn't have them yet.
class Attachments {
  Attachments._(this.dir);

  final Directory dir;

  /// Largest picture accepted (the page shrinks photos well below this before sending).
  static const maxBytes = 30 * 1024 * 1024;
  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|gif|webp)$');

  static Future<Attachments> open(Directory base) async {
    final d = Directory('${base.path}${Platform.pathSeparator}attachments');
    try {
      await d.create(recursive: true);
    } catch (_) {}
    return Attachments._(d);
  }

  /// Only plain file names like `img-abc123.jpg`: nothing that could reach outside the folder.
  static bool validId(String id) => _id.hasMatch(id);

  File file(String id) => File('${dir.path}${Platform.pathSeparator}$id');

  Future<bool> has(String id) async => validId(id) && await file(id).exists();

  Future<Set<String>> list() async {
    final out = <String>{};
    try {
      await for (final f in dir.list()) {
        final name = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
        if (f is File && validId(name)) out.add(name);
      }
    } catch (_) {}
    return out;
  }

  /// How many pictures there are and how much space they take (Settings → Data & storage).
  Future<(int, int)> stats() async {
    var count = 0, bytes = 0;
    for (final id in await list()) {
      try {
        bytes += await file(id).length();
        count++;
      } catch (_) {}
    }
    return (count, bytes);
  }

  /// Copies every picture [to] doesn't have yet (the data folder is moving there).
  /// False if one couldn't be copied, so the move can stop before anything is switched over.
  Future<bool> copyTo(Attachments to) async {
    for (final id in await list()) {
      try {
        if (!await to.file(id).exists()) await file(id).copy(to.file(id).path);
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Saves [bytes] as [id] (written to a temp file first, so a half-written picture never shows).
  Future<bool> save(String id, Stream<List<int>> bytes) async {
    if (!validId(id)) return false;
    final tmp = File('${file(id).path}.part');
    try {
      final sink = tmp.openWrite();
      var total = 0;
      await for (final chunk in bytes) {
        total += chunk.length;
        if (total > maxBytes) {
          await sink.close();
          await tmp.delete();
          return false;
        }
        sink.add(chunk);
      }
      await sink.close();
      if (await file(id).exists()) await file(id).delete();
      await tmp.rename(file(id).path);
      return true;
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Sends the picture, or 404 if this device doesn't have it (yet).
  Future<void> serve(HttpRequest req, String id) async {
    final res = req.response;
    final f = file(id);
    if (!validId(id) || !await f.exists()) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    res.headers.contentType = typeOf(id);
    // a picture's name never changes, so the web view can keep it
    res.headers.set('cache-control', 'private, max-age=31536000, immutable');
    await res.addStream(f.openRead());
    await res.close();
  }

  static ContentType typeOf(String id) {
    final ext = id.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return ContentType('image', 'png');
      case 'gif':
        return ContentType('image', 'gif');
      case 'webp':
        return ContentType('image', 'webp');
      default:
        return ContentType('image', 'jpeg');
    }
  }
}

/// Pictures nothing points at any more (removed from every note and canvas): the files on disk
/// plus those listed in state.files whose id appears nowhere else in [state]. Matching the id
/// anywhere, not just in `![[…]]`, means a picture is only dropped when it's surely unused.
Set<String> unusedFileIds(Map<String, dynamic> state, Set<String> onDisk) {
  final rest = jsonEncode(Map<String, dynamic>.of(state)..remove('files'));
  return {...onDisk, ...fileIdsIn(state)}.where((id) => !rest.contains(id)).toSet();
}

/// The pictures the data knows about (state.files).
Set<String> fileIdsIn(Map<String, dynamic> state) {
  final list = state['files'];
  if (list is! List) return <String>{};
  return list.map((f) => asMap(f)['id']?.toString() ?? '').where(Attachments.validId).toSet();
}
