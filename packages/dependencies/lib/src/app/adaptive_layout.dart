import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/clinic.dart';
import '../providers/clinic_provider.dart';
import '../theme/brand.dart';
import '../widgets/clinic_title.dart';
import 'clinic_router.dart';

/// Window widths the layout changes at.
///
///   phone     < 600    tabs in a bar along the bottom
///   tablet    600–1199 tabs in a rail down the side
///   desktop   ≥ 1200   the rail widens to show the tab names
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1200;

  /// Wide enough for a page to set two columns side by side.
  static const double twoPane = 840;
}

/// How wide a page's content may grow before it stops and centres, so a line
/// of text or a row of fields never runs the width of a desktop monitor.
abstract final class ContentWidth {
  /// A form, or one thing being read: a sign-in, a booking, a bill.
  static const double form = 640;

  /// A single column of cards: a list of visits, a list of bills.
  static const double list = 840;

  /// A detail page, which may split into two columns.
  static const double detail = 1080;

  /// Lists and dashboards, which fill up with columns of cards.
  static const double wide = 1320;
}

enum WindowSize { compact, medium, expanded }

extension AdaptiveContext on BuildContext {
  WindowSize get windowSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width >= Breakpoints.expanded) return WindowSize.expanded;
    if (width >= Breakpoints.medium) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => windowSize == WindowSize.compact;
}

/// One tab of an app's main navigation.
class ClinicTab {
  const ClinicTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
  });

  /// Under the clinic, starting with `/`: `'/schedule'`.
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Something waiting on this tab; shown as a count when above zero.
  final int badge;

  Widget _icon(bool selected) {
    final glyph = Icon(selected ? selectedIcon : icon);
    if (badge <= 0) return glyph;
    return Badge(label: Text('$badge'), child: glyph);
  }
}

/// An app's tabs. A function of [WidgetRef] so a tab can carry a live badge.
typedef ClinicTabs = List<ClinicTab> Function(WidgetRef ref);

/// The app's tabs around [child]: a bottom bar on a phone, a side rail on a
/// tablet or desktop.
///
/// [ClinicNavScaffold.shell] wraps the tab pages themselves. [ClinicNavScaffold.frame]
/// wraps a page opened from a tab (a visit, a patient, a bill): on a phone
/// that page covers the tabs as usual, but on a wider screen the rail stays
/// put beside it, so the rest of the app is always one click away.
class ClinicNavScaffold extends ConsumerWidget {
  const ClinicNavScaffold.shell({
    super.key,
    required this.tabs,
    required StatefulNavigationShell this.shell,
  }) : child = shell;

  const ClinicNavScaffold.frame({
    super.key,
    required this.tabs,
    required this.child,
  }) : shell = null;

  final ClinicTabs tabs;
  final StatefulNavigationShell? shell;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = context.windowSize;
    final isFrame = shell == null;
    // A page opened from a tab stays full-screen on a phone.
    if (isFrame && size == WindowSize.compact) return child;

    final items = tabs(ref);
    final selected = shell?.currentIndex ?? _tabOf(context, items);

    void select(int i) {
      final s = shell;
      if (s != null) {
        s.goBranch(i, initialLocation: i == s.currentIndex);
      } else {
        context.goInClinic(items[i].path);
      }
    }

    if (size == WindowSize.compact) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected ?? 0,
          onDestinationSelected: select,
          destinations: [
            for (final t in items)
              NavigationDestination(
                icon: t._icon(false),
                selectedIcon: t._icon(true),
                label: t.label,
              ),
          ],
        ),
      );
    }

    final extended = size == WindowSize.expanded;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 232,
            backgroundColor: cs.surfaceContainerLow,
            selectedIndex: selected,
            onDestinationSelected: select,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            groupAlignment: -1,
            leading: _RailHeader(extended: extended),
            destinations: [
              for (final t in items)
                NavigationRailDestination(
                  icon: t._icon(false),
                  selectedIcon: t._icon(true),
                  label: Text(t.label),
                ),
            ],
          ),
          Expanded(
            child: extended ? _RailShowsClinic(child: child) : child,
          ),
        ],
      ),
    );
  }

  /// Whether the rail beside this page already names the clinic (a desktop),
  /// so the page's own title can name the page instead of the clinic again.
  static bool showsClinicName(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RailShowsClinic>() != null;

  /// The tab a page opened from the tabs belongs to, from its path:
  /// `/clinic/patients/42` belongs to Patients. Null when none matches (a
  /// visit, reached from several tabs), and the rail highlights nothing.
  static int? _tabOf(BuildContext context, List<ClinicTab> tabs) {
    final segments = GoRouterState.of(context).uri.pathSegments;
    if (segments.length < 2) return null;
    final section = '/${segments[1]}';
    final i = tabs.indexWhere((t) => t.path == section);
    return i == -1 ? null : i;
  }
}

class _RailShowsClinic extends InheritedWidget {
  const _RailShowsClinic({required super.child});

  @override
  bool updateShouldNotify(_RailShowsClinic oldWidget) => false;
}

/// The clinic's mark, and on a desktop its name. For someone at several
/// clinics it is also the switcher, since the page titles beside it then
/// name the page rather than the clinic.
class _RailHeader extends ConsumerWidget {
  const _RailHeader({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(routeBrandClinicProvider);
    final clinics = ref.watch(myClinicsProvider).value ?? const <Clinic>[];
    final canSwitch = clinics.length > 1;
    final mark = ClinicMark(clinic: clinic, size: 40);
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: extended
          ? SizedBox(
              width: 200,
              child: Row(
                children: [
                  mark,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      clinic?.name ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canSwitch) const Icon(Icons.expand_more, size: 20),
                ],
              ),
            )
          : mark,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: !canSwitch
          ? header
          : Tooltip(
              message: 'Switch clinic',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showClinicSwitcher(context, ref),
                child: header,
              ),
            ),
    );
  }
}

