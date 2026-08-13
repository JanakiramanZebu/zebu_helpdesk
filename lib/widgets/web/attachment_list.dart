import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'ellipsis_text.dart';

/// Staged attachments, one full-width row each.
///
/// Replaces a `Wrap` of narrow chips. In a chip the file name had ~180 px and
/// ellipsised to `ca72cf893205fa54349ca381c1519…`, which is the part every
/// export shares — you could not tell two attachments apart, and the size sat
/// inside the same run of text as the name. A row gives the name the full
/// width, puts the size on its own line, and states the type as a coloured tag
/// so the list can be read down the left edge without parsing extensions.
class ZebuAttachmentList extends StatelessWidget {
  const ZebuAttachmentList({
    super.key,
    required this.files,
    required this.onRemove,
  });

  final List<ZebuAttachmentSpec> files;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Two across, never one. A column of one-per-line turned six files
        // into a 400 px wall in the middle of the form — the list is a receipt
        // for what you attached, not the subject of the screen. Not three
        // either: at ~215 px a cell truncated every name past a dozen
        // characters, so the third column cost more than the row it saved.
        final cols = box.maxWidth >= 340 ? 2 : 1;
        const gap = 16.0;

        final lines = <Widget>[];
        for (var i = 0; i < files.length; i += cols) {
          final row = <Widget>[];
          for (var c = 0; c < cols; c++) {
            final k = i + c;
            if (c > 0) row.add(const SizedBox(width: gap));
            row.add(
              Expanded(
                // A short last line keeps its cells the same width as every
                // other line rather than stretching to fill the gap.
                child: k < files.length
                    ? _Cell(spec: files[k], onRemove: () => onRemove(k))
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (lines.isNotEmpty) lines.add(const SizedBox(height: gap));
          // Not `IntrinsicHeight`: the name uses a LayoutBuilder to measure
          // itself, and LayoutBuilder cannot report intrinsic dimensions —
          // it asserts. Every cell is a fixed height anyway, so equal rows
          // come for free and without the extra layout pass.
          lines.add(Row(children: row));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines,
        );
      },
    );
  }
}

class ZebuAttachmentSpec {
  const ZebuAttachmentSpec({required this.name, required this.size});

  final String name;

  /// Already formatted — "277 KB". Empty hides the line.
  final String size;
}

// --- File-type tags ---------------------------------------------------------

/// Colour and label for a file's extension.
///
/// Grouped by what the file *is*, not by extension, so `.jpg` and `.png` read
/// as the same kind of thing in a list. Every tone is a tinted pair; none is a
/// solid badge, so the tag never competes with the file name beside it.
({Color bg, Color ink, String label}) zebuFileTag(String name, ZebuTheme t) {
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 && dot < name.length - 1
      ? name.substring(dot + 1).toLowerCase()
      : '';
  final light = t.isLight;

  ({Color bg, Color ink, String label}) tag(int bg, int ink, [String? l]) => (
    bg: Color(light ? bg : ink).withValues(alpha: light ? 1 : 0.18),
    ink: Color(ink),
    // Four characters is the widest that still reads at 9 px; `jpeg` and
    // `xlsx` fit, and nothing longer earns the width it would take.
    label: (l ?? ext).toUpperCase().substring(0, (l ?? ext).length.clamp(0, 4)),
  );

  const image = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic'};
  const sheet = {'csv', 'xls', 'xlsx', 'ods', 'tsv'};
  const doc = {'doc', 'docx', 'txt', 'rtf', 'md', 'odt'};
  const archive = {'zip', 'rar', '7z', 'tar', 'gz'};
  const media = {'mp4', 'mov', 'avi', 'mkv', 'mp3', 'wav', 'm4a'};

  if (ext == 'pdf') return tag(0xFFFEE4E2, 0xFFB42318);
  if (image.contains(ext)) return tag(0xFFEDEBFE, 0xFF5B47C4);
  if (sheet.contains(ext)) return tag(0xFFE3F5E9, 0xFF1E7A45);
  if (doc.contains(ext)) return tag(0xFFE4ECFB, 0xFF1554C7);
  if (archive.contains(ext)) return tag(0xFFFCEEDC, 0xFF9A5B06);
  if (media.contains(ext)) return tag(0xFFE0F2F3, 0xFF10707A);
  // No extension, or one nobody has a colour for. "FILE" beats an empty tag,
  // which would leave a coloured square saying nothing.
  return tag(0xFFEFF1F4, 0xFF596278, ext.isEmpty ? 'FILE' : ext);
}

/// Two lines of text plus padding. Fixed so a row of cells lines up without
/// an intrinsic-height pass.
const double _kCellHeight = 46;

class _Cell extends StatefulWidget {
  const _Cell({required this.spec, required this.onRemove});
  final ZebuAttachmentSpec spec;
  final VoidCallback onRemove;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final spec = widget.spec;
    final tag = zebuFileTag(spec.name, t);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: _kCellHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hover ? t.bgHover : t.bgElevated,
          border: Border.all(color: t.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(ZebuRadius.rSm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Sized to its label, not fixed. At a fixed 32 px a four-letter
            // tag like DART filled the box edge to edge with no room around
            // it, while PDF swam in it. A minimum keeps the short ones square
            // enough to still read as a column down the left.
            Container(
              constraints: const BoxConstraints(minWidth: 30),
              height: 28,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: tag.bg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ZebuTextStyles.small(
                  context,
                  fontWeight: ZebuFonts.semiBold,
                  color: tag.ink,
                ).copyWith(fontSize: 9, letterSpacing: .3, height: 1),
              ),
            ),
            const SizedBox(width: ZebuSpacing.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ZebuEllipsisText(
                    spec.name,
                    style: ZebuTextStyles.small(
                      context,
                      fontWeight: ZebuFonts.medium,
                      color: t.textPrimary,
                    ).copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 1),
                  if (spec.size.isNotEmpty) ...[
                    Text(
                      spec.size,
                      style: ZebuTextStyles.small(
                        context,
                        color: t.textSlateMuted,
                      ).copyWith(fontSize: 11).withTabularNums(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            _RemoveBtn(onTap: widget.onRemove),
          ],
        ),
      ),
    );
  }
}

