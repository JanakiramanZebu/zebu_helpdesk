import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/common.dart';
import '../../../widgets/app_snack.dart';
import '../../../widgets/attachment_tile.dart';
import '../../../widgets/thread_html.dart';
import '../../../widgets/user_avatar.dart';

/// Renders a single thread entry as a WhatsApp-style chat bubble.
///
/// Alignment conveys direction: staff-authored entries (agent replies and
/// internal notes) sit on the right; incoming customer messages sit on the
/// left with the sender's avatar. Type is reinforced by tint — internal notes
/// are amber, agent replies carry a brand tint, customer messages are neutral —
/// plus a small role chip. Each bubble carries a tail (one squared corner) and
/// a trailing timestamp, like a messaging app.
class ThreadEntryTile extends StatelessWidget {
  const ThreadEntryTile({
    super.key,
    required this.entry,
    this.onReply,
    this.onEdit,
    this.onHistory,
    this.showHeader = true,
  });
  final ThreadEntry entry;

  /// Long-press → "Reply" quotes this entry into the composer. When null the
  /// Reply action is hidden (Copy is always available).
  final ValueChanged<ThreadEntry>? onReply;

  /// Long-press → "Edit message" rewrites this entry. Null when the agent may
  /// not edit it (the host applies osTicket's rule), which hides the action.
  final ValueChanged<ThreadEntry>? onEdit;

  /// Long-press → "View history" lists this entry's earlier versions. Only
  /// offered for an entry that actually has some.
  final ValueChanged<ThreadEntry>? onHistory;

  /// Whether to show the sender's avatar + name. False for a message that
  /// follows another from the same sender (grouped, WhatsApp-style), so the
  /// avatar/name aren't repeated and the run reads as one conversation turn.
  final bool showHeader;

