import 'dart:io';
import 'dart:isolate';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../services/auto_backup.dart';
import '../../services/backup_service.dart';
import '../../services/local_notifications.dart';
import '../../services/update_controller.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../documents/logo_image.dart';
import '../documents/receipt.dart';
import '../motion.dart';
import '../menu/menu_labels.dart';
import '../orders/order_labels.dart' show channelFeeText;
import '../layout.dart';
import '../theme.dart';
import 'account_section.dart';

/// Pengaturan: profil usaha, harga, stok, notifikasi, channel, akun dan
/// sinkron, backup (FR-6.8, FR-8.1–8.3, FR-10.7).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider).value;
    final settings = ref.watch(notificationSettingsProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: business == null || settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: readablePadding(
                context,
                const EdgeInsets.fromLTRB(20, 0, 20, 32),
              ),
              children: [
                _ProfileSection(business: business),
                const SizedBox(height: 24),
                _PricingSection(business: business),
                const SizedBox(height: 24),
                _StockSection(business: business),
                const SizedBox(height: 24),
                _NotificationSection(settings: settings),
                const SizedBox(height: 24),
                const _ChannelSection(),
                const SizedBox(height: 24),
                const AccountSection(),
                const SizedBox(height: 24),
                const _DataSection(),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tentang aplikasi'),
                  subtitle: Text(
                    'Versi ${ref.watch(updateControllerProvider.select((s) => s.installed?.versionName)) ?? '—'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tentang'),
                ),
              ],
            ),
    );
  }
}

Future<void> _update(
  BuildContext context,
  WidgetRef ref,
  BusinessesCompanion changes, [
  String done = 'Disimpan.',
]) async {
  final business = await ref.read(currentBusinessProvider.future);
  if (!context.mounted) return;
  await runWithSnack(
    context,
    () => ref
        .read(businessRepositoryProvider)
        .updateBusiness(business.id, changes),
    done,
  );
}

