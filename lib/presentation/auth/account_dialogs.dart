import 'package:flutter/material.dart';

import '../../data/sync/sync_engine.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

const pillShape = StadiumBorder();

ButtonStyle pillFilled({Color? background, double height = 48}) =>
    FilledButton.styleFrom(
      minimumSize: Size.fromHeight(height),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: pillShape,
      backgroundColor: background,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

ButtonStyle pillOutlined({Color color = AppColors.primary}) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: pillShape,
      foregroundColor: color,
      side: BorderSide(color: color),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

ButtonStyle get quietButton => TextButton.styleFrom(
  minimumSize: const Size.fromHeight(44),
  foregroundColor: AppColors.textMuted,
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
);

/// Kerangka dialog mockup `AkunData`: judul Fraunces, teks, tombol bertumpuk.
class StackedDialog extends StatelessWidget {
  const StackedDialog({
    super.key,
    required this.title,
    required this.message,
    required this.buttons,
    this.warning,
  });

  final String title;
  final String message;
  final String? warning;
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
            if (warning != null) ...[
              const SizedBox(height: 12),
              InfoBox(warning!),
            ],
            for (final b in buttons) ...[const SizedBox(height: 12), b],
          ],
        ),
      ),
    );
  }
}

/// "Akun ini sudah berisi data" (FR-10.5, mockup `Menyiapkan`). `null` =
/// batal dan keluar.
class LinkChoiceDialog extends StatelessWidget {
  const LinkChoiceDialog({super.key, required this.check});

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
        : 'Di HP ini ada ${joinAnd(parts)}.';
    final remoteAt = check.remoteUpdatedAt;
    return StackedDialog(
      title: 'Akun ini sudah berisi data',
      message:
          'Data dari HP lain ada di akun ini'
          '${remoteAt == null ? '' : ' (sinkron terakhir ${formatShortDate(remoteAt)})'}'
          '. $here',
      buttons: [
        FilledButton(
          style: pillFilled(),
          onPressed: () => Navigator.pop(context, LinkChoice.merge),
          child: const Text('Gabungkan keduanya'),
        ),
        OutlinedButton(
          style: pillOutlined(),
          onPressed: () => Navigator.pop(context, LinkChoice.replace),
          child: const Text(
            'Pakai data akun (data HP ini dicadangkan ke file dulu)',
            textAlign: TextAlign.center,
          ),
        ),
        TextButton(
          style: quietButton,
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal dan keluar'),
        ),
      ],
    );
  }
}

/// "6 bahan, 2 menu, dan 14 pesanan".
String joinAnd(List<String> parts) => switch (parts.length) {
  0 => '',
  1 => parts.single,
  2 => '${parts.first} dan ${parts.last}',
  _ => '${parts.sublist(0, parts.length - 1).join(', ')}, dan ${parts.last}',
};

/// Keluar akun (FR-10.8, mockup `AkunData`): data usaha dan backup otomatis
/// dihapus dari HP. [unsent] = perubahan yang tetap belum terkirim setelah
/// dicoba dikirim. Hasil `true` = keluar.
class SignOutDialog extends StatelessWidget {
  const SignOutDialog({super.key, required this.unsent});

  final int unsent;

  @override
  Widget build(BuildContext context) {
    return StackedDialog(
      title: 'Keluar dari akun?',
      message:
          'Data usaha dan backup otomatis akan dihapus dari HP ini. Data di '
          'akun tetap aman dan kembali saat kamu masuk lagi dengan akun yang '
          'sama.',
      warning: unsent == 0
          ? null
          : 'Ada $unsent perubahan yang belum terkirim karena tidak ada '
                'internet. Kalau keluar sekarang, perubahan itu hilang.',
      buttons: [
        FilledButton(
          style: pillFilled(background: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            unsent == 0
                ? 'Keluar dan hapus data dari HP ini'
                : 'Keluar tanpa mengirim perubahan',
            textAlign: TextAlign.center,
          ),
        ),
        TextButton(
          style: quietButton,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
