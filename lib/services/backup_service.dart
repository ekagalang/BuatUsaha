import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../data/db/app_database.dart';

/// File SQLite yang dipakai aplikasi (lihat `driftDatabase(name: 'hpp_app')`).
Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}hpp_app.sqlite');
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
        'hpp-backup-${now.year}${_two(now.month)}${_two(now.day)}-'
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
      throw const FormatException('File ini bukan backup HPP Usaha.');
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
      throw const FormatException('File ini bukan backup HPP Usaha.');
    } finally {
      await db.close();
      if (copy.existsSync()) copy.deleteSync();
    }
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
