import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/enums.dart';

const _uuid = Uuid();

/// UUID v7 dibuat di HP: urut menurut waktu dan tidak bentrok saat sinkron.
String newId() => _uuid.v7();

DateTime nowUtc() => DateTime.now().toUtc();

/// Menyimpan [CodedEnum] sebagai TEXT berisi `code`-nya.
class CodedEnumConverter<T extends CodedEnum> extends TypeConverter<T, String> {
  const CodedEnumConverter(this.values);

  final List<T> values;

  @override
  T fromSql(String fromDb) {
    for (final value in values) {
      if (value.code == fromDb) return value;
    }
    throw ArgumentError.value(fromDb, 'fromDb', 'Kode $T tidak dikenal');
  }

  @override
  String toSql(T value) => value.code;
}

/// Kolom wajib semua tabel: primary key UUID dan kolom audit untuk sinkron.
mixin EntityColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(nowUtc)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Transaksi tidak dihapus permanen; pembatalan mengisi kolom ini (FR-9.1).
mixin VoidColumns on Table {
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
}
