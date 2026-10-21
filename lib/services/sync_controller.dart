import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/sync/firestore_remote_store.dart';
import '../data/sync/remote_store.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_schema.dart';
import 'account_service.dart';
import 'auto_backup.dart';
import 'backup_service.dart';

/// `true` setelah `Firebase.initializeApp` berhasil (ada
/// `google-services.json` di build ini); diisi di `main`.
final firebaseReadyProvider = Provider<bool>((ref) => false);

final accountGatewayProvider = Provider<AccountGateway?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseAccountGateway() : null,
);

final remoteStoreProvider = Provider<RemoteStore?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirestoreRemoteStore() : null,
);

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final remote = ref.watch(remoteStoreProvider);
  return remote == null
      ? null
      : SyncEngine(ref.watch(appDatabaseProvider), remote);
});

/// Jumlah perubahan yang belum terkirim (FR-10.7).
final pendingChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(syncEngineProvider)?.watchPending() ?? Stream.value(0),
);

final lastSyncProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(syncEngineProvider)?.watchLastSync() ?? Stream.value(null),
);

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncStatus {
  const SyncStatus({
    this.available = false,
    this.ready = false,
    this.user,
    this.linked = false,
    this.busy = false,
    this.error,
  });

  /// Firebase siap di build ini.
  final bool available;

  /// Status masuk dan keterhubungan data sudah diketahui; sebelum itu
  /// aplikasi menampilkan layar pembuka.
  final bool ready;
  final AccountUser? user;

  /// Data HP ini terhubung dengan akun [user] dan ikut disinkron.
  final bool linked;
  final bool busy;

  /// Pesan kegagalan terakhir; hilang setelah berhasil.
  final String? error;

  static const _keep = Object();

  SyncStatus copyWith({
    bool? ready,
    Object? user = _keep,
    bool? linked,
    bool? busy,
    Object? error = _keep,
  }) => SyncStatus(
    available: available,
    ready: ready ?? this.ready,
    user: identical(user, _keep) ? this.user : user as AccountUser?,
    linked: linked ?? this.linked,
    busy: busy ?? this.busy,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

/// Akun dan sinkron (PRD 5.10). Masuk wajib (FR-10.1): router menahan
/// pengguna di layar Masuk sampai [SyncStatus.user] ada, lalu di layar
/// Menyiapkan sampai [SyncStatus.linked].
///
/// Kapan sinkron berjalan (FR-10.2): kirim ±15 detik setelah perubahan
/// tersimpan; tarik + kirim saat aplikasi dibuka, kembali dari latar, tiap
/// 30 menit selama dibuka, dan tiap 6 jam di latar (WorkManager). Gagal →
/// dicoba lagi makin jarang sampai 15 menit.
class SyncController extends Notifier<SyncStatus> {
  static const pushDelay = Duration(seconds: 15);
  static const _foregroundPull = Duration(minutes: 30);
  static const _retry = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  Timer? _pushTimer;
  Timer? _retryTimer;
  Timer? _periodic;
  StreamSubscription<AccountUser?>? _authSub;
  StreamSubscription<void>? _dbSub;
  AppLifecycleListener? _lifecycle;
  var _failures = 0;

  AccountGateway? get _gateway => ref.read(accountGatewayProvider);
  SyncEngine? get _engine => ref.read(syncEngineProvider);

  @override
  SyncStatus build() {
    final gateway = ref.watch(accountGatewayProvider);
    final engine = ref.watch(syncEngineProvider);
    ref.onDispose(_stop);
    if (gateway == null || engine == null) {
      // Build tanpa Firebase: layar Masuk menampilkan pesannya (FR-10.12).
      return const SyncStatus(ready: true);
    }

    final db = ref.watch(appDatabaseProvider);
    // Stream login langsung mengirim akun saat ini → status siap.
    _authSub = gateway.changes().listen(_onUser);
    _dbSub = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            for (final t in db.allTables)
              if (syncedTables.contains(t.actualTableName)) t,
          ]),
        )
        .listen((_) => _schedulePush());
    _lifecycle = AppLifecycleListener(onResume: () => _run(full: true));
    _periodic = Timer.periodic(_foregroundPull, (_) => _run(full: true));
    return SyncStatus(available: true, user: gateway.current);
  }

  void _stop() {
    _pushTimer?.cancel();
    _retryTimer?.cancel();
    _periodic?.cancel();
    _authSub?.cancel();
    _dbSub?.cancel();
    _lifecycle?.dispose();
    _pushTimer = _retryTimer = _periodic = null;
    _authSub = null;
    _dbSub = null;
    _lifecycle = null;
  }

  Future<void> _onUser(AccountUser? user) async {
    final engine = _engine;
    if (engine == null || !ref.mounted) return;
    final linkedUid = await engine.linkedUid();
    if (!ref.mounted) return;
    final linked = user != null && linkedUid == user.uid;
    state = state.copyWith(ready: true, user: user, linked: linked);
    if (linked) await _run(full: true);
  }

  void _schedulePush() {
    if (!state.linked) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () => _run(full: false));
  }

  Future<void> _run({required bool full}) async {
    final engine = _engine;
    final user = state.user;
    if (engine == null || user == null || !state.linked) return;
    await _guard(() => engine.sync(user.uid, pull: full));
  }

  /// Menjalankan [body] dengan status sibuk; gagal → pesan di [SyncStatus]
  /// (FR-10.7) dan sinkron dicoba lagi nanti. `true` jika berhasil.
  Future<bool> _guard(Future<void> Function() body) async {
    state = state.copyWith(busy: true);
    try {
      await body();
      if (!ref.mounted) return true;
      _failures = 0;
      _retryTimer?.cancel();
      state = state.copyWith(busy: false, error: null);
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      _failures++;
      state = state.copyWith(busy: false, error: describeSyncError(e));
      _retryTimer?.cancel();
      _retryTimer = Timer(
        _retry[math.min(_failures, _retry.length) - 1],
        () => _run(full: true),
      );
      return false;
    }
  }

  // ------------------------------------------------------- Layar Masuk

  /// Masuk dengan Google (FR-10.1). `true` jika berhasil; dibatalkan atau
  /// gagal → `false`, pesannya di [SyncStatus.error].
  Future<bool> signIn() async {
    final gateway = _gateway;
    if (gateway == null) return false;
    AccountUser? user;
    final ok = await _guard(() async => user = await gateway.signIn());
    if (!ref.mounted) return false;
    if (ok && user == null) {
      state = state.copyWith(
        error:
            'Masuk dibatalkan. Pilih akun Google '
            'untuk melanjutkan.',
      );
      return false;
    }
    if (!ok) return false;
    // Data belum terhubung: router pindah ke layar Menyiapkan.
    state = state.copyWith(ready: true, user: user, linked: false);
    return true;
  }

  // -------------------------------------------------- Layar Menyiapkan

  /// Backup baru dipulihkan: isi akun harus diganti isi HP ini (FR-10.11).
  Future<bool> overwritePending() async =>
      await _engine?.overwritePending() ?? false;

  /// Memeriksa isi akun dan HP ini (FR-10.13). `null` jika gagal.
  Future<LinkCheck?> inspect() async {
    final engine = _engine;
    final user = state.user;
    if (engine == null || user == null) return null;
    LinkCheck? check;
    final ok = await _guard(() async {
      // Usaha bawaan dulu, supaya akun baru langsung punya usaha.
      await ref.read(businessRepositoryProvider).ensureDefault();
      check = await engine.check(user.uid);
    });
    return ok ? check : null;
  }

  /// Menghubungkan data HP ini dengan akun sesuai [check] dan [choice].
  Future<bool> link(
    LinkCheck check, {
    LinkChoice? choice,
    LinkProgressCallback? onProgress,
  }) async {
    final engine = _engine;
    final user = state.user;
    if (engine == null || user == null) return false;
    final ok = await _guard(() async {
      final replacing =
          check.plan == LinkPlan.download ||
          (check.plan == LinkPlan.choose && choice == LinkChoice.replace);
      if (replacing && !check.local.isEmpty) {
        // FR-10.5: data HP dicadangkan dulu ke file.
        await AutoBackup.snapshot(ref.read(appDatabaseProvider));
      }
      await engine.link(
        user.uid,
        check.plan,
        choice: choice,
        onProgress: onProgress,
      );
      try {
        await ref
            .read(remoteStoreProvider)
            ?.saveProfile(user.uid, email: user.email, name: user.name);
      } catch (_) {
        // Hanya keterangan akun; data usaha sudah tersinkron.
      }
    });
    if (!ok || !ref.mounted) return false;
    state = state.copyWith(linked: true);
    ref.invalidate(currentBusinessProvider);
    return true;
  }

  /// Isi akun diganti isi backup yang baru dipulihkan (FR-10.11).
  Future<bool> overwrite({LinkProgressCallback? onProgress}) async {
    final engine = _engine;
    final user = state.user;
    if (engine == null || user == null) return false;
    final ok = await _guard(
      () => engine.overwriteRemote(user.uid, onProgress: onProgress),
    );
    if (!ok || !ref.mounted) return false;
    state = state.copyWith(linked: true);
    ref.invalidate(currentBusinessProvider);
    return true;
  }

  /// Batal di layar Menyiapkan: keluar dari Google, kembali ke layar Masuk.
  /// Data HP ini belum terhubung, jadi tidak dihapus.
  Future<void> cancelLink() async {
    await _gateway?.signOut();
    if (ref.mounted) {
      state = state.copyWith(user: null, linked: false, error: null);
    }
  }

  // ------------------------------------------------------- Pengaturan

  Future<void> syncNow() => _run(full: true);

  /// Sebelum keluar: perubahan yang tertunda dicoba dikirim. Mengembalikan
  /// jumlah yang masih belum terkirim (tanpa internet).
  Future<int> flushBeforeSignOut() async {
    final engine = _engine;
    final user = state.user;
    if (engine == null) return 0;
    if (user != null && state.linked && await engine.pendingCount() > 0) {
      await _guard(() => engine.sync(user.uid, pull: false));
    }
    return engine.pendingCount();
  }

  /// Keluar akun (FR-10.8): data usaha dan backup otomatis dihapus dari HP
  /// ini, lalu router kembali ke layar Masuk. Data di akun tetap ada.
  Future<void> signOut() async {
    final engine = _engine;
    if (engine == null) return;
    _pushTimer?.cancel();
    _retryTimer?.cancel();
    await engine.unlink(wipe: true);
    for (final cleanup in [
      AutoBackup.deleteAll,
      BackupService.deleteLeftovers,
    ]) {
      try {
        await cleanup();
      } catch (e) {
        debugPrint('Keluar akun: backup lokal gagal dihapus ($e)');
      }
    }
    await _gateway?.signOut();
    if (!ref.mounted) return;
    state = state.copyWith(user: null, linked: false, error: null);
    ref.invalidate(currentBusinessProvider);
  }
}
