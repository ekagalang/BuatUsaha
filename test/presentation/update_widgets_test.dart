import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/presentation/settings/about_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/presentation/update/update_widgets.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/fake_updates.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeAppPlatform platform;
  late FakeReleaseSource source;
  late FakeDownloader downloader;
  late MemoryStore store;

  setUp(() {
    platform = FakeAppPlatform();
    source = FakeReleaseSource(release('v1.1.0'));
    downloader = FakeDownloader();
    store = MemoryStore();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appPlatformProvider.overrideWithValue(platform),
        releaseSourceProvider.overrideWithValue(source),
        keyValueStoreProvider.overrideWithValue(store),
        updateDownloaderProvider.overrideWithValue(downloader),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await _settle(tester);
    return container;
  }

  Widget beranda() => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [UpdateCard()],
    ),
  );

  testWidgets('kartu muncul bila ada versi baru dan bisa disembunyikan', (
    tester,
  ) async {
    final c = await pump(tester, beranda());
    expect(find.text('Versi 1.1.0 tersedia'), findsNothing);

    await c.read(updateControllerProvider.notifier).check();
    await _settle(tester);
    expect(find.text('Versi 1.1.0 tersedia'), findsOneWidget);
    expect(find.text('2 perubahan · 25,9 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Sembunyikan sampai versi berikutnya'));
    await _settle(tester);
    expect(find.text('Versi 1.1.0 tersedia'), findsNothing);
  });

  testWidgets('versi yang sama: tidak ada kartu', (tester) async {
    source.next = release('v1.0.0');
    final c = await pump(tester, beranda());
    await c.read(updateControllerProvider.notifier).check();
    await _settle(tester);
    expect(find.textContaining('tersedia'), findsNothing);
  });

  testWidgets('unduh → izin pertama kali → pemasangan lanjut otomatis', (
    tester,
  ) async {
    platform.canInstall = false;
    final c = await pump(tester, beranda());
    await c.read(updateControllerProvider.notifier).check();
    await _settle(tester);

    await tester.tap(find.text('Lihat'));
    await _settle(tester);
    expect(find.text('Yang baru'), findsOneWidget);
    expect(find.text('• Daftar belanja otomatis'), findsOneWidget);
    expect(find.textContaining('Kamu memakai versi 1.0.0'), findsOneWidget);

    await tester.tap(find.text('Unduh dan pasang'));
    await _settle(tester);
    expect(find.text('Izinkan pemasangan'), findsOneWidget);
    expect(downloader.calls, 1);

    await tester.tap(find.text('Buka pengaturan'));
    await _settle(tester);
    expect(platform.settingsOpened, 1);

    // Kembali dari pengaturan setelah izin diberikan.
    platform.canInstall = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(find.text('Siap dipasang'), findsOneWidget);
    expect(platform.installed_, hasLength(1));
    expect(platform.installed_.single, endsWith('arm64-v8a.apk'));
  });

  testWidgets('unduhan gagal: coba lagi atau lewat browser', (tester) async {
    downloader.fail = true;
    final c = await pump(tester, beranda());
    await c.read(updateControllerProvider.notifier).check();
    await _settle(tester);
    await tester.tap(find.text('Lihat'));
    await _settle(tester);
    await tester.tap(find.text('Unduh dan pasang'));
    await _settle(tester);

    expect(find.text('Unduhan gagal'), findsOneWidget);
    expect(find.textContaining('Koneksi terputus di 13,0 MB'), findsOneWidget);
    await tester.tap(find.text('Unduh lewat browser'));
    await _settle(tester);
    expect(platform.opened, ['https://contoh/arm64.apk']);

    downloader.fail = false;
    await tester.tap(find.text('Coba lagi'));
    await _settle(tester);
    expect(find.text('Siap dipasang'), findsOneWidget);
  });

  testWidgets('Tentang aplikasi: versi dan Cek pembaruan', (tester) async {
    await pump(tester, const AboutScreen());
    expect(find.text('Versi 1.0.0 (build 152)'), findsOneWidget);
    expect(find.text('Cek pembaruan'), findsOneWidget);

    await tester.tap(find.text('Cek pembaruan'));
    await _settle(tester);
    expect(find.text('Versi 1.1.0 tersedia'), findsOneWidget);

    source.next = release('v1.0.0');
    await tester.tap(find.text('Lihat'));
    await _settle(tester);
    expect(find.text('Unduh dan pasang'), findsOneWidget);
  });

  testWidgets('Tentang aplikasi: sudah terbaru dan gagal', (tester) async {
    source.next = release('v1.0.0');
    await pump(tester, const AboutScreen());
    await tester.tap(find.text('Cek pembaruan'));
    await _settle(tester);
    expect(find.text('Sudah versi terbaru'), findsOneWidget);

    source.offline = true;
    await tester.tap(find.text('Cek lagi'));
    await _settle(tester);
    expect(
      find.text('Tidak bisa memeriksa: tidak ada internet.'),
      findsOneWidget,
    );
  });

  testWidgets('kartu, dialog, dan Tentang aplikasi tidak terpotong di 130%', (
    tester,
  ) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = await pump(tester, beranda(), textScale: 1.3);
    await c.read(updateControllerProvider.notifier).check();
    await _settle(tester);
    await tester.tap(find.text('Lihat'));
    await _settle(tester);
    expect(find.text('Unduh dan pasang'), findsOneWidget);

    // Aplikasi baru, supaya dialog sebelumnya tidak ikut terbawa.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, const AboutScreen(), textScale: 1.3);
    await tester.tap(find.text('Cek pembaruan'));
    await _settle(tester);
    expect(find.text('Lihat'), findsOneWidget);
  });
}
