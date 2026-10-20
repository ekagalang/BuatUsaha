import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db/app_database.dart';
import 'local_notifications.dart';
import 'notification_sync.dart';

const _resyncTask = 'notification-resync';

/// Dijalankan WorkManager di isolate latar: jadwal ringkasan harian dan
/// pengingat Tutup hari ikut diperbarui walau aplikasi tidak dibuka.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final db = AppDatabase();
    try {
      await LocalNotifications.instance.init(background: true);
      await NotificationSync(db, LocalNotifications.instance).resync();
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<void> registerBackgroundTasks() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _resyncTask,
    _resyncTask,
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
