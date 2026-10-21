import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'common.dart';

/// Profil usaha. MVP berisi satu baris; fase 3 bisa banyak usaha per pengguna.
@DataClassName('Business')
class Businesses extends Table with EntityColumns {
  TextColumn get name => text()();
  TextColumn get phoneWa => text().nullable()();
  TextColumn get logoPath => text().nullable()();

  /// Pembulatan harga saran: 100, 500, atau 1000.
  IntColumn get priceRounding => integer().withDefault(const Constant(500))();
  RealColumn get defaultMarkupPct => real().withDefault(const Constant(60.0))();

  /// Mode stok bawaan untuk menu baru; bawaannya ready stock.
  TextColumn get stockDeductMode => text()
      .map(const CodedEnumConverter(StockDeductMode.values))
      .withDefault(const Constant('ON_PRODUCTION'))();
  BoolColumn get allowNegativeStock =>
      boolean().withDefault(const Constant(false))();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Jakarta'))();

  /// Upah per jam pemilik untuk HPP; diubah → HPP semua menu dihitung ulang.
  IntColumn get ownerHourlyWage => integer().nullable()();

  /// Tanggal Tutup hari terakhir, `YYYY-MM-DD`.
  TextColumn get lastClosedOn => text().nullable()();

  /// Diisi setelah onboarding selesai atau dilewati (FR-8.4). Skema v2.
  DateTimeColumn get onboardedAt => dateTime().nullable()();

  /// uid Firebase pemilik setelah login Google; kosong = mode lokal
  /// (FR-10.1). Skema v3, tidak ikut disinkron.
  TextColumn get ownerUid => text().nullable()();
}

/// Pengaturan notifikasi, 1:1 dengan [Businesses].
class NotificationSettings extends Table with EntityColumns {
  TextColumn get businessId => text().unique().references(Businesses, #id)();
  BoolColumn get orderEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get stockEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get paymentEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get dayCloseEnabled =>
      boolean().withDefault(const Constant(true))();
  TextColumn get dailySummaryTime =>
      text().withDefault(const Constant('06:00'))();
  TextColumn get dayCloseTime => text().withDefault(const Constant('20:00'))();

  /// JSON daftar pengingat bawaan untuk pesanan baru.
  TextColumn get defaultOffsets => text().withDefault(
    const Constant(
      '[{"type":"DAY_BEFORE","time":"08:00"},{"type":"BEFORE_DUE","minutes":120}]',
    ),
  )();
  TextColumn get quietStart => text().nullable()();
  TextColumn get quietEnd => text().nullable()();
}

@DataClassName('ExpenseCategory')
class ExpenseCategories extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// Pengeluaran operasional. Belanja bahan dan upah pemilik yang sudah masuk
/// HPP tidak dicatat di sini.
@TableIndex(name: 'expenses_business_spent', columns: {#businessId, #spentAt})
class Expenses extends Table with EntityColumns, VoidColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get spentAt => dateTime()();

  /// Pengeluaran bulanan (sewa, gaji) tidak masuk ringkasan harian, hanya
  /// laporan bulanan (FR-7.7). Skema v2.
  BoolColumn get isMonthly => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
}
