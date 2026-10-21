import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Versi aplikasi `major.minor.patch` (PRD FR-11.1), dibandingkan per angka:
/// 1.10.0 lebih baru dari 1.9.0.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// "v1.2.0", "1.2.0", atau "1.2.0+57" → 1.2.0; selain itu `null`.
  static AppVersion? tryParse(String text) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Satu file APK di rilis GitHub.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;

  /// Ukuran dalam byte.
  final int size;
}

/// Rilis terbaru di GitHub Releases (FR-11.2, FR-11.3).
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    this.publishedAt,
  });

  final AppVersion version;
  final String tag;

  /// Poin perubahan dari catatan rilis (baris `- …` dari CHANGELOG.md).
  final List<String> notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final version = AppVersion.tryParse(tag);
    if (version == null ||
        json['draft'] == true ||
        json['prerelease'] == true) {
      return null;
    }
    final body = json['body'] as String? ?? '';
    return ReleaseInfo(
      version: version,
      tag: tag,
      notes: [
        for (final line in const LineSplitter().convert(body))
          if (RegExp(r'^\s*[-*]\s+').hasMatch(line))
            line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '').trim(),
      ],
      pageUrl: json['html_url'] as String? ?? GitHubReleaseSource.releasesPage,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: [
        for (final a in (json['assets'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> &&
              (a['name'] as String? ?? '').endsWith('.apk'))
            ReleaseAsset(
              name: a['name'] as String,
              url: a['browser_download_url'] as String,
              size: (a['size'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }

  /// APK yang cocok dengan jenis HP (FR-11.4): ABI pertama yang tersedia,
  /// arm64-v8a sebagai cadangan.
  ReleaseAsset? assetFor(List<String> abis) {
    for (final abi in [...abis, 'arm64-v8a']) {
      for (final a in assets) {
        if (a.name.endsWith('-$abi.apk')) return a;
      }
    }
    return assets.isEmpty ? null : assets.first;
  }
}

/// Sumber rilis; GitHub di aplikasi, tiruan di test.
abstract class ReleaseSource {
  /// `null` = belum ada rilis.
  Future<ReleaseInfo?> latest();
}

/// API publik GitHub Releases tanpa token (batas 60 permintaan per jam per
/// jaringan).
class GitHubReleaseSource implements ReleaseSource {
  static const repo = 'ekagalang/BuatUsaha';
  static const releasesPage = 'https://github.com/$repo/releases';
  static const _timeout = Duration(seconds: 15);

  @override
  Future<ReleaseInfo?> latest() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .getUrl(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          )
          .timeout(_timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'BuatUsaha');
      final response = await request.close().timeout(_timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub menjawab ${response.statusCode}');
      }
      return ReleaseInfo.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }
}

/// Versi yang terpasang di HP ini.
class InstalledApp {
  const InstalledApp({required this.versionName, required this.buildNumber});

  final String versionName;
  final String buildNumber;

  AppVersion? get version => AppVersion.tryParse(versionName);
}

/// Bagian Android yang dipakai pembaruan; tiruan di test.
abstract class AppPlatform {
  Future<InstalledApp> installed();
  Future<List<String>> supportedAbis();

  /// Izin "pasang dari sumber ini" (Android 8+).
  Future<bool> canInstallPackages();
  Future<void> openInstallSettings();
  Future<void> installApk(String path);
  Future<void> openUrl(String url);
}

/// Saluran `buatusaha/app` di `MainActivity.kt`.
class AndroidAppPlatform implements AppPlatform {
  static const _channel = MethodChannel('buatusaha/app');

  @override
  Future<InstalledApp> installed() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledApp(
      versionName: info.version,
      buildNumber: info.buildNumber,
    );
  }

  @override
  Future<List<String>> supportedAbis() async =>
      (await _channel.invokeListMethod<String>('supportedAbis')) ?? const [];

  @override
  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> installApk(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});

  @override
  Future<void> openUrl(String url) =>
      _channel.invokeMethod<void>('openUrl', {'url': url});
}

/// Mengunduh APK [asset] ke folder cache `updates/` (dibagikan ke penginstal
/// lewat FileProvider). File yang sudah lengkap dipakai lagi.
class UpdateDownloader {
  UpdateDownloader({Future<Directory> Function()? cacheDir})
    : _cacheDir = cacheDir ?? getTemporaryDirectory;

  final Future<Directory> Function() _cacheDir;

  Future<File> download(
    ReleaseAsset asset, {
    required void Function(int received, int total) onProgress,
    required bool Function() cancelled,
  }) async {
    final dir = Directory('${(await _cacheDir()).path}/updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/${asset.name}');
    if (file.existsSync() && file.lengthSync() == asset.size) {
      onProgress(asset.size, asset.size);
      return file;
    }
    // APK versi lain tidak dibutuhkan lagi.
    for (final old in dir.listSync().whereType<File>()) {
      old.deleteSync();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BuatUsaha');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Unduhan gagal (${response.statusCode})');
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : asset.size;
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (cancelled()) throw const UpdateCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.close();
      if (total > 0 && received != total) {
        throw HttpException('Unduhan terputus ($received dari $total byte)');
      }
      return partial.renameSync(file.path);
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Penyimpanan kecil per HP (tidak disinkron): kapan terakhir dicek, versi
/// yang disembunyikan, versi yang sudah diberitahukan.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// Tanpa cache di memori, jadi aman dipakai bersama tugas latar.
class SharedPrefsStore implements KeyValueStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}

abstract final class UpdateKeys {
  static const lastCheck = 'update.last_check';
  static const dismissed = 'update.dismissed';
  static const notified = 'update.notified';
}

/// "25,9 MB".
String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
