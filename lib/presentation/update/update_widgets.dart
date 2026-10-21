import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_updates.dart';
import '../../services/update_controller.dart';
import '../auth/account_dialogs.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../theme.dart';

/// Kartu "Versi baru tersedia" di Beranda (FR-11.4, mockup `VersiBaru`).
/// Juga membuka dialog pembaruan saat notifikasi pembaruan diketuk.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(updateControllerProvider.select((s) => s.dialogRequests), (
      _,
      _,
    ) {
      if (ref.read(updateControllerProvider).hasUpdate) {
        showUpdateDialog(context, ref);
      }
    });
    final status = ref.watch(updateControllerProvider);
    final latest = status.latest;
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.enter,
      alignment: Alignment.topCenter,
      child: !status.showCard || latest == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward,
                        size: 20,
                        color: AppColors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Versi ${latest.version} tersedia',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _summary(latest),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: pillFilled(height: 40, expand: false),
                      onPressed: () => showUpdateDialog(context, ref),
                      child: const Text('Lihat'),
                    ),
                    IconButton(
                      tooltip: 'Sembunyikan sampai versi berikutnya',
                      onPressed: () =>
                          ref.read(updateControllerProvider.notifier).dismiss(),
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  static String _summary(ReleaseInfo latest) {
    final parts = [
      if (latest.notes.isNotEmpty) '${latest.notes.length} perubahan',
      if (latest.assets.isNotEmpty) formatMegabytes(latest.assets.first.size),
    ];
    return parts.isEmpty ? 'Ketuk Lihat untuk memasang' : parts.join(' · ');
  }
}

Future<void> showUpdateDialog(BuildContext context, WidgetRef ref) async {
  final status = ref.read(updateControllerProvider);
  final latest = status.latest;
  if (latest == null) return;
  await showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(
      release: latest,
      installedVersion: status.installed?.versionName,
    ),
  );
}

enum _Stage { info, downloading, permission, ready, failed }

