import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'ellipsis_text.dart';
import 'zebu_avatar.dart';

/// Floor height for both people cards.
///
/// They sit side by side in one row, and their contents are different heights
/// — a 36 px avatar over two lines against a 32 px avatar stack over one — so
/// left to themselves they landed 4 px apart. `IntrinsicHeight` on the row
/// would be the general fix, but both cards measure text with a
/// `LayoutBuilder` and that combination asserts, so the floor is a constant.
///
/// 68 clears the tallest of the three. The requester's name-over-email column
/// measures 42 px, which beats its own 36 px avatar, so the card wants 66 on
/// its own; the floor pulls the placeholder and the collaborator stack up to
/// meet it.
/// `user_card_test.dart` asserts the two match rather than asserting this
/// number, so a font change that pushes one past the floor fails the test
/// instead of quietly reintroducing the step.
const double kZebuUserCardMinHeight = 68;

/// The chosen requester, shown as a card rather than a value in a select box.
///
/// A person is not a value like a priority is. Once picked, the thing that
/// matters is whether it is the *right* person — so the card shows the avatar,
/// the name and the address the ticket will actually go to, which a one-line
/// select truncated to `'Jayashree.M'` and left you to trust.
///
/// [chips] carry whatever else is known about them. They are passed in rather
/// than derived: the list endpoint returns no organisation, so the org only
/// appears once the full record has been fetched, and a chip nobody can fill
/// should simply not be built.
class ZebuUserCard extends StatelessWidget {
  const ZebuUserCard({
    super.key,
    required this.name,
    required this.email,
    required this.onChange,
    this.chips = const [],
  });

  final String name;
  final String email;

  /// Reopens the picker. The whole card is the target — a separate "Change"
  /// link had to be paid for in width, and the width came out of the email,
  /// which is the one thing on the card you need to read in full.
  final VoidCallback onChange;

  final List<ZebuUserChip> chips;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChange,
        child: Container(
          constraints: const BoxConstraints(minHeight: kZebuUserCardMinHeight),
          padding: const EdgeInsets.all(ZebuSpacing.s3),
          decoration: BoxDecoration(
            // color: t.accentSoft,
            border: Border.all(color: t.accent, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ZebuAvatar.solid(name: name, size: 36),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZebuEllipsisText(
                      name,
                      style: ZebuTextStyles.body(
                        context,
                        color: t.textPrimary,
                        fontWeight: ZebuFonts.semiBold,
                      ),
                    ),
                    ZebuEllipsisText(
                      email,
                      style: ZebuTextStyles.small(
                        context,
                        color: t.textSlateMuted,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: ZebuSpacing.s2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final c in chips) _Chip(chip: c)],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One fact about the requester. [tone] null means the neutral slate chip.
class ZebuUserChip {
  const ZebuUserChip(this.label, {this.tone});
  final String label;
  final Color? tone;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.chip});
  final ZebuUserChip chip;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final ink = chip.tone ?? t.textSlate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        border: Border.all(color: ink.withValues(alpha: 0.28), width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rXs),
      ),
      child: Text(
        chip.label,
        style: ZebuTextStyles.small(
          context,
          color: ink,
          fontWeight: ZebuFonts.medium,
        ).copyWith(fontSize: 11),
      ),
    );
  }
}

/// The chosen collaborators, summarised.
///
/// Overlapped avatars rather than a list: at four people a stacked row is one
/// glance, and the names below say who without costing four rows of the form.
/// The whole card opens the picker, same as [ZebuUserCard] — there is no
/// separate add button, because "add another" and "change who" open the same
/// multi-select anyway.
class ZebuCollaboratorsCard extends StatelessWidget {
  const ZebuCollaboratorsCard({
    super.key,
    required this.names,
    required this.onEdit,
    this.maxAvatars = 4,
  });

  final List<String> names;
  final VoidCallback onEdit;

  /// Beyond this the stack stops and a `+n` disc takes over — six overlapping
  /// discs is a smear, not a count.
  final int maxAvatars;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final shown = names.take(maxAvatars).toList();
    final extra = names.length - shown.length;
    const size = 28.0;
    const overlap = 9.0;

    // Each disc is drawn inside a ring, so it occupies `size + 4` — and the
    // stack has to be measured on that, not on `size`. Measuring on the bare
    // avatar cropped 4 px off the right of the last disc and 4 off the bottom
    // of every one of them, which is what sliced the row.
    const ring = size + 4;
    const step = size - overlap;
    final discs = shown.length + (extra > 0 ? 1 : 0);
    final stackWidth = (discs - 1) * step + ring;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onEdit,
        child: Container(
          constraints: const BoxConstraints(minHeight: kZebuUserCardMinHeight),
          padding: const EdgeInsets.all(ZebuSpacing.s3),
          decoration: BoxDecoration(
            // color: t.accentSoft,
            border: Border.all(color: t.accent, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Row(
            children: [
              SizedBox(
                width: stackWidth,
                height: ring,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * step,
                        child: _Ringed(
                          size: size,
                          ring: t.accentSoft,
                          child: ZebuAvatar.solid(name: shown[i], size: size),
                        ),
                      ),
                    if (extra > 0)
                      Positioned(
                        left: shown.length * step,
                        child: _Ringed(
                          size: size,
                          ring: t.accentSoft,
                          child: Container(
                            width: size,
                            height: size,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.bgTertiary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '+$extra',
                              style: ZebuTextStyles.small(
                                context,
                                color: t.textSlate,
                                fontWeight: ZebuFonts.semiBold,
                              ).copyWith(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              // No names line. Twelve of them ellipsised to a fragment that
              // named three people and implied nothing about the other nine,
              // and its tooltip dumped the whole list across the window. The
              // count is the fact; the picker is where you check the list.
              Expanded(
                child: Text(
                  names.length == 1
                      ? '1 collaborator'
                      : '${names.length} collaborators',
                  style: ZebuTextStyles.body(
                    context,
                    color: t.textPrimary,
                    fontWeight: ZebuFonts.semiBold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ring in the card's own fill, so overlapping discs read as separate.
class _Ringed extends StatelessWidget {
  const _Ringed({required this.size, required this.ring, required this.child});

  final double size;
  final Color ring;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size + 4,
    height: size + 4,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
    child: child,
  );
}

/// The unfilled counterpart of the two cards above.
///
/// A select is 40 px and a filled card is 64, so a field that swapped one for
/// the other grew 24 px the moment you chose someone — every control below it
/// jumping down the page mid-interaction. The empty state is the same card
/// with a placeholder disc and grey text, so choosing changes what the field
/// says and never how much room it takes.
class ZebuPersonPlaceholder extends StatelessWidget {
  const ZebuPersonPlaceholder({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.hasError = false,
  });

  final IconData icon;

  /// The action — "Select a requester", "Add collaborators".
  final String label;

  /// Second line, so the empty card is the same two-line shape as the filled
  /// one rather than a single line floating in a tall box.
  final String hint;

  final VoidCallback onTap;

  /// Turns the outline red, matching every other control on the form.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kZebuUserCardMinHeight),
          padding: const EdgeInsets.all(ZebuSpacing.s3),
          decoration: BoxDecoration(
            border: Border.all(color: hasError ? t.danger : t.accent, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.bgTertiary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: t.iconMuted),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZebuTextStyles.body(
                        context,
                        color: t.textSlate,
                        fontWeight: ZebuFonts.medium,
                      ),
                    ),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZebuTextStyles.small(
                        context,
                        color: t.textSlateMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
