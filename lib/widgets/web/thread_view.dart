import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../models/common.dart';
import '../../res/zebu_spacing.dart';
import '../../res/zebu_status_colors.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'bubble_shape.dart';
import 'dots_loader.dart';
import 'hatched_card.dart';
import 'zebu_avatar.dart';

/// The conversation half of a ticket or task detail panel.
///
/// Tickets and tasks render the *same* `ThreadEntry` model — same M/R/N
/// types, same attachments, same posters — so they share one implementation
/// rather than two that drift. Both panels previously carried their own copy
/// of this, and the project has already been bitten by that pattern: the
/// status-tone map existed in four copies, one of which still had a bug the
/// others had lost.
///
/// Call [zebuThreadItems] to get the flat widget list — date dividers
/// included — and splat it into whatever scrollable the panel already uses.

/// Horizontal space held back from every bubble so the far side always reads
/// as empty gutter — the gutter *is* the directional cue. Deliberately small:
/// the tint and the type tag already say which side an entry is on twice
/// over, and agents read long quoted email in this column, so width is the
/// scarcest thing on the screen.
const double _kBubbleGutter = 160;

/// Inline image preview box. Wide enough that a screenshot of a form or
/// an error dialog is legible without opening it, short enough that a tall
/// portrait image can't push the rest of the thread off-screen.
const double _kPreviewWidth = 280;

/// Attachment chip width. Fixed so a message carrying several files
/// renders a tidy stack rather than a ragged staircase.
const double _kChipWidth = 280;
const double _kPreviewHeight = 180;

/// Avatar diameter plus the gap to the bubble. Reserved on the sender's side
/// even when the avatar is hidden by grouping, so a run of bubbles keeps one
/// straight edge instead of stepping in and out.
const double _kAvatarSize = 32;
const double _kAvatarGap = ZebuSpacing.s3;

/// Consecutive entries by the same author, of the same type, closer together
/// than this collapse into one visual run: avatar and name appear once, and
/// the follow-ups are bare bubbles. Without it a four-reply burst repeats the
/// same name and face four times and reads noisier than a plain list.
const Duration _kGroupWindow = Duration(minutes: 10);

bool _groupsWith(ThreadEntry entry, ThreadEntry? prev) {
  if (prev == null) return false;
  if (prev.poster != entry.poster || prev.type != entry.type) return false;
  final a = prev.created, b = entry.created;
  if (a == null || b == null) return false;
  return b.difference(a).abs() <= _kGroupWindow;
}

/// True when the body says nothing the attachment chips don't already say.
///
/// osTicket fills the body with `Attachment: <filename>` when a file is sent
/// without a message, so the name lands twice — once as body copy and again
/// on the chip directly beneath it.
bool _isAttachmentEcho(String plain, List<Attachment> files) {
  if (files.isEmpty) return false;
  var s = plain.trim();
  final m = RegExp(r'^Attachments?\s*:\s*', caseSensitive: false).firstMatch(s);
  if (m == null) return false;
  s = s.substring(m.end).trim();
  for (final f in files) {
    s = s.replaceFirst(f.name, '').trim();
    s = s.replaceFirst(RegExp(r'^[,;]\s*'), '');
  }
  // Only suppress on an exact echo — a real message that merely opens with
  // the word "Attachment:" must still be shown.
  return s.isEmpty;
}

/// Reveals an entry's exact timestamp on hover. The header only carries a
/// relative time ("a day ago"), and grouped follow-ups have no header at all.
class _Dated extends StatelessWidget {
  const _Dated({required this.created, required this.child});
  final DateTime? created;
  final Widget child;

  @override
  Widget build(BuildContext context) => created == null
      ? child
      : Tooltip(
          message: Fmt.dateTime(created),
          waitDuration: const Duration(milliseconds: 500),
          child: child,
        );
}

/// The thread as a flat widget list, with a [ZebuDateDivider] wherever the day
/// changes. Grouping is suppressed across a divider — a run that straddles
/// midnight would otherwise lose its author to the divider it sits under.
List<Widget> zebuThreadItems(List<ThreadEntry> thread) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (var i = 0; i < thread.length; i++) {
    final e = thread[i];
    var divided = false;
    final d = e.created;
    if (d != null) {
      final day = DateTime(d.year, d.month, d.day);
      if (day != lastDay) {
        out.add(ZebuDateDivider(day: day));
        lastDay = day;
        divided = true;
      }
    }
    out.add(
      ZebuThreadRow(entry: e, prev: (divided || i == 0) ? null : thread[i - 1]),
    );
  }
  return out;
}

