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
    this.showHeader = true,
  });
  final ThreadEntry entry;

  /// Long-press → "Reply" quotes this entry into the composer. When null the
  /// Reply action is hidden (Copy is always available).
  final ValueChanged<ThreadEntry>? onReply;

  /// Whether to show the sender's avatar + name. False for a message that
  /// follows another from the same sender (grouped, WhatsApp-style), so the
  /// avatar/name aren't repeated and the run reads as one conversation turn.
  final bool showHeader;

  /// WhatsApp-style long-press action sheet: Reply (quote) + Copy.
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
    final isEmpty = Fmt.stripHtml(html).trim().isEmpty;

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
              if (isEmpty)
                AppText.subText(
                  context,
                  '(no content)',
                  color: scheme.onSurfaceVariant,
                )
              else
                ThreadHtml(html: html, textStyle: theme.textTheme.bodyMedium),
              if (entry.attachments.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final a in entry.attachments)
                  AttachmentTile(attachment: a),
              ],
              const SizedBox(height: 2),
              // Trailing clock time (WhatsApp-style "3:45 PM"). The day is
              // conveyed by the date separators between turns, so the bubble
              // only needs the time-of-day.
              if (entry.created != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: AppText.captionText(
                    context,
                    Fmt.time(entry.created),
                    color: scheme.onSurfaceVariant,
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
    this.bottomReserve = 10,
    this.headerController,
  });
  final List<ThreadEntry> thread;
  final ValueChanged<ThreadEntry>? onReply;

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
        ThreadEntryTile(entry: e, onReply: widget.onReply, showHeader: !grouped),
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

/// The "replying to …" banner shown above the composer input. Tapping the
/// close button invokes [onCancel] to drop the quote.
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
    final excerpt =
        Fmt.stripHtml(entry.bodyHtml ?? entry.body ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.paraText(context, 'Replying to ${entry.poster}',
                      fw: 2, color: accent),
                  const SizedBox(height: 1),
                  AppText.paraText(
                    context,
                    excerpt.isEmpty ? '(attachment)' : excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cancel reply',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
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
