import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common/format.dart';
import 'theme.dart';

/// Token gerak (Design.md bagian Gerak, PRD FR-11.6–11.10). Semua animasi
/// ≤ 300 ms dan mati bila pengaturan Android "hapus animasi" aktif.
abstract final class Motion {
  /// Tekan tombol, sakelar, centang.
  static const fast = Duration(milliseconds: 150);

  /// Ganti tab, dialog, bottom sheet, angka berubah.
  static const medium = Duration(milliseconds: 250);

  /// Pindah layar, kartu → detail.
  static const slow = Duration(milliseconds: 300);

  /// Masuk: melambat di akhir.
  static const enter = Easing.emphasizedDecelerate;

  /// Keluar: mempercepat.
  static const exit = Easing.emphasizedAccelerate;

  /// Pindah posisi.
  static const move = Easing.standard;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], atau nol bila animasi dimatikan di HP.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Getar sesuai jenis aksi (FR-11.9).
abstract final class Haptics {
  /// Simpan, selesai, bayar.
  static void success() => HapticFeedback.lightImpact();

  /// Sebelum aksi membatalkan atau menghapus.
  static void warning() => HapticFeedback.mediumImpact();

  /// Pilihan, tab, sakelar.
  static void select() => HapticFeedback.selectionClick();
}

/// Transisi antarlayar: shared axis horizontal; tanpa animasi bila
/// dimatikan di HP (FR-11.6).
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  static const _sharedAxis = SharedAxisPageTransitionsBuilder(
    transitionType: SharedAxisTransitionType.horizontal,
    fillColor: AppColors.background,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    return _sharedAxis.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Dialog masuk dengan skala 0,9 → 1 dan pudar (FR-11.9). Pengganti
/// `showDialog` di seluruh aplikasi.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Motion.of(context, Motion.medium),
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Ganti tab bawah dengan fade-through (FR-11.7): isi lama memudar, isi baru
/// memudar masuk dengan skala 0,92 → 1. Semua tab tetap hidup, jadi posisi
/// gulir tiap tab tidak hilang.
class FadeThroughTabs extends StatefulWidget {
  const FadeThroughTabs({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeThroughTabs> createState() => _FadeThroughTabsState();
}

class _FadeThroughTabsState extends State<FadeThroughTabs>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
  late int _previous = widget.index;

  @override
  void didUpdateWidget(FadeThroughTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _previous = old.index;
      _controller.duration = Motion.of(context, Motion.medium);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final running = _controller.isAnimating;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final (i, child) in widget.children.indexed)
              _tab(i, child, running),
          ],
        );
      },
    );
  }

  Widget _tab(int i, Widget child, bool running) {
    final current = i == widget.index;
    final leaving = running && i == _previous && !current;
    final visible = current || leaving;
    var opacity = 1.0;
    var scale = 1.0;
    if (running && current) {
      final t = Motion.enter.transform(
        ((_controller.value - 0.35) / 0.65).clamp(0.0, 1.0),
      );
      opacity = t;
      scale = 0.92 + 0.08 * t;
    } else if (leaving) {
      opacity =
          1 - Motion.exit.transform((_controller.value / 0.35).clamp(0.0, 1.0));
    }
    // Susunan widget selalu sama supaya isi tab (navigator, posisi gulir)
    // tidak dibuat ulang saat berganti.
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !current,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      ),
    );
  }
}

/// Kartu yang membesar menjadi layar detail (container transform, FR-11.8).
class ContainerToDetail extends StatelessWidget {
  const ContainerToDetail({
    super.key,
    required this.closed,
    required this.open,
    this.radius = 16,
    this.bordered = true,
  });

  /// Isi kartu; panggil `openContainer` saat diketuk.
  final Widget Function(BuildContext context, VoidCallback openContainer)
  closed;
  final WidgetBuilder open;
  final double radius;

  /// `false` untuk baris di dalam kartu bersama (mis. daftar bahan).
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return OpenContainer<void>(
      useRootNavigator: true,
      transitionDuration: Motion.of(context, Motion.slow),
      transitionType: ContainerTransitionType.fadeThrough,
      closedElevation: 0,
      openElevation: 0,
      closedColor: AppColors.surface,
      openColor: AppColors.background,
      middleColor: AppColors.surface,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: bordered
            ? const BorderSide(color: AppColors.border)
            : BorderSide.none,
      ),
      tappable: false,
      openBuilder: (context, _) => open(context),
      // Selama transisi isi kartu digambar di luar Material asalnya; InkWell
      // butuh Material sendiri.
      closedBuilder: (context, openContainer) => Material(
        type: MaterialType.transparency,
        child: closed(context, openContainer),
      ),
    );
  }
}

/// Daftar muncul bertahap 30 ms per item untuk 8 item pertama, hanya saat
/// pertama kali dibuat (FR-11.9).
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curved;
  var _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.index >= 8 || Motion.reduced(context)) return;
    final delay = widget.index * 30;
    final total = delay + Motion.medium.inMilliseconds;
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    )..forward();
    _controller = controller;
    _curved = CurvedAnimation(
      parent: controller,
      curve: Interval(delay / total, 1, curve: Motion.enter),
    );
  }

  @override
  void dispose() {
    _curved?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    if (curved == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Angka Rupiah yang dihitung naik/turun saat berubah (FR-11.9).
class AnimatedRupiah extends StatelessWidget {
  const AnimatedRupiah(this.amount, {super.key, this.style});

  final int amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: amount.toDouble()),
      duration: Motion.of(context, Motion.medium),
      curve: Motion.enter,
      builder: (context, value, _) =>
          Text(formatRupiah(value.round()), style: style),
    );
  }
}

/// Efek tekan: mengecil ke 0,97 selama ditekan (FR-11.9).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Motion.of(context, Motion.fast),
        curve: Motion.move,
        child: widget.child,
      ),
    );
  }
}

/// Kerangka abu-abu yang berdenyut pelan saat memuat (FR-11.9).
class SkeletonList extends StatefulWidget {
  const SkeletonList({
    super.key,
    this.count = 4,
    this.height = 64,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  final int count;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat',
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.5).animate(_controller),
        // Tidak bisa digulir; kerangka yang tidak muat terpotong saja.
        child: ListView(
          padding: widget.padding,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < widget.count; i++)
              Container(
                height: widget.height,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
