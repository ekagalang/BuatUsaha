import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_updates.dart';
import 'notification_scheduler.dart';

final appPlatformProvider = Provider<AppPlatform>(
  (ref) => AndroidAppPlatform(),
);

final releaseSourceProvider = Provider<ReleaseSource>(
  (ref) => GitHubReleaseSource(),
);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SharedPrefsStore(),
);

final updateDownloaderProvider = Provider((ref) => UpdateDownloader());

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateStatus>(UpdateController.new);

/// Tanggal build dari `--dart-define=BUILD_DATE=yyyy-mm-dd` (skrip build dan
/// CI); kosong saat `flutter run`.
const buildDate = String.fromEnvironment('BUILD_DATE');

enum UpdateCheck { idle, checking, done, failed }

class UpdateStatus {
  const UpdateStatus({
    this.installed,
    this.latest,
    this.check = UpdateCheck.idle,
    this.lastCheckedAt,
    this.dismissedTag,
    this.dialogRequests = 0,
  });

  final InstalledApp? installed;
  final ReleaseInfo? latest;
  final UpdateCheck check;
  final DateTime? lastCheckedAt;

  /// Versi yang disembunyikan dari Beranda lewat tombol tutup (FR-11.4).
  final String? dismissedTag;

  /// Naik setiap notifikasi pembaruan diketuk; Beranda membuka dialog.
  final int dialogRequests;

  bool get hasUpdate {
    final mine = installed?.version;
    final theirs = latest?.version;
    return mine != null && theirs != null && theirs > mine;
  }

  /// Kartu "Versi baru tersedia" di Beranda.
  bool get showCard => hasUpdate && dismissedTag != latest!.tag;

  static const _keep = Object();

  UpdateStatus copyWith({
    Object? installed = _keep,
    Object? latest = _keep,
    UpdateCheck? check,
    Object? lastCheckedAt = _keep,
    Object? dismissedTag = _keep,
    int? dialogRequests,
  }) => UpdateStatus(
    installed: identical(installed, _keep)
        ? this.installed
        : installed as InstalledApp?,
    latest: identical(latest, _keep) ? this.latest : latest as ReleaseInfo?,
    check: check ?? this.check,
    lastCheckedAt: identical(lastCheckedAt, _keep)
        ? this.lastCheckedAt
        : lastCheckedAt as DateTime?,
    dismissedTag: identical(dismissedTag, _keep)
        ? this.dismissedTag
        : dismissedTag as String?,
    dialogRequests: dialogRequests ?? this.dialogRequests,
  );
}

/// Cek versi baru (FR-11.3): saat aplikasi dibuka atau kembali dari latar
/// bila cek terakhir lebih dari 6 jam, dan dari tombol Cek pembaruan.
class UpdateController extends Notifier<UpdateStatus> {
  static const interval = Duration(hours: 6);

  AppLifecycleListener? _lifecycle;
  Future<void>? _loading;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  UpdateStatus build() {
    ref.onDispose(() => _lifecycle?.dispose());
    _loading = _load();
    return const UpdateStatus();
  }

  // Versi terpasang dan catatan cek dibaca terpisah: penyimpanan yang gagal
  // tidak boleh menyembunyikan versi atau menggagalkan cek.
  Future<void> _load() async {
    InstalledApp? installed;
    try {
      installed = await ref.read(appPlatformProvider).installed();
    } catch (_) {
      // Tanpa info versi kartu pembaruan tidak tampil.
    }
    final last = DateTime.tryParse(await _read(UpdateKeys.lastCheck) ?? '');
    final dismissed = await _read(UpdateKeys.dismissed);
    if (!ref.mounted) return;
    state = state.copyWith(
      installed: installed,
      lastCheckedAt: last,
      dismissedTag: dismissed,
    );
  }

  Future<String?> _read(String key) async {
    try {
      return await _store.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _store.setString(key, value);
    } catch (_) {
      // Hanya catatan; cek berikutnya berjalan lagi.
    }
  }

  /// Dipanggil sekali dari `main`: cek sekarang bila sudah waktunya, lalu
  /// setiap kali aplikasi kembali dari latar.
  void start() {
    _lifecycle ??= AppLifecycleListener(onResume: checkIfDue);
    unawaited(checkIfDue());
  }

  Future<void> checkIfDue() async {
    await _loading;
    final last = state.lastCheckedAt;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await check();
  }

  /// Tombol Cek pembaruan di Tentang aplikasi.
  Future<void> check() async {
    await _loading;
    if (!ref.mounted || state.check == UpdateCheck.checking) return;
    state = state.copyWith(check: UpdateCheck.checking);
    try {
      final latest = await ref.read(releaseSourceProvider).latest();
      final now = DateTime.now();
      await _write(UpdateKeys.lastCheck, now.toIso8601String());
      if (!ref.mounted) return;
      state = state.copyWith(
        latest: latest,
        check: UpdateCheck.done,
        lastCheckedAt: now,
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(check: UpdateCheck.failed);
    }
  }

  /// Tombol tutup di kartu Beranda: disembunyikan sampai versi berikutnya.
  Future<void> dismiss() async {
    final tag = state.latest?.tag;
    if (tag == null) return;
    await _write(UpdateKeys.dismissed, tag);
    if (ref.mounted) state = state.copyWith(dismissedTag: tag);
  }

  /// Notifikasi pembaruan diketuk: Beranda membuka dialog pembaruan.
  void requestDialog() =>
      state = state.copyWith(dialogRequests: state.dialogRequests + 1);
}

/// Dijalankan WorkManager tiap 6 jam: notifikasi sekali per versi baru.
Future<void> notifyIfUpdateAvailable({
  required AppPlatform platform,
  required ReleaseSource source,
  required KeyValueStore store,
  required NotificationScheduler notifications,
}) async {
  final mine = (await platform.installed()).version;
  final latest = await source.latest();
  await store.setString(UpdateKeys.lastCheck, DateTime.now().toIso8601String());
  if (mine == null || latest == null || !(latest.version > mine)) return;
  if (await store.getString(UpdateKeys.notified) == latest.tag) return;
  await notifications.showNow(
    PlannedNotification(
      id: NotificationIds.update,
      at: DateTime.now(),
      title: 'Versi ${latest.version} tersedia',
      body: 'Ketuk untuk melihat yang baru dan memasangnya.',
      payload: 'update',
      channel: NotifyChannel.updates,
    ),
  );
  await store.setString(UpdateKeys.notified, latest.tag);
}
