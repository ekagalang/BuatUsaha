import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db/app_database.dart';
import '../data/sync/firestore_remote_store.dart';
import '../data/sync/sync_engine.dart';
import 'app_updates.dart';
import 'local_notifications.dart';
import 'notification_sync.dart';
import 'update_controller.dart';

const _resyncTask = 'notification-resync';

/// Dijalankan WorkManager di isolate latar tiap 6 jam: data dari HP lain
/// ditarik (FR-10.2), lalu jadwal ringkasan harian dan pengingat ikut
/// diperbarui walau aplikasi tidak dibuka.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase();
    try {
      await _syncInBackground(db);
      await LocalNotifications.instance.init(background: true);
      await NotificationSync(db, LocalNotifications.instance).resync();
      await _checkUpdateInBackground();
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<void> _syncInBackground(AppDatabase db) async {
  try {
    await Firebase.initializeApp();
    final user = await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 10),
    );
    if (user == null) return;
    final engine = SyncEngine(db, FirestoreRemoteStore());
    if (await engine.linkedUid() != user.uid) return;
    await engine.sync(user.uid);
  } catch (_) {
    // Tanpa Firebase atau internet: dicoba lagi di jadwal berikutnya atau
    // saat aplikasi dibuka.
  }
}

/// Versi baru di GitHub → notifikasi sekali per versi (FR-11.3, FR-11.4).
Future<void> _checkUpdateInBackground() async {
  try {
    await notifyIfUpdateAvailable(
      platform: AndroidAppPlatform(),
      source: GitHubReleaseSource(),
      store: SharedPrefsStore(),
      notifications: LocalNotifications.instance,
    );
  } catch (_) {
    // Tanpa internet: dicek lagi di jadwal berikutnya.
  }
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
