import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/app.dart';

void main() {
  LicenseRegistry.addLicense(_fontLicenses);
  runApp(const ProviderScope(child: HppApp()));
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