/// Padding that keeps content at most [maxWidth] wide, centred, in a box
/// [available] wide, on top of [padding].
EdgeInsets centeredInsets(
  double available, {
  double maxWidth = ContentWidth.wide,
  EdgeInsets padding = const EdgeInsets.all(16),
}) {
  final inner = available - padding.horizontal;
  final side = math.max(0.0, (inner - maxWidth) / 2);
  return padding.copyWith(
    left: padding.left + side,
    right: padding.right + side,
  );
}

/// Hands [builder] the padding that centres a scroll view's content at
/// [maxWidth], leaving the scroll view itself — and so its scrollbar and
/// mouse-wheel area — the full width of the page.
///
///   CenteredScroll(
///     maxWidth: ContentWidth.form,
///     builder: (padding) => ListView(padding: padding, children: …),
///   )
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({
    super.key,
    required this.builder,
    this.maxWidth = ContentWidth.wide,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget Function(EdgeInsets padding) builder;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) => builder(
          centeredInsets(box.maxWidth, maxWidth: maxWidth, padding: padding)),
    );
  }
}

/// [CenteredScroll] for a sliver in a [CustomScrollView].
class SliverCentered extends StatelessWidget {
  const SliverCentered({
    super.key,
    required this.sliver,
    this.maxWidth = ContentWidth.wide,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget sliver;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (_, constraints) => SliverPadding(
        padding: centeredInsets(constraints.crossAxisExtent,
            maxWidth: maxWidth, padding: padding),
        sliver: sliver,
      ),
    );
  }
}

/// [child] no wider than [maxWidth], centred. For content that does not
/// scroll, or a block inside a scroll view.
class Centered extends StatelessWidget {
  const Centered({
    super.key,
    required this.child,
    this.maxWidth = ContentWidth.wide,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// [children] in as many equal columns as fit at [minItemWidth] each, up to
/// [maxColumns]: one on a phone, two or three on a tablet or desktop.
class CardColumns extends StatelessWidget {
  const CardColumns({
    super.key,
    required this.children,
    this.minItemWidth = 360,
    this.maxColumns = 3,
    this.spacing = 12,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  /// How many columns [width] fits.
  static int columnsFor(
    double width, {
    double minItemWidth = 360,
    int maxColumns = 3,
    double spacing = 12,
  }) =>
      ((width + spacing) / (minItemWidth + spacing))
          .floor()
          .clamp(1, maxColumns);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final columns = columnsFor(box.maxWidth,
          minItemWidth: minItemWidth, maxColumns: maxColumns, spacing: spacing);
      if (columns == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) SizedBox(height: runSpacing),
              c,
            ],
          ],
        );
      }
      // Rows rather than a Wrap, so a short last row keeps the column widths.
      // Not IntrinsicHeight: cards may hold a LayoutBuilder, which has none.
      final rows = <Widget>[];
      for (var start = 0; start < children.length; start += columns) {
        if (start > 0) rows.add(SizedBox(height: runSpacing));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = start; i < start + columns; i++) ...[
              if (i > start) SizedBox(width: spacing),
              Expanded(
                child: i < children.length
                    ? children[i]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

/// Two columns side by side once there is room ([Breakpoints.twoPane] of
/// width), one after the other before that: [start] then [end].
///
/// For a detail page whose sections split naturally: who and what on one
/// side, the history or the actions on the other. Pass [narrow] when the
/// single column wants another order than [start] then [end] — say, a page's
/// buttons at the very bottom on a phone, but at the top of the side column
/// once there is one.
///
/// [below] runs the full width under both columns once they split: for
/// something that needs the room, like a dental chart whose teeth are tapped
/// on a tablet. A single column leaves it out, so put it in [narrow] too.
class SplitColumns extends StatelessWidget {
  const SplitColumns({
    super.key,
    required this.start,
    required this.end,
    this.below = const [],
    this.narrow,
    this.startFlex = 1,
    this.endFlex = 1,
    this.spacing = 24,
    this.breakpoint = Breakpoints.twoPane,
  });

  final List<Widget> start;
  final List<Widget> end;
  final List<Widget> below;
  final List<Widget>? narrow;
  final int startFlex;
  final int endFlex;
  final double spacing;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: narrow ?? [...start, ...end, ...below],
        );
      }
      final columns = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: startFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: start,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            flex: endFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: end,
            ),
          ),
        ],
      );
      if (below.isEmpty) return columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [columns, ...below],
      );
    });
  }
}

/// Page transitions that keep the side rail still on a tablet or desktop.
///
/// A page opened from a tab draws the same rail as the page beneath it, so a
/// cross-fade leaves the rail where it is while the page changes. A slide or
/// zoom would carry the rail along with it. On a phone, where the new page
/// covers everything, this defers to [compact], the platform's own.
class AdaptivePageTransitionsBuilder extends PageTransitionsBuilder {
  const AdaptivePageTransitionsBuilder(this.compact);

  final PageTransitionsBuilder compact;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.sizeOf(context).width < Breakpoints.medium) {
      return compact.buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

/// [PageTransitionsTheme] with [AdaptivePageTransitionsBuilder] on every
/// platform.
PageTransitionsTheme adaptivePageTransitions() {
  const defaults = PageTransitionsTheme();
  return PageTransitionsTheme(builders: {
    for (final platform in TargetPlatform.values)
      platform: AdaptivePageTransitionsBuilder(
        defaults.builders[platform] ?? const ZoomPageTransitionsBuilder(),
      ),
  });
}
