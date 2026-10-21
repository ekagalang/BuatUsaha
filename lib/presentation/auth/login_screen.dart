import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync_controller.dart';
import '../common/brand_marks.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'account_dialogs.dart';

/// Layar Masuk (FR-10.1, FR-10.12, mockup `Masuk`): satu-satunya jalan ke
/// aplikasi bila belum ada akun yang masuk.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final error = status.available
        ? status.error
        : 'Versi aplikasi ini belum tersambung ke Firebase. Pasang versi '
              'terbaru.';
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: const CupcakeMark(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'BuatUsaha',
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Hitung HPP, catat stok bahan, pesanan, dan untung-rugi '
                      'harian usaha rumahanmu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const _Benefit(
                      Icons.calculate_outlined,
                      'HPP per pcs otomatis dari resep',
                    ),
                    const SizedBox(height: 12),
                    const _Benefit(
                      Icons.layers_outlined,
                      'Stok bahan dan nilai modal selalu terkini',
                    ),
                    const SizedBox(height: 12),
                    const _Benefit(
                      Icons.cloud_done_outlined,
                      'Data aman di akun Google, bisa pindah HP',
                    ),
                    const Spacer(),
                    const SizedBox(height: 32),
                    if (error != null) ...[
                      InfoBox(error, kind: StatusKind.danger),
                      const SizedBox(height: 12),
                    ],
                    status.busy
                        ? const _Connecting()
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: pillShape,
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.text,
                              side: const BorderSide(
                                color: AppColors.inputBorder,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: status.available
                                ? () => ref
                                      .read(syncControllerProvider.notifier)
                                      .signIn()
                                : null,
                            icon: const GoogleMark(),
                            label: const Text('Masuk dengan Google'),
                          ),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum punya akun? Cukup masuk dengan Google, akunmu '
                      'dibuat otomatis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Legal(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
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
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Flexible(
            child: Text(
              'Menghubungkan ke Google…',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ketentuan layanan dan Kebijakan privasi: halamannya disiapkan sebelum
/// aplikasi dikomersialkan (PRD 5.10).
class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    void soon(String page) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$page disiapkan sebelum aplikasi dikomersialkan.'),
      ),
    );
    const muted = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: AppColors.textMuted,
    );
    const link = TextStyle(
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
      decoration: TextDecoration.underline,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        const Text('Dengan masuk, kamu menyetujui ', style: muted),
        GestureDetector(
          onTap: () => soon('Ketentuan layanan'),
          child: const Text('Ketentuan layanan', style: link),
        ),
        const Text(' dan ', style: muted),
        GestureDetector(
          onTap: () => soon('Kebijakan privasi'),
          child: const Text('Kebijakan privasi', style: link),
        ),
        const Text('.', style: muted),
      ],
    );
  }
}
