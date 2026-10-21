import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'presentation/app.dart';
import 'services/auto_backup.dart';
import 'services/background_tasks.dart';
import 'services/local_notifications.dart';
import 'services/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicenses);
  final firebaseReady = await _initFirebase();
  await LocalNotifications.instance.init();
  unawaited(registerBackgroundTasks().catchError((Object _) {}));
  final container = ProviderContainer(
    overrides: [firebaseReadyProvider.overrideWithValue(firebaseReady)],
  );
  container.read(notificationSyncProvider).start();
  // Login Google dan sinkron otomatis (FR-10.1, FR-10.2).
  container.read(syncControllerProvider);
  unawaited(
    AutoBackup.runIfDue(container.read(appDatabaseProvider))
        .then((_) {}, onError: (Object _) {}),
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const HppApp()),
  );
}

/// Firebase untuk login, sinkron, dan laporan crash (PRD 5.10, 9.1).
/// Dilewati jika `google-services.json` belum dipasang: aplikasi tetap jalan
/// penuh dalam mode lokal.
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return false;
  }
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
  return true;
}

/// Lisensi OFL font yang dibundel, tampil di halaman lisensi aplikasi.
Stream<LicenseEntry> _fontLicenses() async* {
  const fonts = [
    ('Plus Jakarta Sans', 'assets/fonts/OFL-PlusJakartaSans.txt'),
    ('Fraunces', 'assets/fonts/OFL-Fraunces.txt'),
  ];
  for (final (family, path) in fonts) {
    yield LicenseEntryWithLineBreaks([
      family,
    ], await rootBundle.loadString(path));
  }
}
