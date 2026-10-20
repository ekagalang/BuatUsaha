import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/services/auto_backup.dart';
import 'package:hpp_app/services/backup_service.dart';

import '../support/seed.dart';

void main() {
  late Seed s;
  late Directory dir;

  setUp(() async {
    s = await Seed.create();
    dir = Directory.systemTemp.createTempSync('hpp_auto_backup');
  });
  tearDown(() async {
    await s.close();
    dir.deleteSync(recursive: true);
  });

  test('satu backup per hari dan bisa dibaca kembali', () async {
    final day = DateTime(2026, 10, 20, 8);
    final first = await AutoBackup.runIfDue(s.db, now: day, into: dir);
    expect(first, isNotNull);
    expect(
      await AutoBackup.runIfDue(
        s.db,
        now: day.add(const Duration(hours: 5)),
        into: dir,
      ),
      isNull,
    );
    expect(await BackupService.inspect(first!), 'Usaha saya');
    expect(AutoBackup.dateOf(first), DateTime(2026, 10, 20));
  });

  test('hanya 7 backup terakhir yang disimpan, terbaru di atas', () async {
    for (var i = 1; i <= 9; i++) {
      await AutoBackup.runIfDue(s.db, now: DateTime(2026, 10, i), into: dir);
    }
    final files = await AutoBackup.list(into: dir);
    expect(files, hasLength(7));
    expect(AutoBackup.dateOf(files.first), DateTime(2026, 10, 9));
    expect(AutoBackup.dateOf(files.last), DateTime(2026, 10, 3));
  });
}
