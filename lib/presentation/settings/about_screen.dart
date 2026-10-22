import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_updates.dart';
import '../../services/update_controller.dart';
import '../common/brand_marks.dart';
import '../common/format.dart';
import '../layout.dart';
import '../theme.dart';
import '../update/update_widgets.dart';

/// Pengaturan › Tentang aplikasi (FR-11.5, mockup `TentangAplikasi`).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(
      updateControllerProvider.select((s) => s.installed),
    );
    final released = DateTime.tryParse(buildDate);
    final platform = ref.read(appPlatformProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang aplikasi')),
      body: ListView(
        padding: readablePadding(
          context,
          const EdgeInsets.fromLTRB(20, 8, 20, 24),
        ),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const CupcakeMark(size: 64),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'BuatUsaha',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 8),
          Text(
            installed == null
                ? 'Versi —'
                : 'Versi ${installed.versionName} (build ${installed.buildNumber})',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (released != null) ...[
            const SizedBox(height: 4),
            Text(
              'Dirilis ${formatLongDate(released).split(', ').last}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 24),
          const UpdateCheckPanel(),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _Link(
                  title: 'Catatan rilis',
                  subtitle: 'Semua versi di GitHub',
                  icon: Icons.open_in_new,
                  onTap: () =>
                      platform.openUrl(GitHubReleaseSource.releasesPage),
                ),
                const Divider(height: 1),
                const _Link(
                  title: 'Kebijakan privasi',
                  subtitle: 'Segera tersedia',
                  icon: Icons.open_in_new,
                ),
                const Divider(height: 1),
                const _Link(
                  title: 'Ketentuan layanan',
                  subtitle: 'Segera tersedia',
                  icon: Icons.open_in_new,
                ),
                const Divider(height: 1),
                _Link(
                  title: 'Lisensi dan font',
                  subtitle: 'Paket dan font yang dipakai',
                  icon: Icons.chevron_right,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'BuatUsaha',
                    applicationVersion: installed?.versionName,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Dibuat untuk usaha rumahan. Pembaruan diambil dari halaman rilis '
            'BuatUsaha di GitHub.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ListTile(
      enabled: enabled,
      minVerticalPadding: 10,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: enabled ? AppColors.text : AppColors.textMuted,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(icon, size: 20, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
