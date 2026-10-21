import 'package:drift/drift.dart';

/// Antrean baris yang berubah dan belum terkirim ke Firestore (PRD 11.5).
/// Diisi trigger SQLite; tabel ini sendiri tidak disinkron.
@DataClassName('SyncOutboxEntry')
class SyncOutbox extends Table {
  TextColumn get entity => text().named('table_name')();
  TextColumn get rowId => text()();

  /// Waktu perubahan terakhir di HP ini (milidetik epoch); dipakai sebagai
  /// versi untuk aturan "yang terbaru menang".
  IntColumn get changedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {entity, rowId};
}

/// Batas tarik terakhir per tabel (waktu server Firestore).
@DataClassName('SyncStateEntry')
class SyncState extends Table {
  TextColumn get entity => text().named('table_name')();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}
