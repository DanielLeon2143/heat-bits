// Three-way merge for Heat-Bits data.
//
// Both devices keep the last version they agreed on (the "base"). When they
// sync, every value is compared against that base:
//   * changed on one side only  -> that change wins
//   * changed on both sides     -> objects merge key by key, lists of items
//                                  with an "id" merge item by item; anything
//                                  else that truly clashes takes `b`
//   * deleted on one side, untouched on the other -> stays deleted
//   * deleted on one side, edited on the other    -> the edit is kept
//
// So ticking a habit on the phone while editing a to-do on the PC keeps both,
// and two different days logged on two devices both survive (completions are
// maps keyed by date).

const Object _absent = _Absent();

class _Absent {
  const _Absent();
}

bool deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

bool _allIdMaps(List l) => l.every((e) => e is Map && e['id'] != null);

/// Merges [a] and [b], which both started from [base]. On a true clash the
/// value from [b] wins when [preferB] is true.
Object? merge3(Object? base, Object? a, Object? b, {bool preferB = true}) {
  if (deepEq(a, b)) return a;
  if (deepEq(base, a)) return b;
  if (deepEq(base, b)) return a;

  if (a is Map && b is Map) {
    final Map bm = base is Map ? base : const {};
    final out = <String, dynamic>{};
    final keys = <String>[
      ...a.keys.map((k) => k.toString()),
      ...b.keys.map((k) => k.toString()).where((k) => !a.containsKey(k)),
    ];
    for (final k in keys) {
      final r = _mergeVal(
        bm.containsKey(k) ? bm[k] : _absent,
        a.containsKey(k) ? a[k] : _absent,
        b.containsKey(k) ? b[k] : _absent,
        preferB,
      );
      if (!identical(r, _absent)) out[k] = r;
    }
    return out;
  }

  if (a is List && b is List && _allIdMaps(a) && _allIdMaps(b) &&
      (base == null || (base is List && _allIdMaps(base)))) {
    return _mergeIdList(base is List ? base : null, a, b, preferB);
  }

  return preferB ? b : a;
}

Object? _mergeVal(Object? basev, Object? av, Object? bv, bool preferB) {
  final aGone = identical(av, _absent), bGone = identical(bv, _absent), baseGone = identical(basev, _absent);
  if (aGone && bGone) return _absent;
  if (aGone) {
    if (baseGone) return bv; // added on b
    return deepEq(basev, bv) ? _absent : bv; // deleted on a; kept only if b edited it
  }
  if (bGone) {
    if (baseGone) return av; // added on a
    return deepEq(basev, av) ? _absent : av; // deleted on b; kept only if a edited it
  }
  return merge3(baseGone ? null : basev, av, bv, preferB: preferB);
}

List<dynamic> _mergeIdList(List? base, List a, List b, bool preferB) {
  Map<String, dynamic> index(List? l) {
    final m = <String, dynamic>{};
    if (l != null) {
      for (final e in l) {
        if (e is Map && e['id'] != null) m[e['id'].toString()] = e;
      }
    }
    return m;
  }

  final bi = index(base), ai = index(a), bbi = index(b);
  // keep a's order, then append items that are new on b
  final order = <String>[...ai.keys, ...bbi.keys.where((k) => !ai.containsKey(k))];
  final out = <dynamic>[];
  for (final id in order) {
    final r = _mergeVal(
      bi.containsKey(id) ? bi[id] : _absent,
      ai.containsKey(id) ? ai[id] : _absent,
      bbi.containsKey(id) ? bbi[id] : _absent,
      preferB,
    );
    if (!identical(r, _absent)) out.add(r);
  }
  return out;
}

/// The parts of the app's data that sync between devices. Everything else
/// (settings, which page is open, collapsed panels…) stays per device.
const syncKeys = ['habits', 'todos', 'activities', 'payments', 'alarms', 'notes', 'noteFolders', 'files'];

Map<String, dynamic> syncPart(Map<String, dynamic> state) =>
    {for (final k in syncKeys) k: state[k] ?? <dynamic>[]};

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

/// The first sync after pairing: nothing has been agreed yet, so everything on
/// both devices is kept (as if both had added it). PC habits listed in [dropPc]
/// are left out: the user chose the phone's habit of the same name instead.
Map<String, dynamic> firstMerge(Map<String, dynamic> pc, Map<String, dynamic> phone, {Iterable<String> dropPc = const []}) {
  final drop = dropPc.toSet();
  final server = {
    ...pc,
    'habits': ((pc['habits'] as List?) ?? const [])
        .where((h) => !(h is Map && drop.contains(h['id']?.toString())))
        .toList(),
  };
  final empty = {for (final k in syncKeys) k: <dynamic>[]};
  return asMap(merge3(empty, server, phone, preferB: true));
}

