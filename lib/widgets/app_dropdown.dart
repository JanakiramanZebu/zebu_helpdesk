import 'dart:async';

import 'package:flutter/material.dart';
// ignore: unnecessary_import  — material.dart re-exports most of services.dart
// but NOT the low-level KeyDownEvent / LogicalKeyboardKey symbols the Escape
// handler here needs, so the direct import stays.
import 'package:flutter/services.dart';

import '../core/assets.dart';
import '../res/zebu_theme.dart';
import '../res/zebu_spacing.dart';
import 'svg_icon.dart';
import '../res/zebu_text_styles.dart';

/// Reusable dropdown menu styled to match the Zebu Premium spec — an
/// Asana-style rounded card of items with icons, optional keyboard
/// shortcuts, and destructive tones. Use this everywhere the app needs
/// a "trigger + popup list" pattern (action menus, view switchers, …)
/// so the styling stays consistent.
///
/// Example:
/// ```dart
/// AppDropdownButton<String>(
///   label: 'Actions',
///   onSelected: (v) => _onMenu(v),
///   entries: const [
///     AppDropdownItem(value: 'close', label: 'Close task', icon: Icons.check_circle_outline),
///     AppDropdownItem(value: 'assign', label: 'Assign', icon: Icons.person_add_alt),
///     AppDropdownDivider(),
///     AppDropdownItem(value: 'delete', label: 'Delete task', icon: Icons.delete_outline, tone: t.danger),
///   ],
/// )
/// ```
sealed class AppDropdownEntry<T> {
  const AppDropdownEntry();
}

/// A single row in the dropdown. [tone] recolors the icon + label — pass
/// `t.danger` for destructive actions.
class AppDropdownItem<T> extends AppDropdownEntry<T> {
  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.svgAsset,
    this.shortcut,
    this.tone,
    this.disabled = false,
    this.selected = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Mobile action-glyph asset (`Assets.act*`). Rendered as a tinted
  /// icon chip on the row's leading edge (mobile ⋮-menu style); takes
  /// precedence over [icon].
  final String? svgAsset;

  /// Rendered as a small monospace chip on the right (e.g. `'Tab P'`).
  final String? shortcut;

  /// Foreground color for the icon + label. Defaults to `textPrimary`.
  /// Pass `t.danger` for destructive rows.
  final Color? tone;

  final bool disabled;

  /// True on the row that reflects the current value in a single-select
  /// menu. Renders a leading checkmark; when any item in the list is
  /// [selected], every row reserves the check slot so labels stay
  /// vertically aligned (Asana-style).
  final bool selected;
}

/// A full-width separator between grouped items.
class AppDropdownDivider<T> extends AppDropdownEntry<T> {
  const AppDropdownDivider();
}

/// Small-caps header row rendered at the top of a group (Asana-style
/// "My tasks" section title). Optional — most action menus don't need
/// one, but single-select pickers gain scannability.
class AppDropdownHeader<T> extends AppDropdownEntry<T> {
  const AppDropdownHeader(this.label);
  final String label;
}

