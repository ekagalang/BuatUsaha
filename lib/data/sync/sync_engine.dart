import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import 'cache_rebuilder.dart';
import 'remote_store.dart';
import 'sync_schema.dart';

/// Hasil memeriksa akun saat login pertama di HP ini (FR-10.5, FR-10.6).
enum LinkPlan {
  /// Akun masih kosong: data HP ini diunggah.
  upload,

  /// HP ini belum berisi data: data akun diunduh.
  download,

  /// Data HP ini memang dari akun ini (pernah login lalu keluar): digabung
  /// tanpa bertanya.
  rejoin,

  /// HP ini dan akun sama-sama berisi data berbeda: pengguna memilih.
  choose,
}

enum LinkChoice { merge, replace }

/// Isi HP ini untuk dialog "Akun ini sudah berisi data".
class LocalSummary {
  const LocalSummary({
    required this.ingredients,
    required this.products,
    required this.orders,
    required this.others,
  });

  final int ingredients;
  final int products;
  final int orders;

  /// Belanja, pengeluaran, pelanggan, pemasok, produksi.
  final int others;

  bool get isEmpty =>
      ingredients == 0 && products == 0 && orders == 0 && others == 0;
}

enum LinkPhase { download, upload }

/// Progres menyiapkan data setelah masuk (FR-10.13).
class LinkProgress {
  const LinkProgress(this.phase, this.done, this.total);

  final LinkPhase phase;
  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
}

typedef LinkProgressCallback = void Function(LinkProgress progress);

class LinkCheck {
  const LinkCheck(this.plan, this.local, {this.remoteUpdatedAt});

  final LinkPlan plan;
  final LocalSummary local;

  /// Waktu data akun terakhir ditulis (hanya untuk [LinkPlan.choose]).
  final DateTime? remoteUpdatedAt;
}

/// Sinkron per baris antara SQLite di HP dan data akun (PRD 5.10, 11.5).
///
/// Kirim: trigger mencatat baris yang berubah ke `sync_outbox`; isi baris
/// terkini dikirim, baris yang sudah tidak ada dikirim sebagai tombstone.
/// Tarik: dokumen yang ditulis setelah batas tarik terakhir diterapkan;
/// konflik per baris dimenangkan perubahan terbaru (FR-10.4), lalu cache
/// dihitung ulang (FR-10.3).
class SyncEngine {
  SyncEngine(
    this._db,
    this._remote, {
    CacheRebuilder? rebuilder,
    DateTime Function()? clock,
  }) : _rebuilder = rebuilder ?? CacheRebuilder(_db),
       _clock = clock ?? DateTime.now;

  static const _lastSyncKey = '_last_sync';
  static const _overwriteKey = '_overwrite';

  /// Tabel anak-dulu untuk menarik: anak yang terlihat berarti induknya
  /// sudah tertulis lebih dulu, jadi induknya pasti ikut tertarik.
  static final _pullOrder = syncedTables.reversed.toList();

  final AppDatabase _db;
  final RemoteStore _remote;
  final CacheRebuilder _rebuilder;
  final DateTime Function() _clock;
  final _columns = <String, Set<String>>{};
  Future<void>? _running;

  int get _nowMs => _clock().toUtc().millisecondsSinceEpoch;

  // ------------------------------------------------------------- Status

  /// uid akun yang terhubung dengan data HP ini; `null` = belum terhubung.
  Future<String?> linkedUid() async {
    final row = await _db
        .customSelect(
          'SELECT owner_uid FROM businesses WHERE owner_uid IS NOT NULL LIMIT 1',
        )
        .getSingleOrNull();
    return row?.read<String>('owner_uid');
  }

  Future<int> pendingCount() async =>
      (await _pendingQuery().getSingle()).read<int>('n');

  /// Jumlah perubahan yang belum terkirim (FR-10.7). Ikut dihitung ulang
  /// setiap tabel apa pun berubah karena outbox diisi trigger.
  Stream<int> watchPending() =>
      _pendingQuery().watchSingle().map((r) => r.read<int>('n'));

