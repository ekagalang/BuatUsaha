import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_engine.dart';
import '../../services/sync_controller.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

/// Pengaturan → Akun dan sinkron (PRD 5.10, mockup `AkunData`).
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  SyncController get _controller => ref.read(syncControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Akun dan sinkron'),
        const SizedBox(height: 10),
        _Panel(
          child: status.user == null
              ? _LoggedOut(status: status, onSignIn: _signIn)
              : _LoggedIn(
                  status: status,
                  onSync: _syncNow,
                  onSignOut: _signOut,
                ),
        ),
      ],
    );
  }

  Future<void> _signIn() async => _finishConnect(await _controller.signIn());

  Future<void> _syncNow() async {
    final wasLinked = ref.read(syncControllerProvider).linked;
    await _finishConnect(await _controller.syncNow(), quiet: wasLinked);
  }

  /// Dialog pilihan bila akun sudah berisi data lain (FR-10.5), lalu hasil.
  Future<void> _finishConnect(LinkCheck? check, {bool quiet = false}) async {
    if (!mounted) return;
    if (check != null) {
      final choice = await showDialog<LinkChoice>(
        context: context,
        builder: (_) => _LinkDialog(check: check),
      );
      if (choice == null) {
        await _controller.cancelLink();
        return;
      }
      await _controller.link(check, choice);
    }
    if (!mounted) return;
    final status = ref.read(syncControllerProvider);
    final message =
        status.error ??
        (status.linked
            ? quiet
                  ? 'Tersinkron.'
                  : 'Masuk sebagai ${status.user?.email ?? status.user?.name}. '
                        'Data tersinkron.'
            : null);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _signOut() async {
    final pending = ref.read(pendingChangesProvider).value ?? 0;
    final wipe = await showDialog<bool>(
      context: context,
      builder: (_) => _SignOutDialog(pending: pending),
    );
    if (wipe == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _controller.signOut(wipe: wipe);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wipe
              ? 'Keluar dari akun. Data di HP ini dihapus; di akun tetap ada.'
              : 'Keluar dari akun. Data tetap di HP ini.',
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

const _pill = StadiumBorder();

class _LoggedOut extends StatelessWidget {
  const _LoggedOut({required this.status, required this.onSignIn});

  final SyncStatus status;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Simpan salinan data di akun Google-mu. Aplikasi tetap jalan tanpa '
          'internet; kalau HP hilang atau ganti HP, tinggal masuk dan datanya '
          'kembali.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: _pill,
            foregroundColor: AppColors.text,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: status.available && !status.busy ? onSignIn : null,
          icon: status.busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_outline, color: AppColors.primary),
          label: const Text('Masuk dengan Google'),
        ),
        const SizedBox(height: 12),
        Text(
          status.available
              ? 'Gratis. Data hanya bisa dibuka oleh akunmu sendiri.'
              : 'Belum bisa dipakai di versi ini: Firebase belum dipasang.',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (status.error != null) ...[
          const SizedBox(height: 12),
          InfoBox(status.error!, kind: StatusKind.danger),
        ],
      ],
    );
  }
}

class _LoggedIn extends ConsumerWidget {
  const _LoggedIn({
    required this.status,
    required this.onSync,
    required this.onSignOut,
  });