/// Shows an app-styled dropdown menu anchored beneath the widget of the given
/// [anchorContext] and returns the selected value (or `null` if dismissed).
///
/// Positioning contract:
///   * The menu is **always placed below** the anchor's bottom edge — even
///     when the anchor sits near the viewport bottom. If the full list
///     wouldn't fit, the menu clamps its height and scrolls internally
///     instead of flipping above the anchor. (Flutter's `showMenu` flips
///     the menu above when it wouldn't fit, which is disorienting when
///     the whole panel is designed around "click a field → menu drops
///     under it".)
///   * The menu width matches the anchor's width, clamped to
///     [[minWidth], [maxWidth]] so small pills (e.g. `+ SET PRIORITY`)
///     still open a comfortable list, and wide cells don't get shorter
///     than their trigger.
///   * The menu is horizontally clamped inside the viewport with an 8 px
///     side margin so it never crosses the right screen edge.
///
/// Dismisses on outside tap or the Escape key.
Future<T?> showAppDropdown<T>(
  BuildContext anchorContext, {
  required List<AppDropdownEntry<T>> entries,
  double minWidth = 220,
  // Was 480 — wide field-row anchors (Status / Priority in the ticket
  // panel span ~460 px each) dragged the popup out to that same width,
  // which read as too much horizontal air around short items like
  // `Open` / `Low`. 300 keeps the menu narrow enough to feel tight
  // while still accommodating long labels like `Business Analyst`.
  double maxWidth = 300,
}) async {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  final overlayState = Overlay.of(anchorContext);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = box.size;
  final viewport = overlayBox.size;

  final menuWidth = anchorSize.width.clamp(minWidth, maxWidth);
  final menuLeft = anchorTopLeft.dx
      .clamp(8.0, (viewport.width - menuWidth - 8.0).clamp(8.0, viewport.width));
  final menuTop = anchorTopLeft.dy + anchorSize.height + 6;
  // If the anchor is near the bottom edge, cap the menu height instead of
  // flipping upward. 24 px keeps the menu clear of the viewport bottom.
  final maxMenuHeight = (viewport.height - menuTop - 24).clamp(120.0, 480.0);

  final completer = Completer<T?>();
  late OverlayEntry entry;

  void dismiss(T? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      // Focus/Shortcuts handle Escape-to-dismiss; the transparent
      // full-screen barrier below handles outside-click dismissal.
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => dismiss(null),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxMenuHeight),
              child: Focus(
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    dismiss(null);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                // When any item is `selected`, every row reserves a leading
                // check slot so labels align on a shared column — matches
                // Asana's single-select menu treatment. Action menus with
                // no selection pass this whole flag through as false and
                // keep the compact icon-then-label layout. Search field is
                // shown when there are enough items to justify it (≥ 6)
                // and filters the list live.
                child: _AppDropdownContent<T>(
                  entries: entries,
                  onPick: dismiss,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

/// The trigger widget — a solid brand-blue pill with a label + chevron.
/// Tapping opens a popup rendering [entries] at the button's bottom-left,
/// invoking [onSelected] with the picked item's value.
class AppDropdownButton<T> extends StatefulWidget {
  const AppDropdownButton({
    super.key,
    required this.label,
    required this.entries,
    required this.onSelected,
    this.tone,
    this.tooltip,
  });

  final String label;
  final List<AppDropdownEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// Trigger background color. Defaults to `ZebuTheme.accent`.
  final Color? tone;

  final String? tooltip;

  @override
  State<AppDropdownButton<T>> createState() => _AppDropdownButtonState<T>();
}

class _AppDropdownButtonState<T> extends State<AppDropdownButton<T>> {
  bool _hover = false;

  Future<void> _show() async {
    final result = await showAppDropdown<T>(
      context,
      entries: widget.entries,
    );
    if (result != null) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final tone = widget.tone ?? t.accent;
    final trigger = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _show,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: _hover ? Color.lerp(tone, Colors.black, 0.08) : tone,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? trigger
        : Tooltip(message: widget.tooltip!, child: trigger);
  }
}

/// Search-enabled popup body — owns the query state, filters items live,
/// and renders the container chrome (rounded card, hairline border, drop
/// shadow). Search field auto-appears once the menu has ≥ 6 items so short
/// action menus stay compact but long lists (agents, departments) become
/// scannable — mirrors the reference Asana / ClickUp assignee pickers.
class _AppDropdownContent<T> extends StatefulWidget {
  const _AppDropdownContent({
    required this.entries,
    required this.onPick,
  });
  final List<AppDropdownEntry<T>> entries;
  final void Function(T?) onPick;

  @override
  State<_AppDropdownContent<T>> createState() => _AppDropdownContentState<T>();
}

class _AppDropdownContentState<T> extends State<_AppDropdownContent<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// Threshold at which the search input becomes worth showing — action
  /// menus with 3–5 rows don't need it, but any long list benefits.
  static const int _kSearchThreshold = 6;

  int get _itemCount =>
      widget.entries.whereType<AppDropdownItem<T>>().length;

  bool get _showSearch => _itemCount >= _kSearchThreshold;

  bool get _hasSelectionColumn =>
      widget.entries.any((e) => e is AppDropdownItem<T> && e.selected);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(AppDropdownItem<T> item) {
    if (_query.isEmpty) return true;
    return item.label.toLowerCase().contains(_query.toLowerCase());
  }

  /// Filter items by the search query, then prune orphan headers /
  /// dividers that no longer sit above any visible item. Keeps the popup
  /// from showing a "Ticket actions" header with an empty body when the
  /// query filters everything out below it.
  List<AppDropdownEntry<T>> _visibleEntries() {
    if (_query.isEmpty) return widget.entries;
    final filtered = <AppDropdownEntry<T>>[];
    for (final e in widget.entries) {
      if (e is AppDropdownItem<T>) {
        if (_matches(e)) filtered.add(e);
      } else {
        filtered.add(e);
      }
    }
    // Second pass — drop headers/dividers not followed by an item.
    final pruned = <AppDropdownEntry<T>>[];
    for (var i = 0; i < filtered.length; i++) {
      final e = filtered[i];
      if (e is AppDropdownItem<T>) {
        pruned.add(e);
      } else {
        final hasItemAfter = filtered
            .skip(i + 1)
            .any((next) => next is AppDropdownItem<T>);
        if (hasItemAfter) pruned.add(e);
      }
    }
    return pruned;
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final visible = _visibleEntries();
    final hasAnyItem = visible.any((e) => e is AppDropdownItem<T>);

    // Shadow lives on the OUTER DecoratedBox so it can paint outside the
    // Material's clip rect. Previously the Material's `Clip.antiAlias`
    // was cropping the shadow to the rounded card, which is why the lift
    // wasn't visible on-screen even at strong alpha.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        border: Border.all(color: t.borderSubtle, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showSearch) _buildSearchField(t),
            Flexible(
              child: hasAnyItem
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in visible)
                            if (e is AppDropdownItem<T>)
                              _AppDropdownInkRow<T>(
                                item: e,
                                onTap: () => widget.onPick(e.value),
                                hasSelectionColumn: _hasSelectionColumn,
                              )
                            // else if (e is AppDropdownHeader<T>)
                            //   _AppDropdownHeaderRow(label: e.label)
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 0,
                                ),
                                // child: Divider(
                                //   height: 1,
                                //   thickness: 1,
                                //   color: t.borderSubtle,
                                // ),
                              ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZebuSpacing.s4,
                        vertical: 20,
                      ),
                      child: Center(
                        child: Text('No results', style: ZebuTextStyles.small(context)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors [ListSearchInput] — outlined pill with a leading search icon
  /// and a right-hand clear button once the field has text. Every
  /// [InputDecoration] border slot is overridden so the global
  /// `inputDecorationTheme` (which paints grey fill + enabled border on
  /// every TextField) can't bleed through the popover chrome.
  Widget _buildSearchField(ZebuTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            // Same hairline outline `ListSearchInput` uses at the top of
            // every list screen — reads as one continuous search-input
            // language across the app.
            border: Border.all(color: t.borderSubtle, width: 1),
          ),
          // Same geometry `ListSearchInput` uses at the top of every list
          // screen — fixed 40 px height + horizontal padding, so this
          // dropdown search reads as the same search input language as
          // the ticket-list header search.
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgIcon(Assets.search, size: 16, color: t.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      textAlign: TextAlign.start,
                      textAlignVertical: TextAlignVertical.center,
                      style: ZebuTextStyles.body(context).copyWith(fontWeight: FontWeight.w500),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        hintText: 'Search…',
                        hintStyle: ZebuTextStyles.body(context).copyWith(
                          color: t.textSecondary,
                          letterSpacing: -0.1,
                        ),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    _DropdownClearButton(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular clear button — 22 px pill with a close glyph. Copy of
/// [ListSearchInput]'s clear button, kept private here so the dropdown
/// doesn't take a dep on the list widget.
class _DropdownClearButton extends StatefulWidget {
  const _DropdownClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DropdownClearButton> createState() => _DropdownClearButtonState();
}

class _DropdownClearButtonState extends State<_DropdownClearButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rFull),
          ),
          child: Icon(Icons.close_rounded, size: 14, color: t.textSecondary),
        ),
      ),
    );
  }
}

