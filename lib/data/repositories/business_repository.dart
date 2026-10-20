import '../db/app_database.dart';

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
}
