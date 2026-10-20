import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'presentation/app.dart';
import 'services/background_tasks.dart';
import 'services/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicenses);
  await LocalNotifications.instance.init();
  unawaited(registerBackgroundTasks().catchError((Object _) {}));
  final container = ProviderContainer();
  container.read(notificationSyncProvider).start();
  runApp(
    UncontrolledProviderScope(container: container, child: const HppApp()),
  );
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
