import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

class AppTab {
  const AppTab(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

/// Lima tab navigasi bawah (PRD bagian 7, Design.md bagian 6).
const appTabs = [
  AppTab('/beranda', 'Beranda', Icons.home_outlined),
  AppTab('/pesanan', 'Pesanan', Icons.calendar_month_outlined),
  AppTab('/menu', 'Menu', Icons.bakery_dining_outlined),
  AppTab('/bahan', 'Bahan', Icons.inventory_2_outlined),
  AppTab('/laporan', 'Laporan', Icons.bar_chart_outlined),
];

GoRouter buildRouter() => GoRouter(
  initialLocation: appTabs.first.path,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        for (final tab in appTabs)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: tab.path,
                builder: (context, state) =>
                    PlaceholderScreen(title: tab.label),
              ),
            ],
          ),
      ],
    ),
  ],
);

class HppApp extends StatefulWidget {
  const HppApp({super.key});

  @override
  State<HppApp> createState() => _HppAppState();
}

class _HppAppState extends State<HppApp> {
  final _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HPP App',
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: [
            for (final tab in appTabs)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — segera hadir',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