Future<void> _updateNotif(
  WidgetRef ref,
  NotificationSettingsCompanion changes,
) async {
  final business = await ref.read(currentBusinessProvider.future);
  await ref
      .read(businessRepositoryProvider)
      .updateNotificationSettings(business.id, changes);
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({required this.business});

  final Business business;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final _name = TextEditingController(text: widget.business.name);
  late final _phone = TextEditingController(
    text: widget.business.phoneWa ?? '',
  );
  late final _address = TextEditingController(
    text: widget.business.address ?? '',
  );
  late final _payment = TextEditingController(
    text: widget.business.paymentInfo ?? '',
  );
  late final _footer = TextEditingController(
    text: widget.business.receiptNote ?? '',
  );
  var _pickingLogo = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _payment.dispose();
    _footer.dispose();
    super.dispose();
  }

  static Value<String?> _text(TextEditingController c) =>
      Value(c.text.trim().isEmpty ? null : c.text.trim());

  Future<void> _pickLogo() async {
    setState(() => _pickingLogo = true);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Pilih logo usaha',
        type: FileType.image,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final logo = await Isolate.run(() => encodeLogo(bytes));
      if (!mounted) return;
      if (logo == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File itu bukan gambar.')));
        return;
      }
      await _update(
        context,
        ref,
        BusinessesCompanion(logoData: Value(logo)),
        'Logo disimpan.',
      );
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(businessProvider).value ?? widget.business;
    final logo = decodeLogo(business.logoData);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Profil usaha'),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: logo == null
                  ? const Icon(
                      Icons.storefront_outlined,
                      color: AppColors.textMuted,
                    )
                  : Image.memory(logo, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                logo == null
                    ? 'Logo untuk nota (opsional)'
                    : 'Logo tampil di nota dan laporan PDF',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            if (logo != null)
              IconButton(
                tooltip: 'Hapus logo',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _update(
                  context,
                  ref,
                  const BusinessesCompanion(logoData: Value(null)),
                  'Logo dihapus.',
                ),
              ),
            TextButton(
              onPressed: _pickingLogo ? null : _pickLogo,
              child: Text(logo == null ? 'Pilih' : 'Ganti'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama usaha'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'No. WhatsApp usaha'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Alamat (opsional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _payment,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Info pembayaran',
            hintText: 'mis. BCA 1234567 a.n. Rina',
            helperText: 'Tampil di nota yang belum lunas.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _footer,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Catatan kaki nota',
            hintText: defaultReceiptNote,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _update(
              context,
              ref,
              BusinessesCompanion(
                name: Value(
                  _name.text.trim().isEmpty ? 'Usaha saya' : _name.text.trim(),
                ),
                phoneWa: _text(_phone),
                address: _text(_address),
                paymentInfo: _text(_payment),
                receiptNote: _text(_footer),
              ),
              'Profil usaha disimpan.',
            ),
            child: const Text('Simpan profil'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ukuran nota PDF',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final (size, label) in const [
              (ReceiptSize.a6, 'A6'),
              (ReceiptSize.roll58, 'Struk 58 mm'),
            ])
              ChoicePill(
                label: label,
                selected: business.receiptSize == size,
                onSelected: () => ref
                    .read(businessRepositoryProvider)
                    .updateBusiness(
                      business.id,
                      BusinessesCompanion(receiptSize: Value(size)),
                    ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PricingSection extends ConsumerStatefulWidget {
  const _PricingSection({required this.business});

  final Business business;

  @override
  ConsumerState<_PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends ConsumerState<_PricingSection> {
  late final _markup = TextEditingController(
    text: formatDecimal(dec(widget.business.defaultMarkupPct)),
  );
  late final _wage = TextEditingController(
    text: formatRupiahDigits(widget.business.ownerHourlyWage ?? 0),
  );

  @override
  void dispose() {
    _markup.dispose();
    _wage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final markup = parseDecimalInput(_markup.text);
    final wage = parseRupiahInput(_wage.text);
    final business = widget.business;
    await runWithSnack(context, () async {
      final repo = ref.read(businessRepositoryProvider);
      if (markup != null) {
        await repo.setPricing(business.id, defaultMarkupPct: markup);
      }
      if (wage != business.ownerHourlyWage) {
        await repo.setOwnerHourlyWage(business.id, wage);
      }
    }, 'Disimpan. HPP dan saran harga dihitung ulang.');
  }

  @override
  Widget build(BuildContext context) {
    final rounding = widget.business.priceRounding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Harga dan HPP'),
        const SizedBox(height: 8),
        const Text(
          'Pembulatan saran harga',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final r in const [100, 500, 1000])
              ChoicePill(
                label: formatRupiah(r),
                selected: rounding == r,
                onSelected: () => ref
                    .read(businessRepositoryProvider)
                    .setPricing(widget.business.id, priceRounding: r),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _markup,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Markup bawaan',
                  suffixText: '%',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _wage,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Upah pemilik/jam',
                  prefixText: 'Rp ',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Upah pemilik masuk HPP lewat jam kerja per resep; jangan dicatat '
          'lagi sebagai pengeluaran.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _save, child: const Text('Simpan')),
        ),
      ],
    );
  }
}

class _StockSection extends ConsumerWidget {
  const _StockSection({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Stok'),
        const SizedBox(height: 8),
        const Text(
          'Mode stok bawaan untuk menu baru',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final m in StockDeductMode.values)
              ChoicePill(
                label: modeLabel(m),
                selected: business.stockDeductMode == m,
                onSelected: () => _update(
                  context,
                  ref,
                  BusinessesCompanion(stockDeductMode: Value(m)),
                ),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: business.allowNegativeStock,
          onChanged: (v) => _update(
            context,
            ref,
            BusinessesCompanion(allowNegativeStock: Value(v)),
          ),
          title: const Text('Izinkan stok minus'),
          subtitle: const Text(
            'Produksi dan penjualan tetap bisa dicatat walau stok di aplikasi '
            'kurang.',
          ),
        ),
      ],
    );
  }
}

class _NotificationSection extends ConsumerStatefulWidget {
  const _NotificationSection({required this.settings});

  final NotificationSetting settings;

  @override
  ConsumerState<_NotificationSection> createState() =>
      _NotificationSectionState();
}

class _NotificationSectionState extends ConsumerState<_NotificationSection> {
  late Future<(bool, bool)> _permissions = _check();

  Future<(bool, bool)> _check() async => (
    await LocalNotifications.instance.notificationsEnabled(),
    await LocalNotifications.instance.canScheduleExact(),
  );

  Future<void> _pickTime(
    String current,
    NotificationSettingsCompanion Function(String) build,
  ) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await _updateNotif(ref, build(value));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final quiet = s.quietStart != null && s.quietEnd != null;
    String clock(String? v) => v?.replaceAll(':', '.') ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Notifikasi'),
        FutureBuilder<(bool, bool)>(
          future: _permissions,
          builder: (context, snap) {
            final (enabled, exact) = snap.data ?? (true, true);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!enabled) ...[
                  const SizedBox(height: 8),
                  const InfoBox(
                    'Izin notifikasi belum diberikan; pengingat pesanan tidak '
                    'akan muncul.',
                    kind: StatusKind.danger,
                  ),
                  TextButton(
                    onPressed: () async {
                      await LocalNotifications.instance.requestPermission();
                      setState(() => _permissions = _check());
                    },
                    child: const Text('Izinkan notifikasi'),
                  ),
                ],
                if (!exact) ...[
                  const SizedBox(height: 8),
                  const InfoBox(
                    'Alarm tepat belum diizinkan: pengingat bisa tertunda '
                    'beberapa menit.',
                  ),
                  TextButton(
                    onPressed: () async {
                      await LocalNotifications.instance.requestExactAlarms();
                      setState(() => _permissions = _check());
                    },
                    child: const Text('Izinkan alarm tepat'),
                  ),
                ],
              ],
            );
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.orderEnabled,
          onChanged: (v) => _updateNotif(
            ref,
            NotificationSettingsCompanion(orderEnabled: Value(v)),
          ),
          title: const Text('Pengingat pesanan dan ringkasan harian'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.stockEnabled,
          onChanged: (v) => _updateNotif(
            ref,
            NotificationSettingsCompanion(stockEnabled: Value(v)),
          ),
          title: const Text('Stok bahan menipis'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.paymentEnabled,
          onChanged: (v) => _updateNotif(
            ref,
            NotificationSettingsCompanion(paymentEnabled: Value(v)),
          ),
          title: const Text('Pengingat pelunasan'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.dayCloseEnabled,
          onChanged: (v) => _updateNotif(
            ref,
            NotificationSettingsCompanion(dayCloseEnabled: Value(v)),
          ),
          title: const Text('Pengingat Tutup hari'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Jam ringkasan harian'),
          trailing: Text(clock(s.dailySummaryTime)),
          onTap: () => _pickTime(
            s.dailySummaryTime,
            (v) => NotificationSettingsCompanion(dailySummaryTime: Value(v)),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Jam Tutup hari'),
          trailing: Text(clock(s.dayCloseTime)),
          onTap: () => _pickTime(
            s.dayCloseTime,
            (v) => NotificationSettingsCompanion(dayCloseTime: Value(v)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: quiet,
          onChanged: (v) => _updateNotif(
            ref,
            NotificationSettingsCompanion(
              quietStart: Value(v ? '21:00' : null),
              quietEnd: Value(v ? '06:00' : null),
            ),
          ),
          title: const Text('Jam tenang'),
          subtitle: Text(
            quiet
                ? '${clock(s.quietStart)}–${clock(s.quietEnd)}: pengingat '
                      'digeser ke akhir jam tenang'
                : 'Mati',
          ),
        ),
        if (quiet)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(
                    s.quietStart!,
                    (v) => NotificationSettingsCompanion(quietStart: Value(v)),
                  ),
                  child: Text('Mulai ${clock(s.quietStart)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(
                    s.quietEnd!,
                    (v) => NotificationSettingsCompanion(quietEnd: Value(v)),
                  ),
                  child: Text('Selesai ${clock(s.quietEnd)}'),
                ),
              ),
            ],
          ),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Pengingat sering terlambat? (Xiaomi, Oppo, Vivo)'),
          children: [BatteryGuide()],
        ),
      ],
    );
  }
}

