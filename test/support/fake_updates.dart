import 'dart:io';

import 'package:buat_usaha/services/app_updates.dart';
import 'package:buat_usaha/services/notification_scheduler.dart';

ReleaseInfo release(
  String tag, {
  List<String> notes = const ['Daftar belanja otomatis', 'Perbaikan stok'],
}) => ReleaseInfo(
  version: AppVersion.tryParse(tag)!,
  tag: tag,
  notes: notes,
  pageUrl: 'https://github.com/ekagalang/BuatUsaha/releases/tag/$tag',
  assets: [
    ReleaseAsset(
      name: 'BuatUsaha-${tag.substring(1)}-arm64-v8a.apk',
      url: 'https://contoh/arm64.apk',
      size: 27158528,
    ),
  ],
);

class FakeAppPlatform implements AppPlatform {
  FakeAppPlatform({this.version = '1.0.0', this.canInstall = true});

  String version;
  bool canInstall;
  final installed_ = <String>[];
  final opened = <String>[];
  var settingsOpened = 0;

  @override
  Future<InstalledApp> installed() async =>
      InstalledApp(versionName: version, buildNumber: '152');

  @override
  Future<List<String>> supportedAbis() async => const ['arm64-v8a'];

  @override
  Future<bool> canInstallPackages() async => canInstall;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<void> installApk(String path) async => installed_.add(path);

  @override
  Future<void> openUrl(String url) async => opened.add(url);
}

class FakeReleaseSource implements ReleaseSource {
  FakeReleaseSource([this.next]);

  ReleaseInfo? next;
  bool offline = false;
  var calls = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    calls++;
    if (offline) throw const SocketException('Tidak ada internet');
    return next;
  }
}

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class FakeDownloader extends UpdateDownloader {
  FakeDownloader({this.fail = false});

  bool fail;
  var calls = 0;

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required void Function(int received, int total) onProgress,
    required bool Function() cancelled,
  }) async {
    calls++;
    onProgress(asset.size ~/ 2, asset.size);
    if (fail) throw const SocketException('Koneksi terputus');
    onProgress(asset.size, asset.size);
    return File('/cache/updates/${asset.name}');
  }
}

class RecordingNotifications implements NotificationScheduler {
  final shown = <PlannedNotification>[];

  @override
  Future<void> replaceScheduled(
    List<PlannedNotification> notifications,
  ) async {}

  @override
  Future<void> showNow(PlannedNotification notification) async =>
      shown.add(notification);
}

/// Seperti SharedPreferences 2.5.1 di build release: setiap akses gagal.
class BrokenStore implements KeyValueStore {
  @override
  Future<String?> getString(String key) =>
      Future.error(StateError('NoSuchMethodError'));

  @override
  Future<void> setString(String key, String value) =>
      Future.error(StateError('NoSuchMethodError'));
}