  final SyncStatus status;
  final VoidCallback onSync;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = status.user!;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final lastSync = ref.watch(lastSyncProvider).value;
    final synced = status.linked && pending == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                user.initial,
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
                  Text(
                    user.name ?? user.email ?? 'Akun Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Huruf besar: pill boleh turun ke dua baris, bukan meluap.
            Flexible(
              child: StatusPill(
                synced ? 'Tersinkron' : 'Belum terkirim',
                kind: synced ? StatusKind.success : StatusKind.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Stat(
                label: 'Sinkron terakhir',
                value: lastSync == null ? 'Belum pernah' : _when(lastSync),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'Menunggu dikirim',
                value: pending == 0 ? 'Tidak ada' : '$pending perubahan',
              ),
            ),
          ],
        ),
        if (status.error != null) ...[
          const SizedBox(height: 12),
          InfoBox(status.error!, kind: StatusKind.danger),
        ],
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: _pill,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: status.busy ? null : onSync,
          child: Text(status.busy ? 'Menyinkron…' : 'Sinkron sekarang'),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppColors.danger,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: status.busy ? null : onSignOut,
          child: const Text('Keluar dari akun'),
        ),
      ],
    );
  }

  /// "Hari ini 14.32", "Kemarin 08.10", "18 Okt 14.32".
  static String _when(DateTime at) {
    final local = at.toLocal();
    final days = DateUtils.dateOnly(DateTime.now())
        .difference(DateUtils.dateOnly(local))
        .inDays;
    final day = switch (days) {
      0 => 'Hari ini',
      1 => 'Kemarin',
      _ => formatShortDate(local),
    };
    return '$day ${formatTime(local)}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Kerangka dialog mockup `AkunData`: judul Fraunces, teks, tombol bertumpuk.
class _StackedDialog extends StatelessWidget {
  const _StackedDialog({
    required this.title,
    required this.message,
    required this.buttons,
  });

  final String title;
  final String message;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            for (final b in buttons) ...[const SizedBox(height: 12), b],
          ],
        ),
      ),
    );
  }
}

ButtonStyle _filled({Color? background}) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(48),
  shape: _pill,
  backgroundColor: background,
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
);

ButtonStyle _outlined({Color color = AppColors.primary}) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: _pill,
      foregroundColor: color,
      side: BorderSide(color: color),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

ButtonStyle get _quiet => TextButton.styleFrom(
  minimumSize: const Size.fromHeight(44),
  foregroundColor: AppColors.textMuted,
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
);

/// "Akun ini sudah berisi data" (FR-10.5).
class _LinkDialog extends StatelessWidget {
  const _LinkDialog({required this.check});

  final LinkCheck check;

  @override
  Widget build(BuildContext context) {
    final local = check.local;
    final parts = [
      if (local.ingredients > 0) '${local.ingredients} bahan',
      if (local.products > 0) '${local.products} menu',
      if (local.orders > 0) '${local.orders} pesanan',
    ];
    final here = parts.isEmpty
        ? 'HP ini juga sudah berisi data.'
        : 'Di HP ini ada ${_joinAnd(parts)}.';
    final remoteAt = check.remoteUpdatedAt;
    return _StackedDialog(
      title: 'Akun ini sudah berisi data',
      message:
          'Data dari HP lain ada di akun ini'
          '${remoteAt == null ? '' : ' (sinkron terakhir ${formatShortDate(remoteAt)})'}'
          '. $here',
      buttons: [
        FilledButton(
          style: _filled(),
          onPressed: () => Navigator.pop(context, LinkChoice.merge),
          child: const Text('Gabungkan keduanya'),
        ),
        OutlinedButton(
          style: _outlined(),
          onPressed: () => Navigator.pop(context, LinkChoice.replace),
          child: const Text(
            'Pakai data akun (data HP ini dicadangkan ke file dulu)',
            textAlign: TextAlign.center,
          ),
        ),
        TextButton(
          style: _quiet,
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }

  static String _joinAnd(List<String> parts) => switch (parts.length) {
    1 => parts.single,
    2 => '${parts.first} dan ${parts.last}',
    _ => '${parts.sublist(0, parts.length - 1).join(', ')}, dan ${parts.last}',
  };
}

/// Keluar akun: data tetap di HP atau dihapus dari HP (FR-10.8). Hasil
/// `true` = hapus.
class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    return _StackedDialog(
      title: 'Keluar dari akun?',
      message:
          'Sinkron berhenti; data di akun tetap aman dan bisa diunduh lagi '
          'dengan masuk ke akun yang sama.'
          '${pending == 0 ? '' : ' $pending perubahan yang belum terkirim akan dicoba dikirim dulu.'}',
      buttons: [
        FilledButton(
          style: _filled(),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keluar, data tetap di HP'),
        ),
        OutlinedButton(
          style: _outlined(color: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Keluar dan hapus data dari HP ini',
            textAlign: TextAlign.center,
          ),
        ),
        TextButton(
          style: _quiet,
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
