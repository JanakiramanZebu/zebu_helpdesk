import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/assets.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../providers.dart';
import '../../../widgets/svg_icon.dart';
import '_shell_tokens.dart';
import 'rail_tooltip.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

/// Branch indices — must match the order declared in `app_router.dart`.
/// On web the router adds a dedicated Inbox branch between Tasks and More,
/// so the web rail is five destinations wide (mobile still uses four).
const int kIdxDashboard = 0;
const int kIdxTickets = 1;
const int kIdxTasks = 2;
const int kIdxInbox = 3;
const int kIdxWorkspace = 4;

/// Icon-only navigation rail that hover-expands into a labelled sidebar.
///
/// Two states, two lifetimes:
///
///   * **Resting** — [ShellTokens.railWidth] wide, glyphs only. Each item
///     names itself through a [RailTooltip] anchored to its right.
///   * **Hover-expanded** — animates to [ShellTokens.railExpandedWidth] and
///     reveals labels, the brand wordmark, the Inbox count, and the profile
///     identity. It **floats over** the sub-panel and content rather than
///     pushing them, so the page never reflows just because the pointer
///     crossed the rail. Collapses on exit or on any selection.
///
/// The column is always laid out at [ShellTokens.railExpandedWidth] and
/// revealed by clipping, rather than re-laying-out on every animation frame.
/// That keeps labels from being squeezed mid-transition (which would
/// otherwise throw overflow errors) and makes the expand a pure paint.
class NavRail extends ConsumerWidget {
  const NavRail({
    super.key,
    required this.expanded,
    required this.currentIndex,
    required this.createOpen,
    required this.onSelect,
    required this.onCreate,
    required this.onProfile,
  });

  /// True while the pointer is dwelling on the rail.
  final bool expanded;

  /// Active shell branch — one of the `kIdx*` constants.
  final int currentIndex;

  /// True while the transient Create panel is open, so the CTA can hold a
  /// pressed-looking state for as long as its panel is up.
  final bool createOpen;

  /// Navigate to a branch. The shell decides how — some destinations open a
  /// sub-panel as a side effect.
  final ValueChanged<int> onSelect;

  final VoidCallback onCreate;

