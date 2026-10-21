import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'cash_repository.dart';
import 'hpp_refresher.dart';

class BusinessRepository {
  BusinessRepository(this._db);

  final AppDatabase _db;

  /// MVP berisi satu usaha. Dibuat otomatis saat aplikasi pertama dibuka;
  /// namanya bisa diubah di Pengaturan.
  Future<Business> ensureDefault() {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.businesses,
      )..limit(1)).getSingleOrNull();
      if (existing != null) {
        await _seedLists(existing.id);
        return existing;
      }
      final business = await _db
          .into(_db.businesses)
          .insertReturning(BusinessesCompanion.insert(name: 'Usaha saya'));
      await _db
          .into(_db.notificationSettings)
          .insert(
            NotificationSettingsCompanion.insert(businessId: business.id),
          );
      await _seedLists(business.id);
      return business;
    });
  }

  /// Channel penjualan (FR-5.8) dan kategori pengeluaran (FR-7.3) bawaan;
  /// "Langsung" tidak disimpan (channel kosong). Potongan channel diisi
  /// sendiri di Pengaturan karena besarnya beda per mitra.
  Future<void> _seedLists(String businessId) async {
    await CashRepository(_db).ensureDefaults(businessId);
    final hasChannel =
        await (_db.select(_db.salesChannels)
              ..where((t) => t.businessId.equals(businessId))
              ..limit(1))
            .getSingleOrNull();
    if (hasChannel == null) {
      for (final name in defaultChannels) {
        await _db
            .into(_db.salesChannels)
            .insert(
              SalesChannelsCompanion.insert(businessId: businessId, name: name),
            );
      }
    }
    final hasCategory =
        await (_db.select(_db.expenseCategories)
              ..where((t) => t.businessId.equals(businessId))
              ..limit(1))
            .getSingleOrNull();
    if (hasCategory == null) {
      for (final name in defaultExpenseCategories) {
        await _db
            .into(_db.expenseCategories)
            .insert(
              ExpenseCategoriesCompanion.insert(
                businessId: businessId,
                name: name,
                isDefault: const Value(true),
              ),
            );
      }
    }
  }

  static const defaultChannels = [
    'WhatsApp',
    'Instagram',
    'GoFood',
    'GrabFood',
    'ShopeeFood',
    'Shopee',
  ];

  static const defaultExpenseCategories = [
    'Sewa',
    'Listrik bulanan',
    'Gaji',
    'Transport',
    'Promosi',
    'Lainnya',
  ];

  Stream<NotificationSetting> watchNotificationSettings(String businessId) =>
      (_db.select(
        _db.notificationSettings,
      )..where((t) => t.businessId.equals(businessId))).watchSingle();

  Future<void> updateNotificationSettings(
    String businessId,
    NotificationSettingsCompanion changes,
  ) =>
      (_db.update(_db.notificationSettings)
            ..where((t) => t.businessId.equals(businessId)))
          .write(changes.copyWith(updatedAt: Value(DateTime.now().toUtc())));

  /// Profil dan preferensi usaha (FR-8.1, FR-8.2).
  Future<void> updateBusiness(String businessId, BusinessesCompanion changes) =>
      (_db.update(_db.businesses)..where((t) => t.id.equals(businessId))).write(
        changes.copyWith(updatedAt: Value(DateTime.now().toUtc())),
      );

  Stream<Business> watch(String businessId) => (_db.select(
    _db.businesses,
  )..where((t) => t.id.equals(businessId))).watchSingle();

  /// Upah per jam pemilik (FR-2.4); `null` = belum diisi. HPP semua menu
  /// dihitung ulang.
  Future<void> setOwnerHourlyWage(String businessId, int? wage) {
    if (wage != null && wage < 0) {
      throw ArgumentError.value(wage, 'wage', 'harus ≥ 0');
    }
    return _db.transaction(() async {
      await (_db.update(
        _db.businesses,
      )..where((t) => t.id.equals(businessId))).write(
        BusinessesCompanion(
          ownerHourlyWage: Value(wage),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await refreshAllHpp(_db, businessId, cause: HppChangeCause.wage);
    });
  }

  /// Markup bawaan dan pembulatan harga saran (FR-2.5).
  Future<void> setPricing(
    String businessId, {
    Decimal? defaultMarkupPct,
    int? priceRounding,
  }) =>
      (_db.update(_db.businesses)..where((t) => t.id.equals(businessId))).write(
        BusinessesCompanion(
          defaultMarkupPct: defaultMarkupPct == null
              ? const Value.absent()
              : Value(dbl(defaultMarkupPct)),
          priceRounding: priceRounding == null
              ? const Value.absent()
              : Value(priceRounding),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
}
