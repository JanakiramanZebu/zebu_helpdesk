import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/assets.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/svg_icon.dart';
import '../../profile/web/profile_screen_web.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

/// Web-only More hub, styled to the Zebu Premium spec in `skill.md`.
///
/// Same data source as the mobile [MoreScreen] — swaps the ListTile column
/// for a hero + tappable card grid, matching the dashboard cards. Grouped
/// as: Workspace (Users / Orgs), Content (KB / Canned / Queues / Reports),
/// Account (Profile / Appearance / Sign out).
class MoreScreenWeb extends ConsumerWidget {
  const MoreScreenWeb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ZebuTheme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return ColoredBox(
      color: t.bgPrimary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: ZebuSpacing.s8,
          vertical: ZebuSpacing.s6,
        ),
        child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Hero(),
                const SizedBox(height: ZebuSpacing.s8),

                _SectionTitle('WORKSPACE'),
                const SizedBox(height: ZebuSpacing.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    svg: Assets.menuUsers,
                    title: 'Users',
                    subtitle: 'Directory of end users',
                    onTap: () => context.push(Routes.users),
                  ),
                  _NavCardData(
                    svg: Assets.menuOrgs,
                    title: 'Organizations',
                    subtitle: 'Company accounts',
                    onTap: () => context.push(Routes.organizations),
                  ),
                ]),

                const SizedBox(height: ZebuSpacing.s8),
                _SectionTitle('CONTENT'),
                const SizedBox(height: ZebuSpacing.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    svg: Assets.menuKnowledge,
                    title: 'Knowledgebase',
                    subtitle: 'FAQs and articles',
                    onTap: () => context.push(Routes.faq),
                  ),
                  _NavCardData(
                    svg: Assets.menuCanned,
                    title: 'Canned responses',
                    subtitle: 'Reusable reply templates',
                    onTap: () => context.push(Routes.canned),
                  ),
                  _NavCardData(
                    svg: Assets.menuQueues,
                    title: 'Saved queues',
                    subtitle: 'Custom ticket views',
                    onTap: () => context.push(Routes.queues),
                  ),
                  _NavCardData(
                    svg: Assets.menuReports,
                    title: 'Reports',
                    subtitle: 'Volume and performance',
                    onTap: () => context.push(Routes.reports),
                  ),
                ]),

                const SizedBox(height: ZebuSpacing.s8),
                _SectionTitle('ACCOUNT'),
                const SizedBox(height: ZebuSpacing.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    svg: Assets.profileEdit,
                    title: 'Profile & settings',
                    subtitle: 'Manage your account',
                    onTap: () => showProfileDialog(context),
                  ),
                  _NavCardData(
                    icon: _themeIcon(themeMode),
                    title: 'Appearance',
                    subtitle: _themeLabel(themeMode),
                    onTap: () => _chooseTheme(context, ref, themeMode),
                  ),
                  _NavCardData(
                    icon: Icons.logout,
                    title: 'Sign out',
                    subtitle: 'End this session',
                    tone: t.danger,
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ]),

                const SizedBox(height: ZebuSpacing.s10),
              ],
            ),
          ),
      ),
    );
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System default',
  };

  static IconData _themeIcon(ThemeMode m) => switch (m) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };

  Future<void> _chooseTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) {
        final t = ZebuTheme.of(ctx);
        return Dialog(
          backgroundColor: t.bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s5,
                    ZebuSpacing.s5,
                    ZebuSpacing.s5,
                    ZebuSpacing.s3,
                  ),
                  child: Text('APPEARANCE', style: ZebuTextStyles.label(context)),
                ),
                for (final mode in ThemeMode.values)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, mode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZebuSpacing.s5,
                        vertical: ZebuSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _themeIcon(mode),
                            size: 18,
                            color: t.textSecondary,
                          ),
                          const SizedBox(width: ZebuSpacing.s3),
                          Expanded(
                            child: Text(
                              _themeLabel(mode),
                              style: ZebuTextStyles.body(context).copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (mode == current)
                            Icon(
                              Icons.check,
                              size: 18,
                              color: t.accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: ZebuSpacing.s3),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      ref.read(themeModeProvider.notifier).set(picked);
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final ok = await showAppConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    router.go(Routes.login);
  }
}

// ---------------------------------------------------------------------------
// Hero header — dashboard-style greeting + subtitle
// ---------------------------------------------------------------------------

class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final name = me.maybeWhen(
      data: (m) {
        final n = m.name.trim().split(RegExp(r'\s+')).first;
        return n.isEmpty ? 'there' : n;
      },
      orElse: () => 'there',
    );
    final email = me.maybeWhen(data: (m) => m.email, orElse: () => '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text('MORE', style: ZebuTextStyles.label(context)),
        // const SizedBox(height: ZebuSpacing.s2),
        Text('Hello, $name', style: ZebuTextStyles.hero(context)),
        if (email.isNotEmpty) ...[
          const SizedBox(height: ZebuSpacing.s2),
          Text(email, style: ZebuTextStyles.small(context)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s1),
      child: Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context)),
    );
  }
}

// ---------------------------------------------------------------------------
// Card grid — dashboard StatGrid layout (240 px cross axis)
// ---------------------------------------------------------------------------

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});
  final List<_NavCardData> cards;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 96,
        mainAxisSpacing: ZebuSpacing.s3,
        crossAxisSpacing: ZebuSpacing.s3,
      ),
      children: [for (final c in cards) _NavCard(data: c)],
    );
  }
}

class _NavCardData {
  const _NavCardData({
    this.icon,
    this.svg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone,
  }) : assert(icon != null || svg != null, 'Provide icon or svg');

  /// Material fallback glyph — used where no mobile SVG equivalent exists
  /// (theme toggle, sign out).
  final IconData? icon;

  /// Mobile `menu_*` / `profile_*` SVG asset; takes precedence over [icon].
  final String? svg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional accent color for destructive / semantic cards (e.g. Sign out).
  final Color? tone;
}

class _NavCard extends StatefulWidget {
  const _NavCard({required this.data});
  final _NavCardData data;

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final tone = widget.data.tone ?? t.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.data.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: t.card(hover: _hover),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: ZebuSpacing.s3,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                ),
                child: widget.data.svg != null
                    ? SvgIcon(widget.data.svg!, size: 20, color: tone)
                    : Icon(widget.data.icon, size: 20, color: tone),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZebuTextStyles.bodyStrong(context, fontWeight: ZebuFonts.semiBold).copyWith(
                        color: widget.data.tone ?? t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZebuTextStyles.small(context),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: t.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
