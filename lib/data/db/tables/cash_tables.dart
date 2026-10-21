import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'business_tables.dart';
import 'common.dart';

/// Akun kas: Tunai, Bank, QRIS/e-wallet, atau tambahan sendiri (FR-15.1).
/// Saldo tidak disimpan; dihitung dari saldo awal dan semua mutasinya.
/// Skema v6.
class CashAccounts extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get kind =>
      text().map(const CodedEnumConverter(CashAccountKind.values))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();

  /// Saldo awal berlaku mulai tanggal ini; mutasi sebelumnya tidak dihitung.
  DateTimeColumn get openingAt => dateTime().nullable()();

  /// Kode [PaymentMethod] yang masuk ke akun ini, dipisah koma (FR-15.2).
  TextColumn get paymentMethods => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Catatan kas manual: modal masuk, prive, pindah akun, koreksi saldo
/// (FR-15.3). Pembayaran, belanja, dan pengeluaran tidak dicatat di sini.
@TableIndex(
  name: 'cash_entries_business_time',
  columns: {#businessId, #occurredAt},
)
class CashEntries extends Table with EntityColumns, VoidColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get kind =>
      text().map(const CodedEnumConverter(CashEntryKind.values))();
  TextColumn get accountId => text().references(CashAccounts, #id)();

  /// Hanya untuk pindah akun.
  TextColumn get toAccountId =>
      text().nullable().references(CashAccounts, #id)();

  /// Positif, kecuali koreksi saldo: selisih bertanda (+ menambah saldo).
  IntColumn get amount => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
}