  /// Opens the profile popover, anchored to the rail's footer row.
  final ValueChanged<BuildContext> onProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ShellTokens.of(context);
    final unread = ref
        .watch(unreadCountProvider)
        .maybeWhen(data: (c) => c, orElse: () => 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? ShellTokens.railExpandedWidth : ShellTokens.railWidth,
      decoration: BoxDecoration(
        color: expanded ? s.railSurfaceExpanded : s.railSurface,
        boxShadow: expanded ? ShellTokens.railShadow : null,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: ShellTokens.railExpandedWidth,
          maxWidth: ShellTokens.railExpandedWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              _BrandSlot(expanded: expanded),
              const SizedBox(height: 14),
              _NavRow(
                asset: Assets.navDashboard,
                label: 'Dashboard',
                expanded: expanded,
                selected: currentIndex == kIdxDashboard,
                onTap: () => onSelect(kIdxDashboard),
              ),
              _NavRow(
                asset: Assets.navTickets,
                label: 'Tickets',
                expanded: expanded,
                selected: currentIndex == kIdxTickets,
                onTap: () => onSelect(kIdxTickets),
              ),
              _NavRow(
                asset: Assets.navTasks,
                label: 'Tasks',
                expanded: expanded,
                selected: currentIndex == kIdxTasks,
                onTap: () => onSelect(kIdxTasks),
              ),
              _NavRow(
                asset: Assets.navInbox,
                label: 'Inbox',
                expanded: expanded,
                selected: currentIndex == kIdxInbox,
                onTap: () => onSelect(kIdxInbox),
                unread: unread,
              ),
              const _RailDivider(),
              _NavRow(
                asset: Assets.navMore,
                label: 'Workspace',
                expanded: expanded,
                selected: currentIndex == kIdxWorkspace,
                onTap: () => onSelect(kIdxWorkspace),
              ),
              const Spacer(),
              _ThemeRow(expanded: expanded),
              _ProfileRow(expanded: expanded, onTap: onProfile),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// Product mark, plus the wordmark once the rail is open.
///
/// The mark alone occupies the collapsed rail — "Zebu Helpdesk / Support
/// workspace" needs ~150 px and cannot fit 72 px, which is exactly why the
/// lockup lives in the expanded state rather than in a top bar.
class _BrandSlot extends StatelessWidget {
  const _BrandSlot({required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShellTokens.railGutter),
      child: Row(
        children: [
          SizedBox(
            width: ShellTokens.railTileSize,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ZebuRadius.rMd),
                  border: Border.all(color: s.cardBorder, width: 1),
                  boxShadow: ZebuElevation.shadowSm,
                ),
                child: Image.asset(Assets.appIcon, fit: BoxFit.cover),
              ),
            ),
          ),
          Expanded(
            child: FadeInSlot(
              visible: expanded,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Zebu Helpdesk',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: s.profileNameFg,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Support workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: s.profileEmailFg,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

/// Shared geometry for every rail row.
///
/// The tile is the interactive surface: a [ShellTokens.railTileSize] square
/// when collapsed, growing into a full-width pill when the rail opens. Its
/// contents are laid out once at pill width and clipped, so the glyph never
/// shifts and [content] never gets squeezed mid-animation.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.expanded,
    required this.fill,
    required this.leading,
    required this.content,
  });

  final bool expanded;
  final Color fill;

  /// Glyph or avatar, centred in the square tile.
  final Widget leading;

  /// Everything to the right of the glyph. Fades in with the expansion and
  /// is laid out at full pill width throughout, so it never reflows.
  final Widget content;

  static const _pillWidth =
      ShellTokens.railExpandedWidth - ShellTokens.railGutter * 2;

  @override
  Widget build(BuildContext context) {
    // The rail's column stretches its children, which hands this row a
    // *tight* width. Tight constraints beat a child's own `width:`, so
    // without this Align the collapsed tile would silently inflate to
    // [_pillWidth] and read as a clipped bar rather than a square.
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: expanded ? _pillWidth : ShellTokens.railTileSize,
        height: ShellTokens.railItemHeight,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: _pillWidth,
            maxWidth: _pillWidth,
            child: Row(
              children: [
                SizedBox(
                  width: ShellTokens.railTileSize,
                  child: Center(child: leading),
                ),
                Expanded(
                  child: FadeInSlot(visible: expanded, child: content),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A primary rail entry. Idle is transparent, hover is a neutral wash, and
/// selected is the one place brand colour appears in the rail.
///
/// Takes its glyph as either a bundled SVG ([asset], the custom Mynt line
/// set the destinations use) or a Material [icon] for entries that have no
/// SVG equivalent. Exactly one must be supplied.
class _NavRow extends StatefulWidget {
  const _NavRow({
    this.asset,
    this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onTap,
    this.unread = 0,
  }) : assert(
         (asset == null) != (icon == null),
         'Supply exactly one of asset / icon',
       );

  final String? asset;
  final IconData? icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  /// Inbox only — a corner dot when collapsed, a count pill when expanded.
  /// Zero hides both.
  final int unread;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final glyphColor = widget.selected
        ? s.railIconActive
        : (_hover ? s.railIconHover : s.railIconIdle);
    final fill = widget.selected
        ? s.railTileActive
        : (_hover ? s.railTileHover : s.railTileIdle);

    // Material glyphs sit a touch smaller than the custom line set at the
    // same nominal size, so the Material path gets 2 px back to keep every
    // glyph optically equal inside the tile.
    Widget glyph = widget.asset != null
        ? SvgIcon(widget.asset!, size: 20, color: glyphColor)
        : Icon(widget.icon, size: 22, color: glyphColor);
    if (widget.unread > 0) {
      glyph = Stack(
        clipBehavior: Clip.none,
        children: [
          glyph,
          // Only meaningful while collapsed — the expanded row carries the
          // real count in its trailing pill, so the dot fades out.
          Positioned(
            right: -3,
            top: -3,
            child: FadeInSlot(
              visible: !widget.expanded,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ShellTokens.badgePink,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.railSurface, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return RailTooltip(
      message: widget.label,
      enabled: !widget.expanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellTokens.railGutter,
          vertical: 3,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: _RailTile(
              expanded: widget.expanded,
              fill: fill,
              leading: glyph,
              content: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected
                            ? s.railLabelActive
                            : s.railLabelIdle,
                        fontSize: 13.5,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (widget.unread > 0) _CountPill(widget.unread),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ShellTokens.badgePink,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Light/dark toggle, pinned above the profile row. Reads the *effective*
/// brightness (system-resolved when the mode is [ThemeMode.system]) and
/// flips to the opposite; explicit choices persist.
class _ThemeRow extends ConsumerStatefulWidget {
  const _ThemeRow({required this.expanded});
  final bool expanded;

  @override
  ConsumerState<_ThemeRow> createState() => _ThemeRowState();
}

class _ThemeRowState extends ConsumerState<_ThemeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final mode = ref.watch(themeModeProvider);
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemDark,
    };
    final label = isDark ? 'Light mode' : 'Dark mode';

    return RailTooltip(
      message: label,
      enabled: !widget.expanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellTokens.railGutter,
          vertical: 3,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref
                .read(themeModeProvider.notifier)
                .set(isDark ? ThemeMode.light : ThemeMode.dark),
            child: _RailTile(
              expanded: widget.expanded,
              fill: _hover ? s.railTileHover : s.railTileIdle,
              leading: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 20,
                color: _hover ? s.railIconHover : s.railIconIdle,
              ),
              content: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.railLabelIdle,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer identity — avatar with an availability dot, plus name/email once
/// the rail is open. Opens the existing profile popover.
class _ProfileRow extends ConsumerStatefulWidget {
  const _ProfileRow({required this.expanded, required this.onTap});
  final bool expanded;
  final ValueChanged<BuildContext> onTap;

  @override
  ConsumerState<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends ConsumerState<_ProfileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    final me = ref.watch(meProvider);
    final name = me.maybeWhen(data: (m) => m.name, orElse: () => '');
    final email = me.maybeWhen(data: (m) => m.email, orElse: () => '');
    final available = me.maybeWhen(
      data: (m) => m.available,
      orElse: () => false,
    );
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    final avatar = SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.railTileActive,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: s.railIconActive,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: available ? ZebuTheme.success : const Color(0xFF737373),
                shape: BoxShape.circle,
                border: Border.all(color: s.railSurface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );

    return Builder(
      builder: (anchorContext) => RailTooltip(
        message: name.isEmpty ? 'Profile' : name,
        enabled: !widget.expanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ShellTokens.railGutter,
            vertical: 3,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap(anchorContext),
              child: _RailTile(
                expanded: widget.expanded,
                fill: _hover ? s.railTileHover : s.railTileIdle,
                leading: avatar,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: s.profileNameFg,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: s.profileEmailFg,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
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

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    final s = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(ShellTokens.railGutter, 8, 20, 8),
      child: Container(height: 1, color: s.railDivider),
    );
  }
}

/// Cross-fades content in step with the rail's width animation, and takes it
/// out of hit-testing while hidden so invisible labels can't swallow clicks
/// meant for the glyph underneath.
class FadeInSlot extends StatelessWidget {
  const FadeInSlot({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: IgnorePointer(ignoring: !visible, child: child),
    );
  }
}