/// A day heading between thread entries — hairlines either side of an
/// uppercase label.
///
/// A ticket can span months. Without this the thread is an undifferentiated
/// run of entries and there is nothing to anchor "when did this go quiet" to,
/// which is exactly the question an agent opens an old ticket to answer.
class ZebuDateDivider extends StatelessWidget {
  const ZebuDateDivider({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rule = Expanded(child: Container(height: 1, color: t.borderSubtle));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s5,
        ZebuSpacing.s4,
        ZebuSpacing.s1,
      ),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            child: Text(
              Fmt.dayLabel(day).toUpperCase(),
              style: ZebuTextStyles.eyebrow(
                context,
                color: t.textSlateMuted,
              ).copyWith(letterSpacing: 0.6),
            ),
          ),
          rule,
        ],
      ),
    );
  }
}

class ZebuThreadRow extends StatelessWidget {
  const ZebuThreadRow({super.key, required this.entry, this.prev});
  final ThreadEntry entry;

  /// The entry rendered directly above this one, for grouping. Null for the
  /// first row in the thread and for the first row under a date divider.
  final ThreadEntry? prev;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final isNote = entry.isNote;

    // Side comes from osTicket's own M / R / N: the requester's messages on
    // the left, everything the desk produced — replies and internal notes —
    // on the right. Keying off `type` rather than off the signed-in agent
    // means the thread renders identically for everyone, and a second
    // agent's reply doesn't jump sides depending on who opened the ticket.
    final onRight = !entry.isMessage;
    final grouped = _groupsWith(entry, prev);

    // Body ink per surface: the default body grey goes muddy on the blue
    // reply tint and on the note's warm hatch, so each carries its own.
    final ink = isNote
        ? t.noteBody
        : onRight
        ? t.bubbleOutboundInk
        : t.bubbleInboundInk;

