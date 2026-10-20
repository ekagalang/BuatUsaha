import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/decimal_convert.dart';
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
      if (existing != null) return existing;
      final business = await _db
          .into(_db.businesses)
          .insertReturning(BusinessesCompanion.insert(name: 'Usaha saya'));
      await _db
          .into(_db.notificationSettings)
          .insert(
            NotificationSettingsCompanion.insert(businessId: business.id),
          );
      return business;
    });
  }

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
      await refreshAllHpp(_db, businessId);
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
