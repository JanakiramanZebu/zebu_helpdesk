import 'package:flutter/material.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';

/// Flat, hairline-bordered container used as the surface for every card on
/// the redesigned web app. Optional header slot renders a title (in
/// [ZebuTheme.cardNameLg]) and a trailing action (typically a "See all"
/// link or a range picker). The body is passed as [child] and receives no
/// default padding — callers with a full-width table body pass the child
/// unpadded; callers wanting a padded body wrap in [Padding] themselves.
///
/// Set [dividerAfterHeader] false for chart / metric cards where a rule
/// under the header would fight the content.
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    this.title,
    this.trailing,
    this.subtitle,
    this.headerPadding = const EdgeInsets.fromLTRB(
      ZebuSpacing.s5,
      ZebuSpacing.s4,
      ZebuSpacing.s5,
      ZebuSpacing.s3,
    ),
    this.dividerAfterHeader = true,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry headerPadding;
  final bool dividerAfterHeader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        // 16px — the unified "card surface" radius shared with [KpiTile] and
        // the loading skeletons, per the design system's r2xl stat-tile token.
        borderRadius: BorderRadius.circular(ZebuRadius.r2xl),
        border: Border.all(color: t.borderSubtle, width: 1),
        boxShadow: ZebuElevation.shadowXs,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: headerPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title!,
                          style: ZebuTextStyles.bodyStrong(
                            context,
                            fontWeight: ZebuFonts.semiBold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: ZebuTextStyles.small(context),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (dividerAfterHeader) Container(height: 1, color: t.borderSubtle),
          ],
          child,
        ],
      ),
    );
  }
}
