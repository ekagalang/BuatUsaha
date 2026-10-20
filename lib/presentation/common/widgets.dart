import 'package:flutter/material.dart';

import '../theme.dart';

enum StatusKind { success, warning, danger, neutral }

(Color, Color) _colors(StatusKind kind) => switch (kind) {
  StatusKind.success => (AppColors.successContainer, AppColors.success),
  StatusKind.warning => (AppColors.warningContainer, AppColors.warning),
  StatusKind.danger => (AppColors.dangerContainer, AppColors.danger),
  StatusKind.neutral => (
    AppColors.primaryContainer,
    AppColors.onPrimaryContainer,
  ),
};

/// Pill status: selalu teks + warna (Design.md bagian 7 dan 8).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.kind});

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Kotak info/peringatan dengan pasangan warna status.
class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {super.key, this.kind = StatusKind.warning});

  final String text;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(kind);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Judul bagian, 16/700.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

/// Bilah putih di bawah layar form berisi satu aksi utama.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child, this.above});

  final Widget child;
  final Widget? above;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (above != null) ...[above!, const SizedBox(height: 12)],
              SizedBox(width: double.infinity, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip pilihan dengan gaya Design.md (terpilih = cokelat penuh).
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      labelStyle: TextStyle(
        color: selected ? AppColors.onPrimary : AppColors.text,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

/// Konfirmasi pembatalan transaksi dengan alasan wajib (FR-9.1).
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Alasan',
              hintText: 'mis. salah ketik harga',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tidak'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: AppColors.danger,
          ),
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.pop(context, reason),
          child: const Text('Batalkan'),
        ),
      ],
    );
  }
}

/// Jalankan aksi lalu tampilkan hasilnya di snackbar.
Future<bool> runWithSnack(
  BuildContext context,
  Future<void> Function() action,
  String done,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Gagal: $error')));
    return false;
  }
}

/// Segmented control Design.md: wadah `surfaceMuted`, segmen terpilih putih.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.surface : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == selected
                          ? AppColors.text
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
