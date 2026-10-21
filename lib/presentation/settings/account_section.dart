import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync_controller.dart';
import '../auth/account_dialogs.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../theme.dart';

/// Pengaturan → Akun dan sinkron (PRD 5.10, mockup `AkunData`). Masuk wajib
/// di awal (FR-10.1), jadi bagian ini selalu menampilkan akun yang masuk.
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
        // Akun hilang sesaat saat keluar, sebelum router pindah ke Masuk.
        if (status.user != null)
          _Panel(
            child: _LoggedIn(
              status: status,
              onSync: _syncNow,
              onSignOut: _signOut,
            ),
          ),
      ],
    );
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    await _controller.syncNow();
    if (!mounted) return;
    final error = ref.read(syncControllerProvider).error;
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Tersinkron.')));
  }

  /// Keluar akun (FR-10.8): perubahan tertunda dikirim dulu, lalu dialog
  /// konfirmasi; data usaha dan backup otomatis dihapus dari HP ini.
  Future<void> _signOut() async {
    final messenger = ScaffoldMessenger.of(context);
    final unsent = await _controller.flushBeforeSignOut();
    if (!mounted) return;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (_) => SignOutDialog(unsent: unsent),
    );
    if (ok != true) return;
    await _controller.signOut();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Keluar dari akun. Data di HP ini dihapus; di akun tetap aman.',
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
            shape: pillShape,
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