/// Dialog pembaruan (FR-11.4): info → mengunduh → izin pertama kali →
/// siap dipasang, atau gagal.
class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.release, this.installedVersion});

  final ReleaseInfo release;
  final String? installedVersion;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  var _stage = _Stage.info;
  var _received = 0;
  var _total = 0;
  var _cancelled = false;
  var _awaitingPermission = false;
  File? _file;
  ReleaseAsset? _asset;
  String? _error;
  AppLifecycleListener? _lifecycle;

  AppPlatform get _platform => ref.read(appPlatformProvider);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _afterSettings);
  }

  @override
  void dispose() {
    _cancelled = true;
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.downloading;
      _received = 0;
      _total = widget.release.assets.firstOrNull?.size ?? 0;
      _cancelled = false;
      _error = null;
    });
    try {
      final asset =
          _asset ?? widget.release.assetFor(await _platform.supportedAbis());
      if (asset == null) {
        throw const FileSystemException('APK tidak ada di rilis ini');
      }
      _asset = asset;
      final file = await ref
          .read(updateDownloaderProvider)
          .download(
            asset,
            cancelled: () => _cancelled,
            onProgress: (received, total) {
              if (mounted) {
                setState(() {
                  _received = received;
                  _total = total;
                });
              }
            },
          );
      if (!mounted) return;
      _file = file;
      Haptics.success();
      await _install();
    } on UpdateCancelled {
      if (mounted) setState(() => _stage = _Stage.info);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = _received > 0
            ? 'Koneksi terputus di ${formatMegabytes(_received)}. Unduhan '
                  'bisa diulang.'
            : 'Unduhan gagal. Periksa internet lalu coba lagi.';
      });
    }
  }

  /// Penginstal Android butuh izin "pasang dari sumber ini" sekali.
  Future<void> _install() async {
    if (!await _platform.canInstallPackages()) {
      if (mounted) setState(() => _stage = _Stage.permission);
      return;
    }
    if (mounted) setState(() => _stage = _Stage.ready);
    await _openInstaller();
  }

  Future<void> _openInstaller() async {
    final file = _file;
    if (file == null) return;
    try {
      await _platform.installApk(file.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = 'Penginstal Android tidak bisa dibuka.';
        });
      }
    }
  }

  Future<void> _openSettings() async {
    _awaitingPermission = true;
    await _platform.openInstallSettings();
  }

  /// Kembali dari pengaturan izin: pemasangan lanjut otomatis.
  Future<void> _afterSettings() async {
    if (!_awaitingPermission || !mounted) return;
    if (await _platform.canInstallPackages()) {
      _awaitingPermission = false;
      if (mounted) setState(() => _stage = _Stage.ready);
      await _openInstaller();
    }
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final size = release.assets.firstOrNull?.size;
    final title = switch (_stage) {
      _Stage.info => 'Versi ${release.version} tersedia',
      _Stage.downloading => 'Mengunduh versi ${release.version}',
      _Stage.permission => 'Izinkan pemasangan',
      _Stage.ready => 'Siap dipasang',
      _Stage.failed => 'Unduhan gagal',
    };
    return StackedDialog(
      title: title,
      message: switch (_stage) {
        _Stage.info =>
          '${widget.installedVersion == null ? '' : 'Kamu memakai versi ${widget.installedVersion}. '}'
              '${size == null || size == 0 ? '' : 'Ukuran unduhan ${formatMegabytes(size)}. '}'
              'Data usahamu tetap aman.',
        _Stage.downloading =>
          'Tetap tersambung internet. Jangan tutup aplikasi sampai selesai.',
        _Stage.permission =>
          'Android perlu izin sekali supaya BuatUsaha bisa memasang '
              'pembaruannya sendiri.',
        _Stage.ready =>
          'Penginstal Android terbuka. Ketuk Perbarui; aplikasi tertutup '
              'sebentar lalu bisa dibuka lagi dengan data yang sama.',
        _Stage.failed => _error ?? 'Unduhan gagal.',
      },
      body: switch (_stage) {
        _Stage.info when release.notes.isNotEmpty => _Notes(release.notes),
        _Stage.downloading => _Progress(received: _received, total: _total),
        _Stage.permission => const _Steps(),
        _ => null,
      },
      buttons: [
        ...switch (_stage) {
          _Stage.info => [
            FilledButton(
              style: pillFilled(),
              onPressed: _download,
              child: const Text('Unduh dan pasang'),
            ),
            TextButton(
              style: quietButton,
              onPressed: _close,
              child: const Text('Nanti'),
            ),
          ],
          _Stage.downloading => [
            TextButton(
              style: quietButton,
              onPressed: () => _cancelled = true,
              child: const Text('Batal'),
            ),
          ],
          _Stage.permission => [
            FilledButton(
              style: pillFilled(),
              onPressed: _openSettings,
              child: const Text('Buka pengaturan'),
            ),
            TextButton(
              style: quietButton,
              onPressed: _close,
              child: const Text('Nanti'),
            ),
          ],
          _Stage.ready => [
            FilledButton(
              style: pillFilled(),
              onPressed: _openInstaller,
              child: const Text('Pasang sekarang'),
            ),
            TextButton(
              style: quietButton,
              onPressed: _close,
              child: const Text('Tutup'),
            ),
          ],
          _Stage.failed => [
            FilledButton(
              style: pillFilled(),
              onPressed: _download,
              child: const Text('Coba lagi'),
            ),
            OutlinedButton(
              style: pillOutlined(),
              onPressed: () =>
                  _platform.openUrl(_asset?.url ?? release.pageUrl),
              child: const Text('Unduh lewat browser'),
            ),
            TextButton(
              style: quietButton,
              onPressed: _close,
              child: const Text('Nanti'),
            ),
          ],
        },
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes(this.notes);

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    const shown = 6;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yang baru',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final note in notes.take(shown))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $note',
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          if (notes.length > shown)
            Text(
              'dan ${notes.length - shown} perubahan lain',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.received, required this.total});

  final int received;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? null : (received / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 10,
            backgroundColor: AppColors.surfaceMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                total == 0
                    ? formatMegabytes(received)
                    : '${formatMegabytes(received)} dari ${formatMegabytes(total)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            if (fraction != null)
              Text(
                '${(fraction * 100).round()}%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, height: 1.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1. Ketuk Buka pengaturan.', style: style),
          SizedBox(height: 4),
          Text('2. Nyalakan Izinkan dari sumber ini.', style: style),
          SizedBox(height: 4),
          Text(
            '3. Kembali ke BuatUsaha; pemasangan lanjut otomatis.',
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Status cek pembaruan untuk Tentang aplikasi.
class UpdateCheckPanel extends ConsumerWidget {
  const UpdateCheckPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final latest = status.latest;
    final last = status.lastCheckedAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.medium),
        child: switch (status.check) {
          UpdateCheck.checking => const Row(
            key: ValueKey('checking'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'Memeriksa…',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          UpdateCheck.done when status.hasUpdate && latest != null => Row(
            key: const ValueKey('new'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versi ${latest.version} tersedia',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      UpdateCard._summary(latest),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: pillFilled(height: 40, expand: false),
                onPressed: () => showUpdateDialog(context, ref),
                child: const Text('Lihat'),
              ),
            ],
          ),
          UpdateCheck.done => Column(
            key: const ValueKey('latest'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Flexible(
                    child: StatusPill(
                      'Sudah versi terbaru',
                      kind: StatusKind.success,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Dicek barusan',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
              TextButton(
                onPressed: controller.check,
                child: const Text('Cek lagi'),
              ),
            ],
          ),
          UpdateCheck.failed => Column(
            key: const ValueKey('failed'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoBox(
                'Tidak bisa memeriksa: tidak ada internet.',
                kind: StatusKind.danger,
              ),
              TextButton(
                onPressed: controller.check,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
          UpdateCheck.idle => Column(
            key: const ValueKey('idle'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                style: pillOutlined(),
                onPressed: controller.check,
                child: const Text('Cek pembaruan'),
              ),
              if (last != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Terakhir dicek ${_when(last)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        },
      ),
    );
  }

  static String _when(DateTime at) {
    final local = at.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final days = today.difference(DateUtils.dateOnly(local)).inDays;
    final day = switch (days) {
      0 => 'hari ini',
      1 => 'kemarin',
      _ => formatShortDate(local),
    };
    return '$day ${formatTime(local)}';
  }
}
