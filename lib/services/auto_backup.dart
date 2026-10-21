import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/db/app_database.dart';
import '../data/repositories/day_close_repository.dart';

/// Backup otomatis harian di dalam HP: satu salinan database per hari saat
/// aplikasi dibuka, 7 terakhir disimpan (mockup `AkunData`).
class AutoBackup {
  const AutoBackup._();

  static const keep = 7;
  static const _prefix = 'otomatis-';

  static Future<Directory> folder() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Membuat backup hari ini jika belum ada; mengembalikan file barunya.
  static Future<File?> runIfDue(
    AppDatabase db, {
    DateTime? now,
    Directory? into,
  }) async {
    final dir = into ?? await folder();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_prefix${dayKey(now ?? DateTime.now())}.sqlite',
    );
    if (file.existsSync()) return null;
    await db.customStatement('VACUUM INTO ?', [file.path]);
    final all = await list(into: dir);
    for (final old in all.skip(keep)) {
      old.deleteSync();
    }
    return file;
  }

  /// Backup hari ini dibuat ulang sekarang, mis. sebelum data HP diganti
  /// data akun (FR-10.5). Muncul di daftar backup otomatis.
  static Future<File> snapshot(
    AppDatabase db, {
    DateTime? now,
    Directory? into,
  }) async {
    final dir = into ?? await folder();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_prefix${dayKey(now ?? DateTime.now())}.sqlite',
    );
    if (file.existsSync()) file.deleteSync();
    await db.customStatement('VACUUM INTO ?', [file.path]);
    return file;
  }

  /// Keluar akun (FR-10.8): backup otomatis ikut dihapus dari HP, supaya
  /// akun lain di HP ini tidak bisa memulihkannya.
  static Future<void> deleteAll({Directory? into}) async {
    for (final file in await list(into: into)) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Backup otomatis, terbaru di atas.
  static Future<List<File>> list({Directory? into}) async {
    final dir = into ?? await folder();
    if (!dir.existsSync()) return const [];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.uri.pathSegments.last.startsWith(_prefix) &&
                  f.path.endsWith('.sqlite'),
            )
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Tanggal backup dari nama filenya (`otomatis-2026-10-20.sqlite`).
  static DateTime? dateOf(File file) {
    final name = file.uri.pathSegments.last;
    final key = name.substring(_prefix.length, name.length - '.sqlite'.length);
    return DateTime.tryParse(key);
  }
}