  Selectable<QueryRow> _pendingQuery() => _db.customSelect(
    'SELECT COUNT(*) AS n FROM sync_outbox',
    readsFrom: _db.allTables.toSet(),
  );

  Stream<DateTime?> watchLastSync() =>
      (_db.select(_db.syncState)..where((t) => t.entity.equals(_lastSyncKey)))
          .watchSingleOrNull()
          .map((r) => r?.lastPulledAt);

  Future<LocalSummary> localSummary() async {
    Future<int> count(String table) async =>
        (await _db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
            .read<int>('n');
    var others = 0;
    for (final t in [
      'purchases',
      'expenses',
      'customers',
      'suppliers',
      'productions',
    ]) {
      others += await count(t);
    }
    return LocalSummary(
      ingredients: await count('ingredients'),
      products: await count('products'),
      orders: await count('orders'),
      others: others,
    );
  }

  // ------------------------------------------------- Login dan keluar

  /// Memeriksa akun [uid] sebelum menghubungkannya dengan data HP ini.
  Future<LinkCheck> check(String uid) async {
    final remote = await _remote.businessIds(uid);
    final local = await localSummary();
    if (remote.isEmpty) return LinkCheck(LinkPlan.upload, local);
    if (local.isEmpty) return LinkCheck(LinkPlan.download, local);
    final mine = await _db.select(_db.businesses).get();
    if (mine.any((b) => remote.contains(b.id))) {
      return LinkCheck(LinkPlan.rejoin, local);
    }
    return LinkCheck(
      LinkPlan.choose,
      local,
      remoteUpdatedAt: await _remote.lastWriteAt(uid),
    );
  }

  /// Menghubungkan data HP ini dengan akun [uid] lalu sinkron. Untuk
  /// [LinkPlan.choose], [choice] wajib diisi. [onProgress] melaporkan unduh
  /// lalu unggah (FR-10.13). Backup ke file sebelum data HP diganti adalah
  /// tugas pemanggil.
  Future<void> link(
    String uid,
    LinkPlan plan, {
    LinkChoice? choice,
    LinkProgressCallback? onProgress,
  }) async {
    await _exclusive(() async {
      switch (plan) {
        case LinkPlan.upload:
          await _linkUpload(uid);
        case LinkPlan.download:
          await _linkReplace(uid, onProgress);
        case LinkPlan.rejoin:
          await _linkMerge(uid, onProgress);
        case LinkPlan.choose:
          if (choice == null) throw ArgumentError.notNull('choice');
          await (choice == LinkChoice.replace
              ? _linkReplace(uid, onProgress)
              : _linkMerge(uid, onProgress));
      }
      await _push(uid, onProgress: onProgress);
      await _markSynced();
    });
  }

  /// Keluar akun (FR-10.8): sinkron berhenti. [wipe] menghapus seluruh data
  /// di HP ini; data di akun tetap ada.
  Future<void> unlink({required bool wipe}) async {
    await _exclusive(() async {
      await _db.transaction(() async {
        await setSyncFlag(_db, 'enabled', on: false);
        if (wipe) {
          await _wipe();
        } else {
          await _db.customStatement('UPDATE businesses SET owner_uid = NULL');
          await _resetState();
        }
      });
      _notifyAll();
    });
  }

  /// Tandai bahwa isi akun harus diganti isi [db] (backup yang dipulihkan),
  /// supaya tetap dijalankan walau internet baru ada nanti.
  static Future<void> markOverwrite(AppDatabase db) => db
      .into(db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(
          entity: _overwriteKey,
          lastPulledAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<bool> overwritePending() async =>
      await (_db.select(
        _db.syncState,
      )..where((t) => t.entity.equals(_overwriteKey))).getSingleOrNull() !=
      null;

  /// Setelah memulihkan backup saat login: isi HP ini menjadi isi akun.
  /// Baris akun yang tidak ada di backup dihapus dari akun, supaya HP lain
  /// ikut kembali ke isi backup dan data yang dipulihkan tidak tertimpa
  /// lagi saat menarik.
  Future<void> overwriteRemote(
    String uid, {
    LinkProgressCallback? onProgress,
  }) async {
    await _exclusive(() async {
      final docs = await _fetchAll(uid, onProgress);
      await _db.transaction(() async {
        await _resetState();
        await _setOwner(uid);
        await _enqueueAll();
        for (final MapEntry(key: table, value: list) in docs.entries) {
          for (final doc in list) {
            if (!doc.deleted && await _row(table, doc.id) == null) {
              await _enqueue(table, doc.id);
            }
          }
        }
        await _saveCursors(docs);
        await setSyncFlag(_db, 'enabled', on: true);
      });
      await _push(uid, onProgress: onProgress);
      await _markSynced();
    });
  }

  Future<void> _linkUpload(String uid) async {
    await _db.transaction(() async {
      await _resetState();
      await _setOwner(uid);
      await _enqueueAll();
      await setSyncFlag(_db, 'enabled', on: true);
    });
  }

  /// Data HP ini diganti seluruhnya dengan data akun.
  Future<void> _linkReplace(
    String uid, [
    LinkProgressCallback? onProgress,
  ]) async {
    final docs = await _fetchAll(uid, onProgress);
    await _db.transaction(() async {
      await setSyncFlag(_db, 'applying', on: true);
      await _wipe();
      final changes = PulledChanges()..everything = true;
      await _apply(uid, docs, changes);
      await _setOwner(uid);
      await _saveCursors(docs);
      await _rebuilder.rebuild(changes);
      await setSyncFlag(_db, 'applying', on: false);
      await setSyncFlag(_db, 'enabled', on: true);
    });
    _notifyAll();
  }

  /// Data akun ditambahkan ke data HP ini. Usaha HP ini dilebur ke usaha di
  /// akun; channel dan kategori pengeluaran bernama sama dipakai bersama.
  Future<void> _linkMerge(
    String uid, [
    LinkProgressCallback? onProgress,
  ]) async {
    final docs = await _fetchAll(uid, onProgress);
    await _db.transaction(() async {
      await setSyncFlag(_db, 'applying', on: true);
      await _resetState();
      final changes = PulledChanges()..everything = true;
      final fromRemote = await _apply(uid, docs, changes, merge: true);
      final remoteBusiness = docs['businesses']!
          .where((d) => !d.deleted)
          .map((d) => d.id)
          .firstOrNull;
      if (remoteBusiness != null) {
        final locals = await _db
            .customSelect(
              'SELECT id FROM businesses WHERE id <> ?',
              variables: [Variable.withString(remoteBusiness)],
            )
            .get();
        for (final row in locals) {
          await _mergeBusiness(row.read<String>('id'), into: remoteBusiness);
        }
      }
      await _setOwner(uid);
      await _enqueueAll();
      for (final key in fromRemote) {
        await _dequeue(key.$1, key.$2);
      }
      await _saveCursors(docs);
      await _rebuilder.rebuild(changes);
      await setSyncFlag(_db, 'applying', on: false);
      await setSyncFlag(_db, 'enabled', on: true);
    });
    _notifyAll();
  }

  Future<void> _mergeBusiness(String from, {required String into}) async {
    Future<void> dedupe(String table, String child, String column) async {
      final mine = await _db
          .customSelect(
            'SELECT id, name FROM $table WHERE business_id = ?',
            variables: [Variable.withString(from)],
          )
          .get();
      for (final row in mine) {
        final same = await _db
            .customSelect(
              'SELECT id FROM $table WHERE business_id = ? '
              'AND lower(trim(name)) = lower(trim(?)) LIMIT 1',
              variables: [
                Variable.withString(into),
                Variable.withString(row.read<String>('name')),
              ],
            )
            .getSingleOrNull();
        if (same == null) continue;
        final id = row.read<String>('id');
        await _db.customStatement(
          'UPDATE $child SET $column = ? WHERE $column = ?',
          [same.read<String>('id'), id],
        );
        await _db.customStatement('DELETE FROM $table WHERE id = ?', [id]);
      }
    }

    await dedupe('sales_channels', 'orders', 'channel_id');
    await dedupe('expense_categories', 'expenses', 'category_id');

    final settings = await _db
        .customSelect(
          'SELECT 1 FROM notification_settings WHERE business_id = ?',
          variables: [Variable.withString(into)],
        )
        .getSingleOrNull();
    if (settings != null) {
      await _db.customStatement(
        'DELETE FROM notification_settings WHERE business_id = ?',
        [from],
      );
    }

    // Nomor pesanan unik per usaha: yang bentrok diberi nomor berikutnya.
    final orders = await _db
        .customSelect(
          'SELECT o.id, o.order_no FROM orders o WHERE o.business_id = ? '
          'AND EXISTS (SELECT 1 FROM orders r WHERE r.business_id = ? '
          'AND r.order_no = o.order_no) ORDER BY o.id',
          variables: [Variable.withString(from), Variable.withString(into)],
        )
        .get();
    for (final row in orders) {
      await _db.customStatement('UPDATE orders SET order_no = ? WHERE id = ?', [
        await _nextOrderNo(row.read<String>('order_no')),
        row.read<String>('id'),
      ]);
    }

    for (final table in syncedTables) {
      if (table == 'businesses') continue;
      if (!(await _columnsOf(table)).contains('business_id')) continue;
      await _db.customStatement(
        'UPDATE $table SET business_id = ? WHERE business_id = ?',
        [into, from],
      );
    }
    await _db.customStatement('DELETE FROM businesses WHERE id = ?', [from]);
  }

  // ------------------------------------------------------------- Sinkron

  /// Tarik lalu kirim. [pull] `false` hanya mengirim (dipakai setelah
  /// perubahan lokal supaya hemat kuota baca).
  Future<void> sync(String uid, {bool pull = true}) => _exclusive(() async {
    if (pull) await _pull(uid);
    await _push(uid);
    await _markSynced();
  });

  Future<void> _pull(String uid) async {
    final docs = await _fetch(uid);
    if (docs.values.every((d) => d.isEmpty)) return;
    await _db.transaction(() async {
      await setSyncFlag(_db, 'applying', on: true);
      final changes = PulledChanges();
      await _apply(uid, docs, changes);
      await _saveCursors(docs);
      await _rebuilder.rebuild(changes);
      await setSyncFlag(_db, 'applying', on: false);
    });
    _notifyAll();
  }

  Future<void> _push(String uid, {LinkProgressCallback? onProgress}) async {
    final entries = await _db.select(_db.syncOutbox).get();
    if (entries.isEmpty) return;
    onProgress?.call(LinkProgress(LinkPhase.upload, 0, entries.length));
    int rank(SyncOutboxEntry e) {
      final i = syncedTables.indexOf(e.entity);
      return i < 0 ? syncedTables.length : i;
    }

    // Induk dulu, supaya akun tidak pernah berisi anak tanpa induk.
    entries.sort((a, b) {
      final byTable = rank(a).compareTo(rank(b));
      return byTable != 0 ? byTable : a.changedAt.compareTo(b.changedAt);
    });
    for (var i = 0; i < entries.length; i += _remote.maxBatch) {
      final chunk = entries.skip(i).take(_remote.maxBatch).toList();
      final writes = <RemoteWrite>[];
      final sent = <SyncOutboxEntry>[];
      for (final e in chunk) {
        if (!syncedTables.contains(e.entity)) {
          await _dequeue(e.entity, e.rowId);
          continue;
        }
        final row = await _row(e.entity, e.rowId);
        writes.add(
          RemoteWrite(
            table: e.entity,
            id: e.rowId,
            version: e.changedAt,
            data: row == null ? null : _outgoing(e.entity, row),
          ),
        );
        sent.add(e);
      }
      if (writes.isEmpty) continue;
      await _remote.write(uid, writes);
      await _db.transaction(() async {
        for (final e in sent) {
          // Baris yang berubah lagi selama dikirim tetap di antrean.
          await _db.customStatement(
            'DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ? '
            'AND changed_at = ?',
            [e.entity, e.rowId, e.changedAt],
          );
        }
      });
      onProgress?.call(
        LinkProgress(
          LinkPhase.upload,
          math.min(i + chunk.length, entries.length),
          entries.length,
        ),
      );
    }
  }

  Future<Map<String, List<RemoteDoc>>> _fetch(
    String uid, {
    bool all = false,
    void Function(int count)? onPage,
  }) async {
    final cursors = all ? const <String, DateTime>{} : await _cursors();
    return {
      for (final table in _pullOrder)
        table: await _remote.changedSince(
          uid,
          table,
          cursors[table],
          onPage: onPage,
        ),
    };
  }

  /// Semua data akun, dengan progres unduh bila diminta.
  Future<Map<String, List<RemoteDoc>>> _fetchAll(
    String uid,
    LinkProgressCallback? onProgress,
  ) async {
    if (onProgress == null) return _fetch(uid, all: true);
    final total = await _remote.countAll(uid);
    var done = 0;
    onProgress(LinkProgress(LinkPhase.download, 0, total));
    return _fetch(
      uid,
      all: true,
      onPage: (count) {
        done += count;
        onProgress(
          LinkProgress(LinkPhase.download, math.min(done, total), total),
        );
      },
    );
  }

  /// Menerapkan dokumen akun ke SQLite, induk dulu. Mengembalikan baris
  /// yang kini sama dengan isi akun.
  Future<Set<(String, String)>> _apply(
    String uid,
    Map<String, List<RemoteDoc>> docs,
    PulledChanges changes, {
    bool merge = false,
  }) async {
    final synced = <(String, String)>{};
    for (final table in syncedTables) {
      final list = docs[table] ?? const <RemoteDoc>[];
      if (list.isEmpty) continue;
      final columns = await _columnsOf(table);
      final localOnly = localOnlyColumns[table] ?? const <String>{};
      for (final doc in list) {
        final pending = await _pendingVersion(table, doc.id);
        // Perubahan di HP ini lebih baru: dibiarkan, nanti terkirim.
        if (pending != null && pending > doc.version) continue;
        final local = await _row(table, doc.id);

        if (doc.deleted) {
          if (local != null) {
            if (!await _tryStatement('DELETE FROM $table WHERE id = ?', [
              doc.id,
            ])) {
              // Masih dipakai baris lain di HP ini: dikirim lagi ke akun.
              await _enqueue(table, doc.id);
              continue;
            }
            changes.add(table, local);
          }
          await _dequeue(table, doc.id);
          continue;
        }

        final data = <String, Object?>{
          for (final e in doc.data!.entries)
            if (columns.contains(e.key) && !localOnly.contains(e.key))
              e.key: e.value,
        }..['id'] = doc.id;
        // Cache di HP ini selalu dihitung sendiri, jadi hanya kolom sumber
        // yang dibandingkan dan ditimpa.
        final source = _sourceOf(table, data);
        if (local != null && _same(local, source)) {
          await _dequeue(table, doc.id);
          synced.add((table, doc.id));
          continue;
        }
        if (merge && local != null && _isNewer(local, data)) continue;

        final clash = await _resolveUnique(table, data, changes);
        if (clash == _Clash.skip) continue;
        final ok = local == null
            ? await _insert(table, {...data, ...await _localValues(table, uid)})
            : await _update(table, doc.id, {
                ..._sourceOf(table, data),
                'updated_at': data['updated_at'],
              });
        if (!ok) continue;
        await _dequeue(table, doc.id);
        if (clash == _Clash.renumbered) {
          // Nomor pesanan diubah di HP ini; hasilnya dikirim balik.
          await _enqueue(table, doc.id);
        } else {
          synced.add((table, doc.id));
        }
        changes.add(table, data);
      }
    }
    return synced;
  }

  /// Kunci unik selain id yang bentrok dengan baris lain di HP ini. Dua HP
  /// memakai aturan yang sama supaya hasilnya sama: untuk pesanan, yang
  /// dibuat lebih dulu (id lebih kecil) mempertahankan nomornya; untuk
  /// lainnya, baris yang lebih baru (id lebih besar) dipakai.
  Future<_Clash> _resolveUnique(
    String table,
    Map<String, Object?> data,
    PulledChanges changes,
  ) async {
    final keys = uniqueKeys[table];
    if (keys == null || keys.any((k) => data[k] == null)) return _Clash.none;
    final id = data['id']! as String;
    final clashes = await _db
        .customSelect(
          'SELECT * FROM $table WHERE ${keys.map((k) => '$k = ?').join(' AND ')} '
          'AND id <> ?',
          variables: [
            for (final k in keys) Variable(data[k]),
            Variable.withString(id),
          ],
        )
        .get();
    var result = _Clash.none;
    for (final clash in clashes) {
      final otherId = clash.read<String>('id');
      if (table == 'orders') {
        if (id.compareTo(otherId) > 0) {
          data['order_no'] = await _nextOrderNo(data['order_no']! as String);
          result = _Clash.renumbered;
        } else {
          await _db.customStatement(
            'UPDATE orders SET order_no = ? WHERE id = ?',
            [await _nextOrderNo(data['order_no']! as String), otherId],
          );
          await _enqueue(table, otherId);
        }
        continue;
      }
      if (id.compareTo(otherId) > 0) {
        await _db.customStatement('DELETE FROM $table WHERE id = ?', [otherId]);
        await _enqueue(table, otherId);
        changes.add(table, clash.data);
      } else {
        // Baris akun kalah: dihapus juga dari akun.
        await _enqueue(table, id);
        return _Clash.skip;
      }
    }
    return result;
  }

  /// Nomor berikutnya untuk awalan nomor pesanan [orderNo] (`PO-261020-`).
  Future<String> _nextOrderNo(String orderNo) async {
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(orderNo);
    if (match == null) return '$orderNo-2';
    final prefix = match.group(1)!;
    final width = match.group(2)!.length;
    final rows = await _db
        .customSelect(
          'SELECT order_no FROM orders WHERE order_no LIKE ?',
          variables: [Variable.withString('$prefix%')],
        )
        .get();
    var max = int.parse(match.group(2)!);
    for (final r in rows) {
      final n = int.tryParse(
        r.read<String>('order_no').substring(prefix.length),
      );
      if (n != null && n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(width, '0')}';
  }

  // ----------------------------------------------------------- Pembantu

  Future<Set<String>> _columnsOf(String table) async =>
      _columns[table] ??= (await tableColumns(_db, table)).toSet();

  Future<Map<String, Object?>?> _row(String table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  Map<String, Object?> _outgoing(String table, Map<String, Object?> row) {
    final localOnly = localOnlyColumns[table] ?? const <String>{};
    return {
      for (final e in row.entries)
        if (!localOnly.contains(e.key)) e.key: e.value,
    };
  }

  /// Nilai kolom khusus HP ini untuk baris baru dari akun.
  Future<Map<String, Object?>> _localValues(String table, String uid) async {
    switch (table) {
      case 'businesses':
        return {'owner_uid': uid};
      case 'order_reminders':
        final row = await _db
            .customSelect(
              'SELECT MAX(notification_id) AS n FROM order_reminders',
            )
            .getSingle();
        final current = row.read<int?>('n') ?? 999;
        return {'notification_id': current < 999 ? 1000 : current + 1};
    }
    return const {};
  }

  /// [data] tanpa kolom cache dan `updated_at`.
  static Map<String, Object?> _sourceOf(
    String table,
    Map<String, Object?> data,
  ) {
    final cache = cacheColumns[table] ?? const <String>{};
    return {
      for (final e in data.entries)
        if (!cache.contains(e.key) && e.key != 'updated_at') e.key: e.value,
    };
  }

  static bool _same(Map<String, Object?> local, Map<String, Object?> data) {
    for (final e in data.entries) {
      if (local[e.key] != e.value) return false;
    }
    return true;
  }

  /// Saat menggabungkan: baris HP ini diubah setelah versi di akun.
  static bool _isNewer(Map<String, Object?> local, Map<String, Object?> data) {
    final mine = DateTime.tryParse('${local['updated_at']}');
    final theirs = DateTime.tryParse('${data['updated_at']}');
    return mine != null && theirs != null && mine.isAfter(theirs);
  }

  Future<bool> _insert(String table, Map<String, Object?> data) {
    final columns = data.keys.toList();
    return _tryStatement(
      'INSERT INTO $table (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      [for (final c in columns) data[c]],
    );
  }

  Future<bool> _update(String table, String id, Map<String, Object?> data) {
    final columns = data.keys.where((c) => c != 'id').toList();
    return _tryStatement(
      'UPDATE $table SET ${columns.map((c) => '$c = ?').join(', ')} '
      'WHERE id = ?',
      [for (final c in columns) data[c], id],
    );
  }

  /// Menjalankan satu perintah; baris yang melanggar constraint (misalnya
  /// induknya sudah tidak ada) dilewati supaya sinkron tidak macet.
  Future<bool> _tryStatement(String sql, List<Object?> args) async {
    try {
      await _db.customStatement(sql, args);
      return true;
    } catch (e) {
      if (!'$e'.contains('constraint failed')) rethrow;
      debugPrint('Sinkron: baris dilewati ($e)');
      return false;
    }
  }

  Future<int?> _pendingVersion(String table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT changed_at FROM sync_outbox WHERE table_name = ? AND row_id = ?',
          variables: [Variable.withString(table), Variable.withString(id)],
        )
        .getSingleOrNull();
    return row?.read<int>('changed_at');
  }

  Future<void> _enqueue(String table, String id) => _db.customStatement(
    'INSERT OR REPLACE INTO sync_outbox (table_name, row_id, changed_at) '
    'VALUES (?, ?, ?)',
    [table, id, _nowMs],
  );

  Future<void> _dequeue(String table, String id) => _db.customStatement(
    'DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ?',
    [table, id],
  );

  Future<void> _enqueueAll() async {
    for (final table in syncedTables) {
      await _db.customStatement(
        'INSERT OR REPLACE INTO sync_outbox (table_name, row_id, changed_at) '
        'SELECT ?, id, ? FROM $table',
        [table, _nowMs],
      );
    }
  }

  Future<void> _setOwner(String uid) =>
      _db.customStatement('UPDATE businesses SET owner_uid = ?', [uid]);

  /// Menghapus seluruh data usaha di HP ini, anak dulu.
  Future<void> _wipe() async {
    for (final table in _pullOrder) {
      await _db.customStatement('DELETE FROM $table');
    }
    await _resetState();
  }

  Future<void> _resetState() async {
    await _db.delete(_db.syncOutbox).go();
    await _db.delete(_db.syncState).go();
  }

  Future<Map<String, DateTime>> _cursors() async {
    final rows = await _db.select(_db.syncState).get();
    return {
      for (final r in rows)
        if (r.lastPulledAt != null) r.entity: r.lastPulledAt!,
    };
  }

  Future<void> _saveCursors(Map<String, List<RemoteDoc>> docs) async {
    for (final MapEntry(key: table, value: list) in docs.entries) {
      if (list.isEmpty) continue;
      final latest = list
          .map((d) => d.serverTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _db
          .into(_db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              entity: table,
              lastPulledAt: Value(latest),
            ),
          );
    }
  }

  Future<void> _markSynced() => _db
      .into(_db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(
          entity: _lastSyncKey,
          lastPulledAt: Value(_clock().toUtc()),
        ),
      );

  /// Perintah SQL mentah tidak memberi tahu stream drift; layar ikut
  /// dimuat ulang setelah data akun diterapkan.
  void _notifyAll() => _db.markTablesUpdated(_db.allTables);

  /// Satu proses sinkron sekaligus di isolate ini.
  Future<T> _exclusive<T>(Future<T> Function() body) async {
    while (_running != null) {
      await _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      return await body();
    } finally {
      _running = null;
      done.complete();
    }
  }
}

enum _Clash { none, renumbered, skip }
