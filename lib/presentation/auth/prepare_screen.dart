import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/sync/sync_engine.dart';
import '../../services/sync_controller.dart';
import '../common/brand_marks.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'account_dialogs.dart';

enum _Mode { checking, newAccount, download, upload, merge, overwrite }

/// Menyiapkan data setelah masuk (FR-10.13, mockup `Menyiapkan`): unduh,
/// unggah, gabung, atau langsung ke onboarding untuk akun baru.
class PrepareScreen extends ConsumerStatefulWidget {
  const PrepareScreen({super.key});

  @override
  ConsumerState<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends ConsumerState<PrepareScreen> {
  static final _number = NumberFormat.decimalPattern('id');

  var _mode = _Mode.checking;
  LinkProgress? _progress;
  var _done = false;
  var _failed = false;

  SyncController get _controller => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _mode = _Mode.checking;
      _progress = null;
      _failed = false;
      _done = false;
    });
    final bool ok;
    if (await _controller.overwritePending()) {
      setState(() => _mode = _Mode.overwrite);
      ok = await _controller.overwrite(onProgress: _onProgress);
    } else {
      final check = await _controller.inspect();
      if (!mounted) return;
      if (check == null) {
        setState(() => _failed = true);
        return;
      }
      LinkChoice? choice;
      if (check.plan == LinkPlan.choose) {
        choice = await showDialog<LinkChoice>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LinkChoiceDialog(check: check),
        );
        if (choice == null) {
          // Batal dan keluar: kembali ke layar Masuk, data HP tetap.
          await _controller.cancelLink();
          return;
        }
      }
      if (!mounted) return;
      setState(
        () => _mode = switch (check.plan) {
          LinkPlan.upload when check.local.isEmpty => _Mode.newAccount,
          LinkPlan.upload => _Mode.upload,
          LinkPlan.download => _Mode.download,
          LinkPlan.rejoin => _Mode.merge,
          LinkPlan.choose =>
            choice == LinkChoice.replace ? _Mode.download : _Mode.merge,
        },
      );
      ok = await _controller.link(
        check,
        choice: choice,
        onProgress: _onProgress,
      );
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _failed = true);
      return;
    }
    // Akun baru: langsung ke onboarding lewat Beranda (FR-8.4).
    if (_mode == _Mode.newAccount) {
      context.go('/beranda');
      return;
    }
    setState(() => _done = true);
  }

  void _onProgress(LinkProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncControllerProvider);
    final user = status.user;
    final (title, subtitle) = _texts();
    final progress = _progress;
    final working = !_done && !_failed;
    final showBar =
        working &&
        progress != null &&
        progress.total > 0 &&
        _mode != _Mode.newAccount;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 56,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user != null)
                      _AccountRow(email: user.email ?? user.name),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: const CupcakeMark(size: 60),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (showBar) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 10,
                          backgroundColor: AppColors.surfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_number.format(progress.done)} dari '
                              '${_number.format(progress.total)} data',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          Text(
                            '${(progress.fraction * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ] else if (working)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: const LinearProgressIndicator(
                          minHeight: 10,
                          backgroundColor: AppColors.surfaceMuted,
                        ),
                      ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    if (working)
                      const InfoBox(
                        'Jangan tutup aplikasi dan tetap tersambung internet '
                        'sampai selesai. Setelah itu aplikasi bisa dipakai '
                        'tanpa internet.',
                      ),
                    if (_failed) ...[
                      InfoBox(
                        status.error ?? 'Gagal menyiapkan data.',
                        kind: StatusKind.danger,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: pillFilled(height: 52),
                        onPressed: _start,
                        child: const Text('Coba lagi'),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        style: quietButton,
                        onPressed: _controller.cancelLink,
                        child: const Text('Keluar, pakai akun lain'),
                      ),
                    ],
                    if (_done)
                      FilledButton(
                        style: pillFilled(height: 52),
                        onPressed: () => context.go('/beranda'),
                        child: const Text('Mulai pakai'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, String) _texts() {
    final uploading = _progress?.phase == LinkPhase.upload;
    if (_failed) {
      return ('Data belum siap', 'Periksa internet lalu coba lagi.');
    }
    return switch (_mode) {
      _Mode.checking => ('Memeriksa data di akunmu', 'Sebentar…'),
      _Mode.newAccount => (
        'Menyiapkan akunmu',
        'Setelah ini isi profil usaha dan menu pertamamu.',
      ),
      _Mode.download when _done => (
        'Data usahamu siap',
        'Bahan, menu, pesanan, dan laporan dari akunmu sudah ada di HP ini. '
            'Pengingat pesanan dijadwalkan ulang.',
      ),
      _Mode.download => (
        'Mengunduh data usahamu',
        'Akun ini sudah berisi data. Bahan, menu, pesanan, dan laporan '
            'dipindahkan ke HP ini.',
      ),
      _Mode.upload when _done => (
        'Data tersimpan di akunmu',
        'Mulai sekarang setiap perubahan otomatis tersinkron.',
      ),
      _Mode.upload => (
        'Mengunggah data HP ini',
        'HP ini berisi data dari versi sebelum ada akun. Datanya disalin ke '
            'akunmu supaya aman.',
      ),
      _Mode.merge when _done => (
        'Data sudah digabung',
        'Data HP ini dan data akunmu kini sama di semua HP.',
      ),
      _Mode.merge => (
        uploading ? 'Mengunggah data HP ini' : 'Mengunduh data akunmu',
        'Data HP ini dan data akunmu digabung.',
      ),
      _Mode.overwrite when _done => (
        'Isi akun sudah diganti',
        'Akunmu kini berisi data dari backup yang dipulihkan.',
      ),
      _Mode.overwrite => (
        'Mengganti isi akun dengan backup',
        'Backup yang baru dipulihkan menjadi isi akunmu, supaya tidak '
            'tertimpa lagi saat sinkron.',
      ),
    };
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final label = email ?? 'Akun Google';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              String.fromCharCode(label.runes.first).toUpperCase(),
              style: const TextStyle(
                color: AppColors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masuk sebagai',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
