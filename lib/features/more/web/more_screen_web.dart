import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../dashboard/web/_tokens.dart';
import '../../profile/web/profile_screen_web.dart';

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
    final t = WebTokens.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return ColoredBox(
      color: t.bgPrimary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTokens.s8,
          vertical: WebTokens.s6,
        ),
        child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Hero(),
                const SizedBox(height: WebTokens.s8),

                _SectionTitle('WORKSPACE'),
                const SizedBox(height: WebTokens.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    icon: Icons.people_outline,
                    title: 'Users',
                    subtitle: 'Directory of end users',
                    onTap: () => context.push(Routes.users),
                  ),
                  _NavCardData(
                    icon: Icons.business_outlined,
                    title: 'Organizations',
                    subtitle: 'Company accounts',
                    onTap: () => context.push(Routes.organizations),
                  ),
                ]),

                const SizedBox(height: WebTokens.s8),
                _SectionTitle('CONTENT'),
                const SizedBox(height: WebTokens.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    icon: Icons.menu_book_outlined,
                    title: 'Knowledgebase',
                    subtitle: 'FAQs and articles',
                    onTap: () => context.push(Routes.faq),
                  ),
                  _NavCardData(
                    icon: Icons.quickreply_outlined,
                    title: 'Canned responses',
                    subtitle: 'Reusable reply templates',
                    onTap: () => context.push(Routes.canned),
                  ),
                  _NavCardData(
                    icon: Icons.bookmark_outline,
                    title: 'Saved queues',
                    subtitle: 'Custom ticket views',
                    onTap: () => context.push(Routes.queues),
                  ),
                  _NavCardData(
                    icon: Icons.bar_chart_outlined,
                    title: 'Reports',
                    subtitle: 'Volume and performance',
                    onTap: () => context.push(Routes.reports),
                  ),
                ]),

                const SizedBox(height: WebTokens.s8),
                _SectionTitle('ACCOUNT'),
                const SizedBox(height: WebTokens.s3),
                _CardGrid(cards: [
                  _NavCardData(
                    icon: Icons.person_outline,
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
                    tone: WebTokens.danger,
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ]),

                const SizedBox(height: WebTokens.s10),
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
        final t = WebTokens.of(ctx);
        return Dialog(
          backgroundColor: t.bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTokens.rMd),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WebTokens.s5,
                    WebTokens.s5,
                    WebTokens.s5,
                    WebTokens.s3,
                  ),
                  child: Text('APPEARANCE', style: t.sectionTitle),
                ),
                for (final mode in ThemeMode.values)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, mode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WebTokens.s5,
                        vertical: WebTokens.s3,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _themeIcon(mode),
                            size: 18,
                            color: t.textSecondary,
                          ),
                          const SizedBox(width: WebTokens.s3),
                          Expanded(
                            child: Text(
                              _themeLabel(mode),
                              style: t.bodyBase.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (mode == current)
                            const Icon(
                              Icons.check,
                              size: 18,
                              color: WebTokens.accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: WebTokens.s3),
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
    final t = WebTokens.of(context);
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
        // Text('MORE', style: t.sectionTitle),
        // const SizedBox(height: WebTokens.s2),
        Text('Hello, $name', style: t.hero),
        if (email.isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          Text(email, style: t.bodySm),
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
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTokens.s1),
      child: Text(label.toUpperCase(), style: t.sectionCaps),
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
        mainAxisSpacing: WebTokens.s3,
        crossAxisSpacing: WebTokens.s3,
      ),
      children: [for (final c in cards) _NavCard(data: c)],
    );
  }
}

class _NavCardData {
  const _NavCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone,
  });
  final IconData icon;
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
    final t = WebTokens.of(context);
    final tone = widget.data.tone ?? WebTokens.accent;
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
          transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
          transformAlignment: Alignment.center,
          decoration: t.card(hover: _hover),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: WebTokens.s3,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(WebTokens.rSm),
                ),
                child: Icon(widget.data.icon, size: 20, color: tone),
              ),
              const SizedBox(width: WebTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.cardNameLg.copyWith(
                        color: widget.data.tone ?? t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySm,
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