  /// WhatsApp-style long-press action sheet: Reply (quote), Edit, History,
  /// Copy — the last always available, the rest wired by the host.
  void _showActions(BuildContext context) {
    final plain = Fmt.stripHtml(entry.bodyHtml ?? entry.body ?? '').trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: AppText.subText(sheetCtx, 'Reply'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onReply!(entry);
                },
              ),
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: AppText.subText(sheetCtx, 'Edit message'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onEdit!(entry);
                },
              ),
            if (onHistory != null && entry.hasHistory)
              ListTile(
                leading: const Icon(Icons.history),
                title: AppText.subText(sheetCtx, 'View history'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onHistory!(entry);
                },
              ),
            ListTile(
              enabled: plain.isNotEmpty,
              leading: const Icon(Icons.copy_outlined),
              title: AppText.subText(sheetCtx, 'Copy text'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await Clipboard.setData(ClipboardData(text: plain));
                if (context.mounted) AppSnack.success(context, 'Copied');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;

    // Staff-authored entries (replies + notes) are "outgoing" → right side.
    final isOwn = isResponse || isNote;

    // Bubble fill: white/neutral for incoming, brand-tinted for agent replies,
    // amber-tinted for internal notes — no border, just a soft shadow so it
    // reads as a chat bubble on the grey conversation background, not a card.
    final Color bg;
    if (isNote) {
      bg = Color.alphaBlend(
        AppTheme.warning.withValues(alpha: isDark ? 0.22 : 0.16),
        isDark ? const Color(0xFF232D36) : scheme.surface,
      );
    } else if (isResponse) {
      bg = scheme.primaryContainer;
    } else {
      bg = isDark ? const Color(0xFF232D36) : scheme.surface;
    }

    final html = entry.bodyHtml ?? entry.body ?? '';
    // A reply that quotes an earlier message carries it as a leading
    // <blockquote>. Split that off so it renders as a chat quote card; left in
    // the HTML it would come out as bare indented text, indistinguishable from
    // the reply itself.
    final quote = splitLeadingQuote(html);
    final bodyHtml = quote?.rest ?? html;
    final isEmpty = Fmt.stripHtml(bodyHtml).trim().isEmpty;

    // Role chip: notes and agent replies are flagged; a plain customer message
    // needs no chip (the avatar + name already identify it).
    ({String label, Color color})? role;
    if (isNote) {
      role = (label: 'Internal note', color: AppTheme.warning);
    } else if (isResponse) {
      role = (label: 'Agent', color: scheme.primary);
    }

    // Name tint matches the sender's deterministic avatar color for incoming
    // turns (WhatsApp group style); role color for staff turns.
    final nameColor = role?.color ?? UserAvatar.colorFor(entry.poster);

    // Rounded bubble with a small "tail" corner on the sender's side; when
    // grouped (no header) the tail is dropped so the run looks continuous.
    const r = Radius.circular(16);
    const tail = Radius.circular(5);
    final radius = BorderRadius.only(
      topLeft: (!isOwn && showHeader) ? tail : r,
      topRight: (isOwn && showHeader) ? tail : r,
      bottomLeft: r,
      bottomRight: r,
    );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.80,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, showHeader ? 8 : 7, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster + role chip (only on the first message of a turn).
              if (showHeader) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AppText.paraText(
                        context,
                        entry.poster,
                        fw: 2,
                        color: nameColor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (role != null) ...[
                      const SizedBox(width: 6),
                      StatusChipDot(label: role.label, color: role.color),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
              ],
              // Optional title, then the message body.
              if (entry.title != null && entry.title!.isNotEmpty) ...[
                AppText.subText(context, entry.title!, fw: 1),
                const SizedBox(height: 4),
              ],
              // The quoted message sits above the reply, like WhatsApp.
              if (quote != null) ...[
                _QuotedMessage(poster: quote.poster, excerpt: quote.excerpt),
                const SizedBox(height: 6),
              ],
              // "(no content)" only when there's nothing at all — a quote with
              // no typed body is still content.
              if (isEmpty && quote == null)
                AppText.subText(
                  context,
                  '(no content)',
                  color: scheme.onSurfaceVariant,
                )
              else if (!isEmpty)
                ThreadHtml(
                  html: bodyHtml,
                  textStyle: theme.textTheme.bodyMedium,
                ),
              if (entry.attachments.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final a in entry.attachments)
                  AttachmentTile(attachment: a),
              ],
              const SizedBox(height: 2),
              // Trailing clock time (WhatsApp-style "3:45 PM"). The day is
              // conveyed by the date separators between turns, so the bubble
              // only needs the time-of-day.
              if (entry.created != null || entry.edited)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Edited", the way the web marks a revised entry; the
                      // editor and edit time sit in the tooltip so the bubble
                      // stays uncluttered.
                      if (entry.edited) ...[
                        Tooltip(
                          message: entry.editor != null
                              ? 'Edited by ${entry.editor} · '
                                    '${Fmt.dateTime(entry.editedAt)}'
                              : 'Edited ${Fmt.dateTime(entry.editedAt)}',
                          child: AppText.captionText(
                            context,
                            'Edited',
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (entry.created != null)
                        AppText.captionText(
                          context,
                          Fmt.time(entry.created),
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: showHeader ? 8 : 2,
        bottom: 1,
      ),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Incoming messages carry the sender's avatar on the left; grouped
          // follow-ups keep the same indent via a spacer so bubbles line up.
          if (!isOwn)
            SizedBox(
              width: 38,
              child: showHeader
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: UserAvatar(name: entry.poster, radius: 15),
                    )
                  : null,
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showActions(context),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

/// The quoted message shown at the top of a reply bubble: an accent rail, a
/// soft tint of the quoted sender's colour, their name, and a two-line excerpt
/// — the same shape as the "replying to" banner above the composer, so what you
/// compose and what you send look like the same thing.
class _QuotedMessage extends StatelessWidget {
  const _QuotedMessage({required this.poster, required this.excerpt});

  /// Quoted sender's display name; null when the quote carries no attribution.
  final String? poster;
  final String excerpt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The quoted sender keeps their own avatar colour (WhatsApp group style),
    // so the card reads as "them" rather than as part of this bubble's text.
    final accent =
        poster == null ? scheme.primary : UserAvatar.colorFor(poster!);
    // Clip so the tinted fill follows the rounded corners; the rail is a left
    // border, which the clip keeps square-ended against the bubble padding.
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poster != null) ...[
                AppText.paraText(
                  context,
                  poster!,
                  fw: 2,
                  color: accent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
              ],
              AppText.paraText(
                context,
                excerpt.isEmpty ? '(attachment)' : excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scrolling conversation: renders [thread] as chat bubbles with WhatsApp
/// touches — a centered date separator when the day changes, and grouping of
/// consecutive messages from the same sender (avatar/name shown once per turn).
///
/// Auto-scrolls to the newest message when the conversation opens and each time
/// a new message arrives (e.g. after sending), so the latest bubble is always
/// in view rather than the list staying pinned at the top.
class ConversationList extends StatefulWidget {
  const ConversationList({
    super.key,
    required this.thread,
    this.onReply,
    this.onEdit,
    this.canEdit,
    this.onHistory,
    this.bottomReserve = 10,
    this.headerController,
  });
  final List<ThreadEntry> thread;
  final ValueChanged<ThreadEntry>? onReply;

  /// Rewrites an entry; offered only for entries [canEdit] accepts.
  final ValueChanged<ThreadEntry>? onEdit;

  /// Whether this agent may edit a given entry (osTicket's own rule: not a
  /// system post, not an agent response, and authored by them / manager /
  /// `thread.edit`). Null means no entry is editable.
  final bool Function(ThreadEntry entry)? canEdit;

  /// Shows an entry's earlier versions.
  final ValueChanged<ThreadEntry>? onHistory;

  /// Extra bottom padding so the newest messages clear the floating composer
  /// that overlays the bottom of the list.
  final double bottomReserve;

  /// The enclosing [NestedScrollView]'s outer (header) controller. Its
  /// `maxScrollExtent` is the collapsing-header distance; subtracting it from
  /// the shared position's max tells us whether the *body* itself overflows.
  /// Without it, a short conversation still auto-scrolls into the header region
  /// on open — collapsing the subject and (with [bottomReserve]) shoving the
  /// lone message off the top, leaving an empty screen. Optional so other
  /// callers keep the plain scroll-to-end behaviour.
  final ScrollController? headerController;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  // The list must ride the scroll controller the enclosing NestedScrollView
  // injects into its body (via PrimaryScrollController), NOT a private one.
  // Using the shared controller is what lets a swipe on the conversation drive
  // the collapsing header; a private controller detaches the list from that
  // coordination and the header never moves.
  ScrollController? _scroll;

  static bool _own(ThreadEntry e) => e.isResponse || e.isNote;
  static DateTime? _day(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    // Land on the newest message when the conversation first opens. The
    // post-frame callback runs after didChangeDependencies has resolved
    // [_scroll], so the controller is ready by the time this fires.
    _scrollToBottom(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll = PrimaryScrollController.maybeOf(context);
  }

  @override
  void didUpdateWidget(ConversationList old) {
    super.didUpdateWidget(old);
    // A new message was appended (send or refresh) — glide to the bottom.
    if (widget.thread.length > old.thread.length) {
      _scrollToBottom(animate: true);
    }
  }

  // The controller is owned by the NestedScrollView, so there's nothing to
  // dispose here.

  // Jump/animate to the end after the new content has been laid out.
  void _scrollToBottom({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scroll;
      // The Conversation and Details lists share this one controller. Only
      // scroll when exactly one is attached (the active tab); bail during a
      // tab-swipe when both are live so we don't yank the other list.
      if (c == null || c.positions.length != 1) return;
      final target = c.position.maxScrollExtent;
      // The shared position's max spans the collapsing header *plus* the body
      // overflow. When the body doesn't overflow (a short conversation that
      // already fits), scrolling would only collapse the header away and — with
      // the composer reserve — push the lone message off the top. So only
      // scroll when the conversation genuinely extends below the fold.
      final headerExtent =
          (widget.headerController?.hasClients ?? false)
              ? widget.headerController!.position.maxScrollExtent
              : 0.0;
      if (target - headerExtent <= 1.0) return;
      if (animate) {
        c.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        c.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? shownDay;
    ThreadEntry? prev;
    for (final e in widget.thread) {
      final day = _day(e.created);
      final isNewDay = day != null && day != shownDay;
      if (isNewDay) {
        children.add(_DateChip(day: day));
        shownDay = day;
      }
      // Group with the previous bubble when it's the same sender on the same
      // side and same day (so the avatar + name aren't repeated).
      final grouped = prev != null &&
          !isNewDay &&
          prev.poster == e.poster &&
          _own(prev) == _own(e);
      children.add(
        ThreadEntryTile(
          entry: e,
          onReply: widget.onReply,
          onEdit: (widget.canEdit?.call(e) ?? false) ? widget.onEdit : null,
          onHistory: widget.onHistory,
          showHeader: !grouped,
        ),
      );
      prev = e;
    }
    return ListView(
      // No explicit controller: attach to the NestedScrollView's injected
      // primary controller so scrolling the messages collapses the header.
      primary: true,
      padding: EdgeInsets.only(top: 4, bottom: widget.bottomReserve),
      children: children,
    );
  }
}

/// Centered "Today / Yesterday / 12 Jun 2026" separator between days.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.day});
  final DateTime day;

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return Fmt.date(day);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF232D36) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: AppText.captionText(
          context,
          _label,
          fw: 1,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A leading `<blockquote>` peeled off a thread entry's HTML: the quoted
/// sender and excerpt to draw as a quote card, plus the [rest] of the body
/// (the actual reply) to render as HTML.
typedef ThreadQuote = ({String? poster, String excerpt, String rest});

// Our own quotes (see [quoteReplyHtml]) are `<blockquote><strong>Name</strong>
// <br>excerpt</blockquote><p></p>`, so match that shape leniently enough to
// also catch a quote a web client wrote.
final _leadingQuoteRe = RegExp(
  r'^\s*<blockquote[^>]*>(.*?)</blockquote>',
  caseSensitive: false,
  dotAll: true,
);
final _quotePosterRe = RegExp(
  r'^\s*<(strong|b)>(.*?)</\1>\s*(?:<br\s*/?>)?',
  caseSensitive: false,
  dotAll: true,
);
// The composer separates the quote from the typed reply with an empty
// paragraph; drop it so the card doesn't sit above a blank line.
final _leadingBlankRe = RegExp(
  r'^(?:\s|<br\s*/?>|<p>\s*(?:<br\s*/?>)?\s*</p>)+',
  caseSensitive: false,
);

// Collapses the newlines/tabs of a stripped body into single spaces so the
// one-line reply banner reads as running text.
final _whitespaceRe = RegExp(r'\s+');

/// Splits a leading quote off [html], or returns null when there isn't one.
ThreadQuote? splitLeadingQuote(String html) {
  final m = _leadingQuoteRe.firstMatch(html);
  if (m == null) return null;
  final inner = m.group(1) ?? '';
  // A forwarded email chain nests blockquotes, which the non-greedy match would
  // cut in the wrong place — leave those to the HTML renderer.
  if (inner.toLowerCase().contains('<blockquote')) return null;
  final p = _quotePosterRe.firstMatch(inner);
  final poster = p == null ? '' : Fmt.stripHtml(p.group(2));
  final excerpt = Fmt.stripHtml(p == null ? inner : inner.substring(p.end));
  if (poster.isEmpty && excerpt.isEmpty) return null;
  return (
    poster: poster.isEmpty ? null : poster,
    excerpt: excerpt,
    rest: html.substring(m.end).replaceFirst(_leadingBlankRe, ''),
  );
}

/// Builds the HTML `<blockquote>` prepended to a reply that quotes [entry],
/// mirroring how email/WhatsApp show the message being replied to. The excerpt
/// is plain-text (HTML-escaped) and capped so long quotes stay compact.
String quoteReplyHtml(ThreadEntry entry) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final plain = Fmt.stripHtml(entry.bodyHtml ?? entry.body ?? '').trim();
  final excerpt = plain.characters.length > 220
      ? '${plain.characters.take(220)}…'
      : plain;
  return '<blockquote><strong>${esc(entry.poster)}</strong><br>'
      '${esc(excerpt).replaceAll('\n', '<br>')}</blockquote><p></p>';
}

/// The "replying to …" banner shown above the composer input.
///
/// Deliberately **one line tall**: the composer already eats the bottom of the
/// screen, so the quote is compressed to `rail | ↩ Poster · excerpt | ✕` with
/// the excerpt running inline after the name instead of wrapping to a second
/// row. Tapping the close button invokes [onCancel] to drop the quote.
class ReplyQuotePreview extends StatelessWidget {
  const ReplyQuotePreview({
    super.key,
    required this.entry,
    required this.onCancel,
    required this.accent,
  });

  final ThreadEntry entry;
  final VoidCallback onCancel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final excerpt = Fmt.stripHtml(entry.bodyHtml ?? entry.body ?? '')
        .replaceAll(_whitespaceRe, ' ')
        .trim();
    return Row(
      children: [
        // Accent rail — the quote marker, shrunk from a full bordered card to
        // a 3px bar so it costs no vertical space of its own.
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.reply_rounded, size: 13, color: accent),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: entry.poster,
                  style: AppText.style(
                    context,
                    fontSize: 12,
                    fw: 2,
                    color: accent,
                  ),
                ),
                TextSpan(
                  text: '  ${excerpt.isEmpty ? '(attachment)' : excerpt}',
                  style: AppText.style(
                    context,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // A bare 24px tap target instead of an IconButton, whose 40px minimum
        // was what forced the old banner two lines tall. It carries its own
        // transparent Material so the ripple isn't clipped away by the frosted
        // composer card this banner sits inside.
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onCancel,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny labeled dot/pill used inline (e.g. "Note", "Agent").
class StatusChipDot extends StatelessWidget {
  const StatusChipDot({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
