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
    this.user,
    this.linked = false,
    this.busy = false,
    this.error,
  });

  /// Firebase siap di build ini.
  final bool available;
  final AccountUser? user;

  /// Data HP ini terhubung dengan akun [user] dan ikut disinkron.
  final bool linked;
  final bool busy;

  /// Pesan kegagalan terakhir; hilang setelah sinkron berhasil.
  final String? error;

  static const _keep = Object();

  SyncStatus copyWith({
    Object? user = _keep,
    bool? linked,
    bool? busy,
    Object? error = _keep,
  }) => SyncStatus(
    available: available,
    user: identical(user, _keep) ? this.user : user as AccountUser?,
    linked: linked ?? this.linked,
    busy: busy ?? this.busy,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

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
  var _overwriting = false;

  AccountGateway? get _gateway => ref.read(accountGatewayProvider);
  SyncEngine? get _engine => ref.read(syncEngineProvider);

  @override
  SyncStatus build() {
    final gateway = ref.watch(accountGatewayProvider);
    final engine = ref.watch(syncEngineProvider);
    ref.onDispose(_stop);
    if (gateway == null || engine == null) return const SyncStatus();

    final db = ref.watch(appDatabaseProvider);
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
    // Stream login langsung mengirim akun saat ini → sinkron saat dibuka.
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
    state = state.copyWith(user: user, linked: linked);
    if (linked) {
      await _run(full: true);
    } else if (user != null && await engine.overwritePending()) {
      await _guard(() => _overwrite(user));
    }
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
  /// (FR-10.7) dan dicoba lagi nanti. `true` jika berhasil.
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

  // ------------------------------------------------------- Dari layar

  /// Login Google (FR-10.1). Mengembalikan pemeriksaan akun bila pengguna
  /// harus memilih gabung atau ganti (FR-10.5); `null` jika sudah selesai
  /// atau dibatalkan.
  Future<LinkCheck?> signIn() async {
    final gateway = _gateway;
    if (gateway == null) return null;
    AccountUser? user;
    if (!await _guard(() async => user = await gateway.signIn())) return null;
    final signedIn = user;
    if (signedIn == null) return null;
    state = state.copyWith(user: signedIn);
    return _connect(signedIn);
  }

  /// Sinkron sekarang. Bila data HP ini belum terhubung dengan akun yang
  /// login, sama seperti login pertama.
  Future<LinkCheck?> syncNow() async {
    final user = state.user;
    if (user == null) return null;
    if (state.linked) {
      await _run(full: true);
      return null;
    }
    return _connect(user);
  }

  Future<LinkCheck?> _connect(AccountUser user) async {
    final engine = _engine!;
    if (await engine.overwritePending()) {
      await _guard(() => _overwrite(user));
      return null;
    }
    LinkCheck? check;
    if (!await _guard(() async => check = await engine.check(user.uid))) {
      return null;
    }
    final result = check!;
    if (result.plan == LinkPlan.choose) return result;
    await link(result);
    return null;
  }

  /// Menghubungkan data HP ini dengan akun sesuai [check] dan [choice].
  Future<void> link(LinkCheck check, [LinkChoice? choice]) async {
    final engine = _engine;
    final user = state.user;
    if (engine == null || user == null) return;
    final ok = await _guard(() async {
      final replacing =
          check.plan == LinkPlan.download ||
          (check.plan == LinkPlan.choose && choice == LinkChoice.replace);
      if (replacing && !check.local.isEmpty) {
        // FR-10.5: data HP dicadangkan dulu ke file.
        await AutoBackup.snapshot(ref.read(appDatabaseProvider));
      }
      await engine.link(user.uid, check.plan, choice: choice);
      try {
        await ref
            .read(remoteStoreProvider)
            ?.saveProfile(user.uid, email: user.email, name: user.name);
      } catch (_) {
        // Hanya keterangan akun; data usaha sudah tersinkron.
      }
    });
    if (!ok || !ref.mounted) return;
    state = state.copyWith(linked: true);
    ref.invalidate(currentBusinessProvider);
  }

  /// Pengguna menutup dialog "Akun ini sudah berisi data": batal login.
  Future<void> cancelLink() async {
    await _gateway?.signOut();
    if (ref.mounted) state = state.copyWith(user: null, linked: false);
  }

  /// Keluar akun (FR-10.8). Perubahan yang masih tertunda dicoba dikirim
  /// dulu; [wipe] menghapus data dari HP ini.
  Future<void> signOut({required bool wipe}) async {
    final engine = _engine;
    final user = state.user;
    if (engine == null) return;
    if (user != null && state.linked) {
      try {
        await engine.sync(user.uid, pull: false);
      } catch (_) {
        // Tetap keluar; perubahan yang belum terkirim hilang dari antrean.
      }
    }
    await engine.unlink(wipe: wipe);
    await _gateway?.signOut();
    if (!ref.mounted) return;
    _retryTimer?.cancel();
    state = state.copyWith(user: null, linked: false, error: null);
    ref.invalidate(currentBusinessProvider);
  }

  /// Dipanggil setelah database diganti backup. Saat login, isi akun ikut
  /// diganti isi backup (data akun tidak menimpa data yang dipulihkan).
  Future<void> afterRestore() async {
    final engine = _engine;
    final user = _gateway?.current;
    if (engine == null || user == null) return;
    // Ditandai dulu: jika gagal (offline), dijalankan lagi saat sinkron
    // berikutnya.
    await engine.requestOverwrite();
    await _guard(() => _overwrite(user));
  }

  Future<void> _overwrite(AccountUser user) async {
    // Stream login dan afterRestore bisa memanggil bersamaan; cukup sekali.
    if (_overwriting) return;
    _overwriting = true;
    try {
      await _engine!.overwriteRemote(user.uid);
    } finally {
      _overwriting = false;
    }
    if (ref.mounted) state = state.copyWith(user: user, linked: true);
  }
}