    // The name / label / time strip lives *outside* the surface. Inside, it
    // set the surface's intrinsic width, so a one-word reply rendered as wide
    // as a full paragraph and the layout read as cards-pushed-right rather
    // than as bubbles. Out here the surface shrink-wraps its body, and short
    // messages finally look short.
    // Header parts in reading order for the left side. On the desk's side the
    // whole strip is reversed so the name still lands next to its avatar —
    // otherwise the timestamp sits against the face and the name drifts off
    // toward the middle of the column.
    final headerParts = <Widget>[
      Flexible(
        child: Text(
          entry.poster,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZebuTextStyles.body(
            context,
            color: t.textPrimary,
            fontWeight: ZebuFonts.semiBold,
          ),
        ),
      ),
      // No REPLY / MESSAGE tag: by the time a row is drawn its type has been
      // stated three times over — which side it sits on, which tint it
      // carries, and which way its tail points. A note keeps its label
      // because the hatch is learned, not innate, and because getting a note
      // wrong is the one mistake on this screen that reaches a customer.
      if (isNote)
        Tooltip(
          message: 'Not visible to the requester',
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            'INTERNAL NOTE',
            style: ZebuTextStyles.eyebrow(
              context,
              color: t.note,
            ).copyWith(letterSpacing: 0.6),
          ),
        ),
    ];
    final ordered = onRight ? headerParts.reversed.toList() : headerParts;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(width: ZebuSpacing.s2),
            ordered[i],
          ],
        ],
      ),
    );

    final body = _body(context, t, ink);

    // A note is a hatched, dashed card rather than a filled bubble. It sits
    // on the desk's side like a reply — it *was* written by the desk — but a
    // note that looks like a reply is a note that eventually gets sent as
    // one, so the surface has to stay unmistakable. Hatching is the one
    // texture nothing else in the app uses, which is what makes it survive
    // being seen out of the corner of the eye.
    // Shared by both surfaces: a speech-bubble outline with the tail on the
    // speaker's side. The tail is why the avatar sits at the *bottom* of the
    // row rather than beside the name — a tail that points at empty gutter is
    // worse than no tail at all.
    final shape = BubbleShape(tailOnRight: onRight);

    final surface = isNote
        ? HatchedCard(
            baseColor: t.noteHatchBase,
            stripeColor: t.noteHatchStripe,
            // No edge: every other surface in the thread lost its hairline
            // when both sides gained a fill, and a dashed outline on the one
            // remaining bordered card made it read as a form field. The hatch
            // is doing the warning on its own.
            shape: shape,
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s4,
              vertical: ZebuSpacing.s3,
            ),
            child: body,
          )
        : Container(
            decoration: ShapeDecoration(
              // Fill only, no hairline. Once both sides carry a fill the
              // border is a second edge doing the first one's job, and the
              // pair stops reading as speech and starts reading as boxes.
              color: onRight ? t.bubbleOutbound : t.bubbleInbound,
              shape: shape,
            ),
            // ShapeDecoration already insets by the shape's dimensions, which
            // reserve the tail strip, so this is the copy padding only.
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s4,
              vertical: ZebuSpacing.s3,
            ),
            child: body,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        // A run reads as one block: tight between its rows, open before the
        // next speaker.
        grouped ? 3 : ZebuSpacing.s4,
        ZebuSpacing.s4,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final gutter = (c.maxWidth * 0.12).clamp(0.0, _kBubbleGutter);
          final maxSurface = (c.maxWidth - gutter - _kAvatarSize - _kAvatarGap)
              .clamp(0.0, c.maxWidth);
          // Always occupied, but only painted once per run. A note's avatar
          // is warm rather than the author's hashed identity colour — on a
          // note, "this is private" outranks "this is Venkat".
          final avatarSlot = SizedBox(
            width: _kAvatarSize,
            child: grouped
                ? null
                : ZebuAvatar(
                    name: entry.poster,
                    fill: isNote ? t.noteAvatarBg : null,
                    ink: isNote ? t.note : null,
                  ),
          );
          return Row(
            // Bottom-aligned so the avatar meets the tail. The name and time
            // still sit above the bubble, so a tall message puts a little air
            // between the two — which is the Telegram / WhatsApp arrangement
            // and reads as the face belonging to the last thing said.
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: onRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!onRight) ...[avatarSlot, const SizedBox(width: _kAvatarGap)],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSurface),
                  child: Column(
                    // The header and the surface hang off the same edge — the
                    // one nearest the avatar — so a run of differently sized
                    // rows still has one straight side.
                    crossAxisAlignment: onRight
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [if (!grouped) header, surface],
                  ),
                ),
              ),
              if (onRight) ...[const SizedBox(width: _kAvatarGap), avatarSlot],
            ],
          );
        },
      ),
    );
  }

  /// Message text plus any attachment chips. Identical inside a bubble and
  /// inside a note card, so it is built once and handed to whichever surface
  /// wins.
  Widget _body(BuildContext context, ZebuTheme t, Color ink) {
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);
    final echo = _isAttachmentEcho(plain, entry.attachments);
    final hasFiles = entry.attachments.isNotEmpty;

    final clockStyle = ZebuTextStyles.small(
      context,
      color: t.textSlateMuted,
    ).withTabularNums();
    final clockText = entry.created == null ? null : Fmt.time(entry.created);

    final bodyStyle = ZebuTextStyles.body(
      context,
      color: ink,
    ).copyWith(height: 1.55);

    // The clock rides the end of the last line when it fits there, and drops
    // to its own line only when it doesn't — the WhatsApp behaviour. It works
    // by appending an invisible spacer the clock's own width to the text, so
    // the layout reserves the room, and then painting the real clock in the
    // corner the spacer just cleared. Only plain-text bodies qualify: an HTML
    // body can't take a trailing span, and a message with attachments has a
    // chip below the text for the clock to sit under anyway.
    final inline =
        clockText != null &&
        !echo &&
        !hasFiles &&
        !html.contains('<') &&
        plain.trim().isNotEmpty;

    if (inline) {
      final gap =
          _measureWidth(context, clockText, clockStyle) + ZebuSpacing.s3;
      return IntrinsicWidth(
        child: _Dated(
          created: entry.created,
          child: Stack(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: plain),
                    WidgetSpan(child: SizedBox(width: gap, height: 1)),
                  ],
                ),
                style: bodyStyle,
              ),
              // Positioned, so it costs the layout nothing beyond the spacer
              // above — the Stack sizes to the text alone.
              Positioned(
                right: 0,
                bottom: 1,
                child: Text(clockText, style: clockStyle),
              ),
            ],
          ),
        ),
      );
    }

    // Sizes the column to its widest child before the clock is right-aligned
    // inside it. Without this the `Align` below takes every pixel it is
    // offered, so a two-letter reply rendered as wide as the width cap. The
    // outer ConstrainedBox still caps it, so long copy wraps as before.
    return IntrinsicWidth(
      child: Column(
        // Body copy stays left-aligned on both sides — ragged-left paragraphs
        // are unreadable, and the row's position already carries direction.
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // osTicket writes "Attachment: <name>" as the body when a file is
          // sent with no message. Rendering that *and* the chip prints the same
          // filename twice, one line apart, which reads as a stutter.
          if (!echo) ...[
            // The exact timestamp hangs off the body text alone, not the whole
            // surface — wrapping the surface meant hovering an attachment
            // popped the date tooltip over the thing you were trying to see.
            _Dated(
              created: entry.created,
              child: plain.trim().isEmpty
                  ? Text('(no content)', style: ZebuTextStyles.small(context))
                  : html.contains('<')
                  ? ZebuHtmlBody(html: html)
                  : Text(plain, style: bodyStyle),
            ),
            if (hasFiles) const SizedBox(height: ZebuSpacing.s3),
          ],
          if (hasFiles)
            Wrap(
              spacing: ZebuSpacing.s2,
              runSpacing: ZebuSpacing.s2,
              children: [
                for (final a in entry.attachments)
                  ZebuAttachment(attachment: a),
              ],
            ),
          if (clockText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(clockText, style: clockStyle),
              ),
            ),
        ],
      ),
    );
  }

  /// Laid-out width of [text] in [style], for reserving space the layout
  /// engine can't be asked for directly.
  static double _measureWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }
}

