import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/services/app_updates.dart';
import 'package:buat_usaha/services/notification_scheduler.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/fake_updates.dart';

void main() {
  group('AppVersion', () {
    test('dibaca dari tag dan nama versi', () {
      expect(AppVersion.tryParse('v1.2.0').toString(), '1.2.0');
      expect(AppVersion.tryParse('1.2.0+57').toString(), '1.2.0');
      expect(AppVersion.tryParse('bukan versi'), isNull);
    });

    test('dibandingkan per angka', () {
      final v = AppVersion.tryParse;
      expect(v('1.10.0')! > v('1.9.0')!, isTrue);
      expect(v('2.0.0')! > v('1.99.99')!, isTrue);
      expect(v('1.0.1')! > v('1.0.0')!, isTrue);
      expect(v('1.0.0')! > v('1.0.0')!, isFalse);
    });
  });

  group('ReleaseInfo', () {
    Map<String, dynamic> json({bool draft = false}) => {
      'tag_name': 'v1.1.0',
      'draft': draft,
      'prerelease': false,
      'html_url': 'https://github.com/ekagalang/BuatUsaha/releases/tag/v1.1.0',
      'published_at': '2026-10-28T02:00:00Z',
      'body': '- Daftar belanja otomatis\n- Bagikan ke WhatsApp\n* Perbaikan stok\n\nBuild 57\n',
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          {
            'name': 'BuatUsaha-1.1.0-$abi.apk',
            'browser_download_url': 'https://contoh/$abi.apk',
            'size': 27000000,
          },
        {'name': 'catatan.txt', 'browser_download_url': 'x', 'size': 1},
      ],
    };

    test('poin perubahan dan APK dibaca dari rilis GitHub', () {
      final info = ReleaseInfo.fromJson(json())!;
      expect(info.version.toString(), '1.1.0');
      expect(info.notes, [
        'Daftar belanja otomatis',
        'Bagikan ke WhatsApp',
        'Perbaikan stok',
      ]);
      expect(info.assets, hasLength(3));
      expect(info.publishedAt, DateTime.utc(2026, 10, 28, 2));
    });

    test('APK dipilih sesuai jenis HP, arm64 sebagai cadangan', () {
      final info = ReleaseInfo.fromJson(json())!;
      expect(
        info.assetFor(['arm64-v8a', 'armeabi-v7a'])!.name,
        endsWith('arm64-v8a.apk'),
      );
      expect(
        info.assetFor(['armeabi-v7a', 'armeabi'])!.name,
        endsWith('armeabi-v7a.apk'),
      );
      expect(info.assetFor(['mips'])!.name, endsWith('arm64-v8a.apk'));
    });

    test('rilis draf diabaikan', () {
      expect(ReleaseInfo.fromJson(json(draft: true)), isNull);
    });
  });

  group('UpdateDownloader', () {
    late HttpServer server;
    late Directory cache;
    final bytes = List<int>.generate(300000, (i) => i % 256);

    setUp(() async {
      cache = Directory.systemTemp.createTempSync('pembaruan');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.contentLength = bytes.length;
        for (var i = 0; i < bytes.length; i += 65536) {
          request.response.add(
            bytes.sublist(i, (i + 65536).clamp(0, bytes.length)),
          );
          await request.response.flush();
          // Tanpa jeda, loopback di Linux (CI) bisa menggabungkan semua
          // potongan jadi satu, sehingga progres hanya terlapor sekali.
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      cache.deleteSync(recursive: true);
    });

    ReleaseAsset asset() => ReleaseAsset(
      name: 'BuatUsaha-1.1.0-arm64-v8a.apk',
      url: 'http://127.0.0.1:${server.port}/apk',
      size: bytes.length,
    );

    test(
      'mengunduh dengan progres lalu memakai file yang sudah lengkap',
      () async {
        final downloader = UpdateDownloader(cacheDir: () async => cache);
        final progress = <int>[];
        final file = await downloader.download(
          asset(),
          cancelled: () => false,
          onProgress: (received, _) => progress.add(received),
        );
        expect(file.lengthSync(), bytes.length);
        expect(progress.last, bytes.length);
        expect(progress.length, greaterThan(1));

        final again = <int>[];
        await downloader.download(
          asset(),
          cancelled: () => false,
          onProgress: (received, _) => again.add(received),
        );
        expect(again, [bytes.length]);
      },
    );

    test('dibatalkan: file setengah jadi dihapus', () async {
      final downloader = UpdateDownloader(cacheDir: () async => cache);
      await expectLater(
        downloader.download(
          asset(),
          cancelled: () => true,
          onProgress: (_, _) {},
        ),
        throwsA(isA<UpdateCancelled>()),
      );
      final left = Directory('${cache.path}/updates').listSync();
      expect(left, isEmpty);
    });
  });

  group('notifikasi latar', () {
    test('sekali per versi baru', () async {
      final store = MemoryStore();
      final notifications = RecordingNotifications();
      Future<void> run(ReleaseSource source) => notifyIfUpdateAvailable(
        platform: FakeAppPlatform(),
        source: source,
        store: store,
        notifications: notifications,
      );

      await run(FakeReleaseSource(release('v1.0.0')));
      expect(notifications.shown, isEmpty);

      await run(FakeReleaseSource(release('v1.1.0')));
      await run(FakeReleaseSource(release('v1.1.0')));
      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, 'Versi 1.1.0 tersedia');
      expect(notifications.shown.single.payload, 'update');
      expect(notifications.shown.single.channel, NotifyChannel.updates);

      await run(FakeReleaseSource(release('v1.2.0')));
      expect(notifications.shown, hasLength(2));
    });
  });

  group('UpdateController', () {
    ProviderContainer container(FakeReleaseSource source, MemoryStore store) {
      final c = ProviderContainer(
        overrides: [
          appPlatformProvider.overrideWithValue(FakeAppPlatform()),
          releaseSourceProvider.overrideWithValue(source),
          keyValueStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('cek menemukan versi baru; tutup kartu disimpan', () async {
      final source = FakeReleaseSource(release('v1.1.0'));
      final store = MemoryStore();
      final c = container(source, store);
      final controller = c.read(updateControllerProvider.notifier);

      await controller.check();
      var status = c.read(updateControllerProvider);
      expect(status.check, UpdateCheck.done);
      expect(status.hasUpdate, isTrue);
      expect(status.showCard, isTrue);

      await controller.dismiss();
      status = c.read(updateControllerProvider);
      expect(status.showCard, isFalse);
      expect(store.values[UpdateKeys.dismissed], 'v1.1.0');
    });

    test('tidak dicek ulang sebelum 6 jam', () async {
      final source = FakeReleaseSource(release('v1.0.0'));
      final store = MemoryStore()
        ..values[UpdateKeys.lastCheck] = DateTime.now()
            .subtract(const Duration(hours: 2))
            .toIso8601String();
      final c = container(source, store);
      await c.read(updateControllerProvider.notifier).checkIfDue();
      expect(source.calls, 0);

      store.values[UpdateKeys.lastCheck] = DateTime.now()
          .subtract(const Duration(hours: 7))
          .toIso8601String();
      final c2 = container(source, store);
      await c2.read(updateControllerProvider.notifier).checkIfDue();
      expect(source.calls, 1);
      expect(c2.read(updateControllerProvider).hasUpdate, isFalse);
    });

    test('tanpa internet: status gagal', () async {
      final source = FakeReleaseSource(release('v1.1.0'))..offline = true;
      final c = container(source, MemoryStore());
      await c.read(updateControllerProvider.notifier).check();
      expect(c.read(updateControllerProvider).check, UpdateCheck.failed);
    });
  });
}
