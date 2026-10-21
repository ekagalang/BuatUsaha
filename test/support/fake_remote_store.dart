import 'package:buat_usaha/data/sync/remote_store.dart';

/// Firestore tiruan di memori: satu "server" yang dipakai beberapa HP.
/// Semua tulis dalam satu batch mendapat waktu server yang sama, seperti
/// `FieldValue.serverTimestamp()`.
class FakeRemoteStore implements RemoteStore {
  final _docs = <String, Map<String, RemoteDoc>>{};
  var _tick = 0;

  /// Simulasi tanpa internet: semua panggilan gagal.
  bool offline = false;
  int writeCount = 0;

  @override
  int maxBatch = 7;

  void _online() {
    if (offline) throw StateError('Tidak ada internet');
  }

  Map<String, RemoteDoc> _table(String uid, String table) =>
      (_docs['$uid/$table'] ??= {});

  @override
  Future<void> write(String uid, List<RemoteWrite> writes) async {
    _online();
    final at = DateTime.utc(2026, 10, 20).add(Duration(milliseconds: ++_tick));
    for (final w in writes) {
      writeCount++;
      _table(uid, w.table)[w.id] = RemoteDoc(
        id: w.id,
        version: w.version,
        serverTime: at,
        data: w.data == null ? null : Map.of(w.data!),
      );
    }
  }

  @override
  Future<List<RemoteDoc>> changedSince(
    String uid,
    String table,
    DateTime? since, {
    void Function(int count)? onPage,
  }) async {
    _online();
    final docs =
        _table(uid, table).values
            .where((d) => since == null || d.serverTime.isAfter(since))
            .toList()
          ..sort((a, b) => a.serverTime.compareTo(b.serverTime));
    onPage?.call(docs.length);
    return docs;
  }

  @override
  Future<int> countAll(String uid) async {
    _online();
    return _docs.entries
        .where((e) => e.key.startsWith('$uid/'))
        .fold<int>(0, (sum, e) => sum + e.value.length);
  }

  @override
  Future<List<String>> businessIds(String uid) async {
    _online();
    return [
      for (final d in _table(uid, 'businesses').values)
        if (!d.deleted) d.id,
    ];
  }

  @override
  Future<DateTime?> lastWriteAt(String uid) async {
    _online();
    DateTime? latest;
    for (final entry in _docs.entries) {
      if (!entry.key.startsWith('$uid/')) continue;
      for (final d in entry.value.values) {
        if (latest == null || d.serverTime.isAfter(latest)) {
          latest = d.serverTime;
        }
      }
    }
    return latest;
  }

  final profiles = <String, Map<String, String?>>{};

  @override
  Future<void> saveProfile(String uid, {String? email, String? name}) async {
    _online();
    profiles[uid] = {'email': email, 'name': name};
  }

  /// Dokumen yang belum dihapus di [table].
  List<Map<String, Object?>> live(String uid, String table) => [
    for (final d in _table(uid, table).values)
      if (!d.deleted) d.data!,
  ];
}
