import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../data/db/app_database.dart';
import '../data/sync/sync_engine.dart';

/// File SQLite yang dipakai aplikasi (lihat `driftDatabase(name: 'buat_usaha')`).
Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}buat_usaha.sqlite');
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Backup dan restore seluruh data ke satu file (FR-8.3).
class BackupService {
  const BackupService._();

  /// Salinan database yang konsisten (`VACUUM INTO`) di folder sementara,
  /// siap dibagikan lewat share sheet.
  static Future<File> export(AppDatabase db, {Directory? into}) async {
    final dir = into ?? await getTemporaryDirectory();
    final now = DateTime.now();
    final name =
        'buatusaha-backup-${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}.sqlite';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
    await db.customStatement('VACUUM INTO ?', [file.path]);
    return file;
  }

  /// Memastikan file benar-benar backup aplikasi ini; mengembalikan nama
  /// usaha di dalamnya. Melempar [FormatException] jika bukan.
  static Future<String> inspect(File file) async {
    final header = await file.openRead(0, 16).first;
    if (String.fromCharCodes(header.take(15)) != 'SQLite format 3') {
      throw const FormatException('File ini bukan backup BuatUsaha.');
    }
    // Buka salinan supaya file asli tidak ikut dimigrasi.
    final copy = await file.copy('${file.path}.check');
    final db = AppDatabase(NativeDatabase(copy));
    try {
      final business = await (db.select(
        db.businesses,
      )..limit(1)).getSingleOrNull();
      if (business == null) {
        throw const FormatException('Backup ini tidak berisi data usaha.');
      }
      return business.name;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('File ini bukan backup BuatUsaha.');
    } finally {
      await db.close();
      if (copy.existsSync()) copy.deleteSync();
    }
  }

  /// Salinan [backup] yang dilepas dari akun: uid pemilik, antrean kirim,
  /// dan batas tarik dihapus, lalu ditandai supaya isi akun diganti isi
  /// backup ini saat layar Menyiapkan berjalan (FR-10.11). Tanpa ini
  /// sinkron berikutnya akan menimpa data yang baru dipulihkan.
  static Future<File> detached(File backup) async {
    final copy = await backup.copy('${backup.path}.restore');
    final db = AppDatabase(NativeDatabase(copy));
    try {
      await db.customStatement('UPDATE businesses SET owner_uid = NULL');
      await db.delete(db.syncOutbox).go();
      await db.delete(db.syncState).go();
      await SyncEngine.markOverwrite(db);
    } finally {
      await db.close();
    }
    return copy;
  }

  /// Keluar akun (FR-10.8): salinan `.bak` dari pemulihan terakhir dihapus.
  static Future<void> deleteLeftovers({File? target}) async {
    final db = target ?? await databaseFile();
    final bak = File('${db.path}.bak');
    if (bak.existsSync()) bak.deleteSync();
  }

  /// Mengganti database aplikasi dengan [backup]. Database yang sedang
  /// dipakai harus sudah ditutup; data lama disimpan sebagai `.bak`.
  static Future<void> replaceDatabase(File backup, {File? target}) async {
    final db = target ?? await databaseFile();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final side = File('${db.path}$suffix');
      if (side.existsSync()) side.deleteSync();
    }
    if (db.existsSync()) await db.copy('${db.path}.bak');
    await backup.copy(db.path);
  }
}