/// One attachment: an inline preview for images, a compact chip for
/// everything else.
///
/// Images get the preview because a screenshot *is* the message — a customer
/// reporting a bug sends a picture of it, and forcing a round-trip to a new
/// browser tab to see it is the single most expensive interaction in the
/// thread. Non-image types have nothing to show until they're opened, so a
/// chip is the honest representation.
class ZebuAttachment extends StatefulWidget {
  const ZebuAttachment({super.key, required this.attachment});
  final Attachment attachment;

  @override
  State<ZebuAttachment> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<ZebuAttachment> {
  /// Set once [Image.network] fails, so the row falls back to the chip
  /// permanently instead of retrying the broken URL on every rebuild.
  bool _previewFailed = false;

  IconData get _icon {
    final t = widget.attachment.type ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (t.contains('word') || t.contains('document')) {
      return Icons.description_outlined;
    }
    if (t.contains('zip') || t.contains('rar') || t.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file;
  }

  /// Badge tint, keyed off the file type. A red PDF and a green spreadsheet
  /// are findable in a long thread the way a uniformly blue tile is not — the
  /// eye sorts by colour before it reads a filename.
  Color _badgeTone(ZebuTheme t) {
    final m = widget.attachment.type ?? '';
    if (m.contains('pdf')) return t.danger;
    if (m.startsWith('image/')) return t.accent;
    if (m.contains('sheet') || m.contains('excel')) return ZebuTheme.success;
    if (m.contains('word') || m.contains('document')) return t.accent;
    return t.iconMuted;
  }

  /// Short uppercase extension for the badge — PDF, XLSX, PNG. Null when the
  /// filename has none, in which case the glyph stands in.
  String? get _ext {
    final n = widget.attachment.name;
    final dot = n.lastIndexOf('.');
    if (dot <= 0 || n.length - dot > 6) return null;
    return n.substring(dot + 1).toUpperCase();
  }

  Future<void> _open() async {
    final a = widget.attachment;
    final url = a.downloadUrl ?? a.streamUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    // `downloadUrl` is the signed absolute `file.php` URL — it carries its own
    // HMAC, so an <img> can fetch it without our bearer token. `streamUrl`
    // needs an Authorization header and so can't be handed to Image.network.
    final canPreview = a.isImage && a.downloadUrl != null && !_previewFailed;
    return MouseRegion(
      // Cursor only, no hover styling. An attachment sits inside a tinted
      // bubble, so a hover fill would be a third surface colour flickering
      // inside a second one — the pointer is affordance enough.
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: canPreview ? _buildPreview(context) : _buildChip(context),
      ),
    );
  }

  /// Image: a media card — the picture itself, with a caption strip under it
  /// carrying the name, size, and open-externally affordance.
  Widget _buildPreview(BuildContext context) {
    final t = ZebuTheme.of(context);
    final a = widget.attachment;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kPreviewWidth,
              maxHeight: _kPreviewHeight,
            ),
            child: Image.network(
              a.downloadUrl!,
              fit: BoxFit.cover,
              width: _kPreviewWidth,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      width: _kPreviewWidth,
                      height: _kPreviewHeight,
                      color: t.surfaceMuted,
                      alignment: Alignment.center,
                      child: const DotsLoader(),
                    ),
              // A blocked or expired URL must not leave a broken-image box in
              // the thread — drop to the chip, which still opens fine.
              errorBuilder: (context, _, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _previewFailed = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
          Container(
            width: _kPreviewWidth,
            color: t.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s2,
              vertical: 6,
            ),
            child: _caption(context),
          ),
        ],
      ),
    );
  }

  /// Everything else: icon tile, name, size, open glyph.
  Widget _buildChip(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      width: _kChipWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      ),
      child: Row(
        children: [
          _badge(context),
          const SizedBox(width: ZebuSpacing.s3),
          _caption(context),
        ],
      ),
    );
  }

  /// 32x32 type tile: the extension in a tinted square, or the glyph when the
  /// filename has none.
  Widget _badge(BuildContext context) {
    final t = ZebuTheme.of(context);
    final tone = _badgeTone(t);
    final ext = _ext;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: ext == null
          ? Icon(_icon, size: 17, color: tone)
          : Text(
              // Four characters is the widest that fits without shrinking
              // past legibility.
              ext.length > 4 ? ext.substring(0, 4) : ext,
              style: ZebuTextStyles.caption(
                context,
                color: zebuOnTint(tone, t),
                fontWeight: ZebuFonts.bold,
              ).copyWith(fontSize: ext.length > 3 ? 8 : 9),
            ),
    );
  }

  /// Name over size, with the download affordance trailing. Two lines rather
  /// than one row: at a fixed chip width the filename gets the whole line
  /// instead of competing with the size for it, so far less of it is lost to
  /// the ellipsis.
  Widget _caption(BuildContext context) {
    final t = ZebuTheme.of(context);
    final a = widget.attachment;
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // One ellipsis, at the end, plus the full name on hover.
                // Shortening the string ourselves *and* letting the layout
                // clip it produced two ellipses in the same filename
                // ("ChatGPT Image...36_32 PM...."), which reads as a bug.
                // Losing the extension costs nothing now that the badge
                // states the type.
                Tooltip(
                  message: a.name,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: ZebuTextStyles.small(
                      context,
                      color: t.textPrimary,
                      fontWeight: ZebuFonts.semiBold,
                    ),
                  ),
                ),
                if (a.size != null)
                  Text(
                    Fmt.fileSize(a.size),
                    style: ZebuTextStyles.caption(
                      context,
                      color: t.textSlateMuted,
                    ).withTabularNums(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZebuSpacing.s2),
          Icon(Icons.download_outlined, size: 16, color: t.iconMuted),
        ],
      ),
    );
  }
}

/// Floors font sizes at 13 px and caps bold weight at 600, and lets the
/// parent's max width wrap long paragraphs naturally.
class ZebuHtmlBody extends StatelessWidget {
  const ZebuHtmlBody({super.key, required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: HtmlWidget(
        html,
        textStyle: ZebuTextStyles.body(context),
        // Anchor taps aren't clickable by default — HtmlWidget hands the
        // URL to us so we can launch it. `mode: externalApplication` on
        // web opens a new browser tab.
        onTapUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null) return false;
          return launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        customStylesBuilder: (element) {
          switch (element.localName) {
            case 'b':
            case 'strong':
              return {'font-weight': '600'};
            case 'small':
            case 'sub':
            case 'sup':
              return {'font-size': '13px'};
            case 'a':
              // Match the composer's link styling so a link reads the
              // same before and after send.
              return {
                'color': '#0037B7', // ZebuTheme.accent
                'text-decoration': 'underline',
              };
            default:
              return null;
          }
        },
      ),
    );
  }
}
