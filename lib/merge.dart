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
const syncKeys = ['habits', 'todos', 'activities', 'payments'];

Map<String, dynamic> syncPart(Map<String, dynamic> state) =>
    {for (final k in syncKeys) k: state[k] ?? <dynamic>[]};

bool hasContent(Map<String, dynamic> part) =>
    syncKeys.any((k) => part[k] is List && (part[k] as List).isNotEmpty);

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};
