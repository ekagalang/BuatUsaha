import 'package:cloud_firestore/cloud_firestore.dart';

import 'remote_store.dart';
import 'sync_schema.dart';

/// Data akun di Cloud Firestore: `users/{uid}/{tabel}/{id}` (PRD 11.5).
/// Antrean offline dipegang `sync_outbox`, jadi cache Firestore dimatikan.
class FirestoreRemoteStore implements RemoteStore {
  FirestoreRemoteStore([FirebaseFirestore? firestore])
    : _fs = firestore ?? FirebaseFirestore.instance {
    _fs.settings = const Settings(persistenceEnabled: false);
  }

  /// Tanpa internet Firestore menunggu terus; dianggap gagal setelah ini.
  static const _timeout = Duration(seconds: 45);
  static const _page = 500;
  static const _server = GetOptions(source: Source.server);

  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _col(String uid, String table) =>
      _fs.collection('users').doc(uid).collection(table);

  @override
  int get maxBatch => 400;

  @override
  Future<void> write(String uid, List<RemoteWrite> writes) async {
    final batch = _fs.batch();
    for (final w in writes) {
      batch.set(_col(uid, w.table).doc(w.id), {
        ...?w.data,
        '_v': w.version,
        '_s': FieldValue.serverTimestamp(),
        '_deleted': w.data == null,
      });
    }
    await batch.commit().timeout(_timeout);
  }

  @override
  Future<List<RemoteDoc>> changedSince(
    String uid,
    String table,
    DateTime? since, {
    void Function(int count)? onPage,
  }) async {
    Query<Map<String, dynamic>> base = _col(uid, table);
    if (since != null) {
      base = base.where(
        '_s',
        isGreaterThan: Timestamp.fromMicrosecondsSinceEpoch(
          since.microsecondsSinceEpoch,
        ),
      );
    }
    base = base.orderBy('_s');
    final docs = <RemoteDoc>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var query = base.limit(_page);
      if (last != null) query = query.startAfterDocument(last);
      final snap = await query.get(_server).timeout(_timeout);
      for (final d in snap.docs) {
        final doc = _toDoc(d.id, d.data());
        if (doc != null) docs.add(doc);
      }
      onPage?.call(snap.docs.length);
      if (snap.docs.length < _page) return docs;
      last = snap.docs.last;
    }
  }

  @override
  Future<int> countAll(String uid) async {
    var total = 0;
    for (final table in syncedTables) {
      // Agregasi dihitung di server: 1 baca per 1.000 dokumen.
      final snap = await _col(uid, table).count().get().timeout(_timeout);
      total += snap.count ?? 0;
    }
    return total;
  }

  @override
  Future<List<String>> businessIds(String uid) async {
    final snap = await _col(uid, 'businesses').get(_server).timeout(_timeout);
    return [
      for (final d in snap.docs)
        if (d.data()['_deleted'] != true) d.id,
    ];
  }

  @override
  Future<DateTime?> lastWriteAt(String uid) async {
    DateTime? latest;
    for (final table in syncedTables) {
      final snap = await _col(
        uid,
        table,
      ).orderBy('_s', descending: true).limit(1).get(_server).timeout(_timeout);
      if (snap.docs.isEmpty) continue;
      final at = (snap.docs.first.data()['_s'] as Timestamp?)?.toDate();
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  @override
  Future<void> saveProfile(String uid, {String? email, String? name}) async {
    final ref = _fs.collection('users').doc(uid);
    final existing = await ref.get(_server).timeout(_timeout);
    await ref
        .set({
          'email': email,
          'name': name,
          if (!existing.exists) 'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(_timeout);
  }

  static RemoteDoc? _toDoc(String id, Map<String, dynamic> raw) {
    final server = raw['_s'];
    if (server is! Timestamp) return null;
    return RemoteDoc(
      id: id,
      version: (raw['_v'] as num?)?.toInt() ?? 0,
      serverTime: server.toDate().toUtc(),
      data: raw['_deleted'] == true
          ? null
          : {
              for (final e in raw.entries)
                if (!e.key.startsWith('_')) e.key: e.value,
            },
    );
  }
}