class _RemoveBtn extends StatefulWidget {
  const _RemoveBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RemoveBtn> createState() => _RemoveBtnState();
}

class _RemoveBtnState extends State<_RemoveBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: 'Remove',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Neutral, matching `ZebuSelect`'s inline clear — the app's one
              // treatment for "take this back out". Red is for actions that
              // reach the server; dropping a file you have not submitted yet
              // is not one, and a column of red crosses made the list read as
              // a list of errors. Idle is the hover tone at zero alpha, never
              // `Colors.transparent` — that is transparent *black*.
              color: _hover ? t.bgHover : t.bgHover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.close,
              size: 13,
              color: _hover ? t.textSecondary : t.textSlateMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-files bar
// ---------------------------------------------------------------------------

/// The whole Attachments block: heading, add button, and either the staged
/// files or an empty line.
///
/// Shared because the ticket and task forms had a copy each, and they had
/// already drifted on the heading's size, weight and tone.
class ZebuAttachmentsField extends StatelessWidget {
  const ZebuAttachmentsField({
    super.key,
    required this.files,
    required this.onAdd,
    required this.onRemove,
    this.label = 'Attachments',
  });

  final List<ZebuAttachmentSpec> files;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The add button moves. Empty, it sits centred in the space the list
        // would occupy — being the only thing there is what says the section
        // is empty, so no "no files" line is needed. Once files exist that
        // space belongs to them, and the button retreats to the heading row
        // where it stays reachable without pushing the list down.
        Row(
          children: [
            Text(
              label,
              style: ZebuTextStyles.body(
                context,
                color: t.textSlate,
                fontWeight: ZebuFonts.regular,
              ),
            ),
            if (files.isNotEmpty) ...[
              const Spacer(),
              ZebuAddFilesButton(onTap: onAdd),
            ],
          ],
        ),
        const SizedBox(height: ZebuSpacing.s2),
        if (files.isEmpty)
          ZebuAddFilesButton.wide(onTap: onAdd)
        else
          ZebuAttachmentList(files: files, onRemove: onRemove),
      ],
    );
  }
}

/// Height of the add-files control, in both its inline and wide forms. Named
/// so a test can assert "same height in both" without pinning the number.
const double kZebuAddFilesHeight = 36;

/// Dashed button that opens the file picker, sat opposite the section
/// heading.
///
/// A dashed outline rather than a plain text link: the dashes say "nothing
/// here yet" the way the empty state used to, so the block needs no "No files
/// added" line under it. Sized to its label, not to the row — full width it
/// read as the attachment area itself rather than as the control that fills
/// it, and it pushed the list a bar's height further down on every form.
class ZebuAddFilesButton extends StatelessWidget {
  /// Inline: a short dashed pill for the heading row, beside a populated list.
  const ZebuAddFilesButton({
    super.key,
    required this.onTap,
    this.label = 'Add files',
    this.hint,
  }) : wide = false;

  /// Full width: the empty state, spanning the space the list would fill.
  /// The same bar as the inline form — same height, same dashes, same label —
  /// so the control does not change shape as files come and go, only how much
  /// room it takes.
  const ZebuAddFilesButton.wide({
    super.key,
    required this.onTap,
    this.label = 'Add files',
    this.hint,
  }) : wide = true;

  final VoidCallback onTap;

  /// The accent-coloured part — the bit that reads as clickable.
  final String label;

  /// Muted text after [label], for a size cap or accepted types. Omit rather
  /// than guess: a limit stated here and not enforced is worse than none.
  final String? hint;

  /// Spans its parent rather than sizing to its label. See the two
  /// constructors.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      // Cursor only. No fill and no colour step — the same call as the
      // property rows, where a hover state on a control that already reads as
      // a control only made the idle version look half-disabled beside it.
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          // Accent at rest, like every other interactive box in the app —
          // `ZebuSelect` and the dialog inputs both carry a static accent
          // outline rather than earning one on hover or focus.
          painter: _DashedRect(color: t.accent, radius: ZebuRadius.rSm),
          // `alignment` is exactly what makes the wide form fill — a
          // Container with one takes every pixel offered. The inline form
          // must go without it, or it stretches across the heading row.
          child: _bar(context, t),
        ),
      ),
    );
  }
}

extension _AddFilesForms on ZebuAddFilesButton {
  Widget _bar(BuildContext context, ZebuTheme t) => Container(
    height: kZebuAddFilesHeight,
    width: wide ? double.infinity : null,
    alignment: wide ? Alignment.center : null,
    padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.attach_file, size: 16, color: t.accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: ZebuTextStyles.small(
            context,
            fontWeight: ZebuFonts.semiBold,
            color: t.accent,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(
            '· $hint',
            style: ZebuTextStyles.small(
              context,
              color: t.textSlateMuted,
            ).copyWith(fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

/// Dashed rounded rectangle. Flutter has no dashed [BorderSide], so the edge
/// is walked as a path and drawn in segments.
class _DashedRect extends CustomPainter {
  const _DashedRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _on = 4;
  static const double _off = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final end = (d + _on).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, end), pen);
        d = end + _off;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) =>
      old.color != color || old.radius != radius;
}