/// Habits that are different on the phone and the PC (different ids) but have
/// the same name. Merging would leave two habits called the same, so the user
/// picks one or renames one first. PC habits in [skipPc] are already decided.
List<Map<String, dynamic>> habitNameClashes(Map<String, dynamic> phone, Map<String, dynamic> pc,
    {Iterable<String> skipPc = const []}) {
  String norm(Object? n) => (n ?? '').toString().trim().toLowerCase();
  final skip = skipPc.toSet();
  final pcAll = ((pc['habits'] as List?) ?? const []).whereType<Map>().toList();
  final pcIds = pcAll.map((h) => h['id']?.toString()).toSet();
  final pcOpen = pcAll.where((h) => !skip.contains(h['id']?.toString())).toList();
  final out = <Map<String, dynamic>>[];
  for (final h in ((phone['habits'] as List?) ?? const []).whereType<Map>()) {
    if (pcIds.contains(h['id']?.toString())) continue; // the same habit, synced before
    final n = norm(h['name']);
    if (n.isEmpty) continue;
    final match = pcOpen.where((p) => norm(p['name']) == n).firstOrNull;
    if (match != null) out.add({'phone': _habitSummary(h), 'pc': _habitSummary(match)});
  }
  return out;
}

Map<String, dynamic> _habitSummary(Map h) {
  final c = h['completions'];
  final days = c is Map ? c.values.where((v) => v != null && v != false && v != 0).length : 0;
  return {
    'id': h['id']?.toString(),
    'name': (h['name'] ?? '').toString(),
    'type': (h['type'] ?? 'boolean').toString(),
    'unit': (h['unit'] ?? '').toString(),
    'color': h['color']?.toString(),
    'days': days,
    'trackers': h['subTrackers'] is List ? (h['subTrackers'] as List).length : 0,
  };
}

// ---------------- notes edited on both devices ----------------
// A note's title and text are single values: if both devices changed one differently since they last
// agreed, merge3 would just keep the phone's. Instead the PC keeps its own for now and the phone asks.

const noteTextKeys = ['title', 'body'];

Map<String, Map<String, dynamic>> _notesById(Object? doc) {
  final list = asMap(doc)['notes'];
  return {
    if (list is List)
      for (final n in list)
        if (n is Map && n['id'] != null) n['id'].toString(): asMap(n),
  };
}

/// Notes whose title or text was changed differently on the PC and the phone since [base].
/// Each is `{id, pc: note, phone: note}` (the whole note as it is on each device).
List<Map<String, dynamic>> noteClashes(Object? base, Map<String, dynamic> pc, Map<String, dynamic> phone) {
  final b = _notesById(base), p = _notesById(phone);
  final out = <Map<String, dynamic>>[];
  _notesById(pc).forEach((id, pcNote) {
    final was = b[id], ph = p[id];
    if (was == null || ph == null) return;
    final clash = noteTextKeys.any((k) => !deepEq(was[k], pcNote[k]) && !deepEq(was[k], ph[k]) && !deepEq(pcNote[k], ph[k]));
    if (clash) out.add({'id': id, 'pc': pcNote, 'phone': ph});
  });
  return out;
}

/// [merged] (the usual sync merge) with the clashing notes merged the other way round: the PC's
/// title/text win, and anything else changed on either side (folder, canvas cards…) still merges.
Map<String, dynamic> keepPcText(Map<String, dynamic> merged, Object? base, List<Map<String, dynamic>> clashes) {
  if (clashes.isEmpty) return merged;
  final b = _notesById(base);
  final fixed = {for (final c in clashes) c['id'] as String: merge3(b[c['id']], c['phone'], c['pc'], preferB: true)};
  final notes = ((merged['notes'] as List?) ?? const []).map((n) {
    final id = n is Map ? n['id']?.toString() : null;
    return id != null && fixed.containsKey(id) ? fixed[id] : n;
  }).toList();
  return {...merged, 'notes': notes};
}

// ---------------- settings ----------------
// Settings sync too (colors, font, sound, layout…) while "Sync settings" is on, on both devices.
// These stay on each device whatever the switch says.
const localSettings = {'tutorialSeen', 'demoAdded', 'soundDueDay', 'syncSettings', 'closeToTray', 'globalHotkey', 'localFonts'};

/// This device's "Sync settings" switch (on unless turned off).
bool syncsSettings(Map<String, dynamic> state) => asMap(state['settings'])['syncSettings'] != false;

/// The settings that sync, plus the app color (which the page keeps outside settings).
Map<String, dynamic> sharedPrefs(Map<String, dynamic> state) {
  final s = asMap(state['settings']);
  return {
    'settings': {for (final k in s.keys) if (!localSettings.contains(k)) k: s[k]},
    if (state['allColor'] != null) 'allColor': state['allColor'],
  };
}

/// [state] with its shared settings replaced by [prefs]; the device-only ones are kept.
Map<String, dynamic> withSharedPrefs(Map<String, dynamic> state, Map<String, dynamic> prefs) {
  final own = asMap(state['settings']);
  return {
    ...state,
    'settings': {
      ...asMap(prefs['settings']),
      for (final k in own.keys) if (localSettings.contains(k)) k: own[k],
    },
    if (prefs['allColor'] != null) 'allColor': prefs['allColor'],
  };
}

/// Settings sent by a phone, merged with the PC's. The first time (no [base]) the PC's win a clash.
Map<String, dynamic> mergePrefs(Object? base, Map<String, dynamic> pc, Map<String, dynamic> phone) =>
    asMap(merge3(base is Map ? base : null, pc, phone, preferB: base is Map));
