import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Ukuran jendela (FR-21.1, mengikuti Material 3): ringkas < 600 dp (HP),
/// sedang 600–839 dp (tablet tegak), lebar ≥ 840 dp (tablet mendatar).
enum WindowSize { compact, medium, expanded }

WindowSize windowSizeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 840) return WindowSize.expanded;
  if (width >= 600) return WindowSize.medium;
  return WindowSize.compact;
}

/// Lebar baca form dan layar detail (FR-21.6).
const readableWidth = 720.0;

/// Padding daftar yang membatasi isi ke [maxWidth] di tengah, sementara area
/// gulirnya tetap selebar layar. Di HP sama dengan [base].
EdgeInsets readablePadding(
  BuildContext context,
  EdgeInsets base, {
  double maxWidth = readableWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = math.max(base.left, (width - maxWidth) / 2);
  return EdgeInsets.fromLTRB(side, base.top, side, base.bottom);
}

/// Isi dibatasi [maxWidth] di tengah (mis. bar tombol bawah).
class Readable extends StatelessWidget {
  const Readable({
    super.key,
    required this.child,
    this.maxWidth = readableWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    // Setinggi isinya; tanpa ini bar bawah memenuhi layar.
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Kartu dalam kisi: 1 kolom di HP, 2 kolom ≥ 560 dp, 3 kolom ≥ 1.000 dp
/// lebar isi (FR-21.5).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.spacing = 10});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 3
            : width >= 560
            ? 2
            : 1;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) SizedBox(height: spacing),
                c,
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: spacing),
                  Expanded(
                    child: i + j < children.length
                        ? children[i + j]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) SizedBox(height: spacing),
              r,
            ],
          ],
        );
      },
    );
  }
}

/// Dua kolom berdampingan bila lebar isi ≥ [breakpoint], bertumpuk di HP
/// (FR-21.4).
class TwoColumns extends StatelessWidget {
  const TwoColumns({
    super.key,
    required this.left,
    required this.right,
    this.narrow,
    this.breakpoint = 720,
    this.gap = 20,
  });

  final List<Widget> left;
  final List<Widget> right;

  /// Urutan di HP bila berbeda dari kiri lalu kanan.
  final List<Widget>? narrow;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: narrow ?? [...left, ...right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Pilihan detail di layar daftar + detail (FR-21.3). Kartu daftar yang
/// berada di bawahnya membuka detail di panel kanan, bukan layar baru.
class ListDetailScope extends InheritedWidget {
  const ListDetailScope({
    super.key,
    required this.selectedId,
    required this.select,
    required this.clear,
    required super.child,
  });

  final String? selectedId;
  final void Function(String id, WidgetBuilder detail) select;

  /// Detail yang tampil tidak ada lagi (mis. dihapus).
  final VoidCallback clear;

  static ListDetailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListDetailScope>();

  @override
  bool updateShouldNotify(ListDetailScope old) => selectedId != old.selectedId;
}

/// Daftar di kiri (± 400 dp) dan detail di kanan pada layar lebar; di HP dan
/// tablet tegak hanya daftar (detail tetap dibuka sebagai layar sendiri).
class ListDetailLayout extends StatefulWidget {
  const ListDetailLayout({
    super.key,
    required this.list,
    required this.emptyText,
    this.initialId,
    this.initialDetail,
  });

  final Widget list;
  final String emptyText;

  /// Item yang terpilih otomatis saat belum ada pilihan.
  final String? initialId;
  final WidgetBuilder? initialDetail;

  @override
  State<ListDetailLayout> createState() => _ListDetailLayoutState();
}

class _ListDetailLayoutState extends State<ListDetailLayout> {
  String? _id;
  WidgetBuilder? _detail;
  var _cleared = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) return widget.list;
        final id = _id ?? (_cleared ? null : widget.initialId);
        final detail = _detail ?? (_cleared ? null : widget.initialDetail);
        final listWidth = math.min(420.0, constraints.maxWidth * 0.42);
        final paneWidth = constraints.maxWidth - listWidth - 1;
        final mq = MediaQuery.of(context);
        return ListDetailScope(
          selectedId: id,
          select: (id, builder) => setState(() {
            _id = id;
            _detail = builder;
          }),
          clear: () => setState(() {
            _id = null;
            _detail = null;
            _cleared = true;
          }),
          child: Row(
            children: [
              SizedBox(width: listWidth, child: widget.list),
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(
                width: paneWidth,
                child: id == null || detail == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.emptyText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      )
                    // Layar detail menghitung lebar baca dari panel ini.
                    : MediaQuery(
                        data: mq.copyWith(
                          size: Size(paneWidth, mq.size.height),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(id),
                          child: Builder(builder: detail),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tutup detail setelah item dihapus/diarsipkan: pop bila layar sendiri,
/// kosongkan panel bila berdampingan.
void closeDetail(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    ListDetailScope.maybeOf(context)?.clear();
  }
}