/// Panduan mematikan optimasi baterai dan mengizinkan autostart (PRD 9.3).
class BatteryGuide extends StatelessWidget {
  const BatteryGuide({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        'Xiaomi / Redmi / POCO',
        'Setelan › Aplikasi › Kelola aplikasi › BuatUsaha: nyalakan Mulai '
            'otomatis, lalu Penghemat baterai › Tanpa batasan.',
      ),
      (
        'Oppo / Realme',
        'Setelan › Baterai › Pengelolaan baterai aplikasi › BuatUsaha: '
            'izinkan aktivitas latar belakang dan mulai otomatis.',
      ),
      (
        'Vivo',
        'Setelan › Baterai › Konsumsi daya latar belakang tinggi: izinkan '
            'BuatUsaha; i Manager › Manajer aplikasi › Mulai otomatis.',
      ),
      (
        'Samsung',
        'Setelan › Baterai › Batas penggunaan latar belakang: pastikan HPP '
            'Usaha tidak masuk "Aplikasi tidur".',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Beberapa HP mematikan alarm aplikasi untuk menghemat baterai. '
          'Nama menunya bisa sedikit berbeda per versi.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        for (final (brand, text) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$brand: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ChannelSection extends ConsumerWidget {
  const _ChannelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Channel penjualan',
          trailing: TextButton.icon(
            onPressed: () => _edit(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah'),
          ),
        ),
        const Text(
          'Potongan dihitung dari total item tanpa ongkir dan bisa diubah per '
          'pesanan. "Langsung" selalu tanpa potongan.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, c) in channels.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  title: Text(
                    c.name,
                    style: TextStyle(
                      color: c.isActive ? null : AppColors.textMuted,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (channelFeeText(c).isEmpty)
                        'tanpa potongan'
                      else
                        channelFeeText(c),
                      if (!c.isActive) 'nonaktif',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _edit(context, ref, c),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    SalesChannel? channel,
  ) async {
    final result = await showAppDialog<_ChannelResult>(
      context: context,
      builder: (_) => _ChannelDialog(channel: channel),
    );
    if (result == null || !context.mounted) return;
    final business = await ref.read(currentBusinessProvider.future);
    if (!context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(orderRepositoryProvider)
          .saveChannel(
            business.id,
            id: channel?.id,
            name: result.name,
            commissionPct: result.pct,
            feePerOrder: result.fee,
            feePerPcs: result.perPcs,
            isActive: result.active,
          ),
      'Channel ${result.name} disimpan.',
    );
  }
}

class _ChannelResult {
  const _ChannelResult(this.name, this.pct, this.fee, this.perPcs, this.active);

  final String name;
  final Decimal pct;
  final int fee;
  final int perPcs;
  final bool active;
}

class _ChannelDialog extends StatefulWidget {
  const _ChannelDialog({required this.channel});

  final SalesChannel? channel;

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<_ChannelDialog> {
  late final _name = TextEditingController(text: widget.channel?.name ?? '');
  late final _pct = TextEditingController(
    text: widget.channel == null
        ? ''
        : formatDecimal(dec(widget.channel!.commissionPct)),
  );
  late final _fee = TextEditingController(
    text: (widget.channel?.feePerOrder ?? 0) > 0
        ? formatRupiahDigits(widget.channel!.feePerOrder)
        : '',
  );
  late final _perPcs = TextEditingController(
    text: (widget.channel?.feePerPcs ?? 0) > 0
        ? formatRupiahDigits(widget.channel!.feePerPcs)
        : '',
  );
  late var _active = widget.channel?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    _pct.dispose();
    _fee.dispose();
    _perPcs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.channel == null ? 'Channel baru' : 'Ubah channel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.channel == null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Nama channel'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pct,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Komisi (opsional)',
                suffixText: '%',
                hintText: 'mis. 20',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Biaya per pesanan (opsional)',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _perPcs,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Potongan per pcs (opsional)',
                prefixText: 'Rp ',
                helperText:
                    'Isi yang dipakai mitra saja; yang lain biarkan kosong.',
                helperMaxLines: 2,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Aktif'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: valid
              ? () => Navigator.pop(
                  context,
                  _ChannelResult(
                    _name.text.trim(),
                    parseDecimalInput(_pct.text) ?? Decimal.zero,
                    parseRupiahInput(_fee.text) ?? 0,
                    parseRupiahInput(_perPcs.text) ?? 0,
                    _active,
                  ),
                )
              : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _DataSection extends ConsumerStatefulWidget {
  const _DataSection();

  @override
  ConsumerState<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends ConsumerState<_DataSection> {
  late Future<List<File>> _autoBackups = AutoBackup.list();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Backup otomatis di HP',
          trailing: Text(
            'Aktif',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sekali sehari saat aplikasi dibuka; 7 salinan terakhir disimpan. '
          'Untuk memulihkan salah input besar.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<File>>(
          future: _autoBackups,
          builder: (context, snap) {
            final files = snap.data ?? const <File>[];
            if (files.isEmpty) {
              return const Text(
                'Belum ada backup otomatis; dibuat saat aplikasi dibuka.',
                style: TextStyle(color: AppColors.textMuted),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, f) in files.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(_label(f)),
                      subtitle: Text(
                        '${(f.lengthSync() / 1024).round()} KB · otomatis',
                      ),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: () => _restoreFrom(f, _label(f)),
                        child: const Text('Pulihkan'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        const SectionTitle('Backup ke file'),
        const SizedBox(height: 4),
        const Text(
          'Simpan ke Google Drive atau WhatsApp sendiri, untuk pindah HP atau '
          'jika HP hilang.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _export,
          child: const Text('Bagikan file backup'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            foregroundColor: AppColors.text,
          ),
          onPressed: _pickAndRestore,
          child: const Text('Pulihkan dari file'),
        ),
      ],
    );
  }

  String _label(File f) {
    final date = AutoBackup.dateOf(f);
    if (date == null) return f.uri.pathSegments.last;
    final today = DateUtils.dateOnly(DateTime.now());
    final diff = today.difference(date).inDays;
    return switch (diff) {
      0 => 'Hari ini',
      1 => 'Kemarin',
      _ => formatLongDate(date).split(' ').take(3).join(' '),
    };
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await BackupService.export(ref.read(appDatabaseProvider));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Backup BuatUsaha',
          text: 'Backup data BuatUsaha ${formatLongDate(DateTime.now())}',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup gagal: $e')));
    }
  }

  Future<void> _pickAndRestore() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Pilih file backup',
      );
      if (picked == null) return;
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}${Platform.pathSeparator}restore.sqlite');
      await file.writeAsBytes(await picked.readAsBytes(), flush: true);
      final date = backupDateOf(File(picked.name));
      await _restoreFrom(
        file,
        date == null
            ? null
            : 'dibuat ${formatShortDate(date)} ${date.year} ${formatTime(date)}',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore gagal: $e')));
    }
  }

  Future<void> _restoreFrom(File file, String? when) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final name = await BackupService.inspect(file);
      if (!mounted) return;
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ganti semua data?'),
          content: Text(
            'Data di HP ini akan diganti dengan backup "$name"'
            '${when == null ? '' : ' (${when.toLowerCase()})'}. Data sekarang '
            'disimpan sebagai cadangan .bak di folder aplikasi. Isi akun '
            'Google juga diganti dengan backup ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: AppColors.danger,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ganti data'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      // Dilepas dari akun dan ditandai: layar Menyiapkan lalu mengganti isi
      // akun dengan backup ini (FR-10.11), supaya sinkron tidak menimpanya.
      final restored = await BackupService.detached(file);
      await ref.read(notificationSyncProvider).dispose();
      await ref.read(appDatabaseProvider).closeOnce();
      await BackupService.replaceDatabase(restored);
      restored.deleteSync();
      ref.invalidate(appDatabaseProvider);
      ref.read(notificationSyncProvider).start();
      router.go('/beranda');
      messenger.showSnackBar(
        const SnackBar(content: Text('Data dipulihkan dari backup.')),
      );
      if (mounted) setState(() => _autoBackups = AutoBackup.list());
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore gagal: $e')));
    }
  }
}
