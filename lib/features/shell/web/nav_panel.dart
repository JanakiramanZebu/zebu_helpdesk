import 'package:flutter/material.dart';

import '../../../core/assets.dart';
import '../../../core/router/routes.dart';
import '../../../widgets/svg_icon.dart';
import '_shell_tokens.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

/// The second-level surface that sits between the rail and the workspace.
///
/// Two lifetimes share one slot, which is why they share one container:
///
///   * **Section panels** are persistent — they belong to the active rail
///     destination and stay until that destination changes or the agent
///     collapses them (Zendesk's edge chevron, owned by the shell).
///   * **Transient panels** are opened by an action, not a destination, and
///     dismiss the moment a choice is made (Pinterest's Create flyout).
///     These carry [onClose] so the header can render an ✕.
class NavPanel extends StatelessWidget {
  const NavPanel({
    super.key,
    required this.title,
    required this.children,
    this.onClose,
  });

  final String title;
  final List<Widget> children;

  /// Non-null for transient panels — renders a close affordance.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final s = ShellTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(ShellTokens.workspaceRadius),
        border: Border.all(color: s.cardBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShellTokens.workspaceRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZebuSpacing.s5,
                ZebuSpacing.s5,
                ZebuSpacing.s3,
                ZebuSpacing.s3,
              ),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: ZebuTextStyles.pageTitle(context))),
                  if (onClose != null) _CloseButton(onTap: onClose!),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: ZebuSpacing.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: _hover ? t.textPrimary : t.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------

/// Small-caps group heading inside a panel.
class NavPanelGroupLabel extends StatelessWidget {
  const NavPanelGroupLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s5,
        ZebuSpacing.s4,
        ZebuSpacing.s5,
        ZebuSpacing.s2,
      ),
      child: Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context)),
    );
  }
}

/// Compact destination row — the workhorse of a section panel.
///
/// The glyph shares the label's tone throughout — neutral at rest,
/// brand-coloured only when selected — so a column of rows reads as one list
/// rather than a scatter of colours.
class NavPanelItem extends StatefulWidget {
  const NavPanelItem({
    super.key,
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// Bundled SVG from the custom Mynt line set.
  final String asset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<NavPanelItem> createState() => _NavPanelItemState();
}

class _NavPanelItemState extends State<NavPanelItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final s = ShellTokens.of(context);
    final fg = widget.selected
        ? s.railIconActive
        : (_hover ? t.textPrimary : t.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 1,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            decoration: BoxDecoration(
              color: widget.selected
                  ? s.railTileActive
                  : (_hover ? t.bgHover : Colors.transparent),
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Row(
              children: [
                SvgIcon(widget.asset, size: 18, color: fg),
                const SizedBox(width: ZebuSpacing.s3),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tall action row — icon tile, title, and a describing line underneath.
/// Used by transient panels where each choice needs explaining, matching
/// the Pinterest Create flyout that prompted this design.
class NavPanelAction extends StatefulWidget {
  const NavPanelAction({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<NavPanelAction> createState() => _NavPanelActionState();
}

class _NavPanelActionState extends State<NavPanelAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(ZebuSpacing.s3),
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(ZebuRadius.rMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.bgTertiary,
                    borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                  ),
                  child: Icon(widget.icon, size: 20, color: t.textPrimary),
                ),
                const SizedBox(width: ZebuSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title, style: ZebuTextStyles.bodyStrong(context, fontWeight: ZebuFonts.semiBold)),
                      const SizedBox(height: 2),
                      Text(
                        widget.description,
                        style: ZebuTextStyles.small(context).copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel content
// ---------------------------------------------------------------------------

/// One Workspace destination.
class WorkspaceDest {
  const WorkspaceDest(this.asset, this.label, this.path);
  final String asset;
  final String label;
  final String path;
}

/// The six destinations that used to sit behind the "More" tab. Surfacing
/// them here is the point of the sub-panel — a hover and a click instead of
/// a navigation to a hub page that only existed to hold links.
const kWorkspaceGroups = <String, List<WorkspaceDest>>{
  'Directory': [
    WorkspaceDest(Assets.menuUsers, 'Users', Routes.users),
    WorkspaceDest(Assets.menuOrgs, 'Organizations', Routes.organizations),
  ],
  'Content': [
    WorkspaceDest(Assets.menuKnowledge, 'Knowledgebase', Routes.faq),
    WorkspaceDest(Assets.menuCanned, 'Canned responses', Routes.canned),
    WorkspaceDest(Assets.menuQueues, 'Saved queues', Routes.queues),
    WorkspaceDest(Assets.menuReports, 'Reports', Routes.reports),
  ],
};

/// Section panel for the Workspace destination.
class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({
    super.key,
    required this.currentPath,
    required this.onGo,
  });

  /// Current router location, used to mark the active destination.
  final String currentPath;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    return NavPanel(
      title: 'Workspace',
      children: [
        for (final entry in kWorkspaceGroups.entries) ...[
          NavPanelGroupLabel(entry.key),
          for (final d in entry.value)
            NavPanelItem(
              asset: d.asset,
              label: d.label,
              selected: currentPath == d.path,
              onTap: () => onGo(d.path),
            ),
        ],
      ],
    );
  }
}

/// Transient panel behind the rail's Create CTA.
class CreatePanel extends StatelessWidget {
  const CreatePanel({
    super.key,
    required this.onClose,
    required this.onNewTicket,
    required this.onNewTask,
  });

  final VoidCallback onClose;
  final VoidCallback onNewTicket;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    return NavPanel(
      title: 'Create',
      onClose: onClose,
      children: [
        NavPanelAction(
          icon: Icons.confirmation_number_outlined,
          title: 'New ticket',
          description: 'Log a request on behalf of a user',
          onTap: onNewTicket,
        ),
        NavPanelAction(
          icon: Icons.check_circle_outline,
          title: 'New task',
          description: 'Track an internal piece of work',
          onTap: onNewTask,
        ),
      ],
    );
  }
}