/// Interactive popup row — leading check slot (single-select menus) or
/// icon, then label + optional shortcut chip, wrapped in an [InkWell] so
/// tap/hover feedback stays inside the row instead of bleeding to the menu
/// edge. Used by [showAppDropdown]'s custom overlay (which doesn't have
/// `PopupMenuItem`'s built-in ink response).
class _AppDropdownInkRow<T> extends StatelessWidget {
  const _AppDropdownInkRow({
    required this.item,
    required this.onTap,
    required this.hasSelectionColumn,
  });
  final AppDropdownItem<T> item;
  final VoidCallback onTap;

  /// True when any item in the parent list is [AppDropdownItem.selected].
  /// In that mode every row reserves a 22 px leading slot so labels align
  /// on a shared column (Asana-style single-select).
  final bool hasSelectionColumn;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final effective = item.disabled
        ? t.textSecondary.withValues(alpha: 0.5)
        : (item.tone ?? t.textPrimary);
    // Tint for the mobile-style leading icon chip: brand accent by default,
    // the row's tone (e.g. danger) when set — mirrors the mobile ⋮-menu's
    // `appMenuItem` treatment.
    final chipTone = item.disabled
        ? t.textSecondary.withValues(alpha: 0.5)
        : (item.tone ?? t.accent);
    return InkWell(
      onTap: item.disabled ? null : onTap,
      hoverColor: t.bgHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZebuSpacing.s4,
          vertical: 6,
        ),
        child: Row(
          children: [
            // Leading slot — check (selected) / icon chip / blank. Fixed
            // width in single-select mode so labels line up across rows.
            if (hasSelectionColumn) ...[
              SizedBox(
                width: 16,
                child: item.selected
                    ? Icon(Icons.check, size: 16, color: effective)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: ZebuSpacing.s3),
            ] else if (item.svgAsset != null || item.icon != null) ...[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chipTone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                ),
                child: item.svgAsset != null
                    ? SvgIcon(item.svgAsset!, size: 15, color: chipTone)
                    : Icon(item.icon, size: 15, color: chipTone),
              ),
              const SizedBox(width: ZebuSpacing.s3),
            ],
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: effective,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.shortcut != null) ...[
              const SizedBox(width: ZebuSpacing.s3),
              _ShortcutChip(text: item.shortcut!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small-caps section header for a group of rows. Emits a top row with
/// muted `tinyLabel` copy — the divider comes from the caller placing an
/// [AppDropdownDivider] right after, when they want one.
class _AppDropdownHeaderRow extends StatelessWidget {
  const _AppDropdownHeaderRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s2,
        ZebuSpacing.s4,
        6,
      ),
      child: Text(label, style: ZebuTextStyles.label(context)),
    );
  }
}

/// The small monospace pill used for keyboard-shortcut hints on the right
/// side of a dropdown row.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: t.borderSubtle, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: t.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
