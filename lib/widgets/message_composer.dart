import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../core/api/api_exception.dart';
import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';
import '../features/tickets/widgets/thread_entry_tile.dart'
    show ReplyQuotePreview, quoteReplyHtml;
import '../models/canned.dart';
import '../models/common.dart';
import '../providers.dart';
import 'app_sheet.dart';
import 'composer_actions.dart';
import 'glass.dart';
import 'pickers.dart';

/// Signature the host implements to actually deliver a composed message: it
/// performs the reply/note API call (plus any list refresh) and returns whether
/// it succeeded. Keeping the transport out here lets the same composer serve
/// tickets, tasks or any future thread without knowing the repository.
typedef ComposerSender =
    Future<bool> Function({
      required bool note,
      required String html,
      required List<MultipartFile> files,
    });

/// Modern, WhatsApp/Slack-style bottom message composer.
///
/// A fixed, softly-elevated bottom bar that hosts a rounded [ChatInputField]
/// with a "+" actions button and emoji picker tucked inside (growing 1â†’5
/// lines), a premium animated [SendButton], and a compact [InlineModeToggle]
/// suffix for switching between a public reply and an internal note. The rich
/// body is backed by a [FleatherController] so canned responses / FAQ articles
/// can still be inserted as formatted HTML.
///
/// The widget owns its editor, focus, attachments and mode; the host only wires
/// [onSend] (transport) and, for tickets, [expandCanned] (variable expansion).
class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    this.replyTo,
    this.onClearReply,
    this.expandCanned,
    this.hintReply = 'Reply to this ticket...',
    this.hintNote = 'Add an internal note...',
    this.keepFocusAfterSend = true,
  });

  /// Delivers the message. Should surface its own errors and return false on
  /// failure so the composer keeps the draft.
  final ComposerSender onSend;

  /// When set, the composer quotes this entry and shows a "replying to" banner.
  final ThreadEntry? replyTo;
  final VoidCallback? onClearReply;

  /// Optional hook to expand a canned response's variables before it's inserted
  /// (tickets expand against the ticket; tasks insert the raw body). Returns the
  /// expanded HTML.
  final Future<String> Function(CannedResponse canned)? expandCanned;

  /// Placeholder shown in reply mode / note mode respectively.
  final String hintReply;
  final String hintNote;

  /// Keep the keyboard up after a successful send (chat-app behaviour).
  final bool keepFocusAfterSend;

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final FleatherController _controller = FleatherController();
  final FocusNode _focus = FocusNode();
  final List<PlatformFile> _files = [];
  bool _note = false; // false = public reply, true = internal note
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onChange);
    _controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(MessageComposer old) {
    super.didUpdateWidget(old);
    // A new reply target: switch to Reply mode and focus so the user can type.
    if (widget.replyTo != null && widget.replyTo != old.replyTo) {
      _note = false;
      _focus.requestFocus();
    }
  }

  // Rebuild so the hint, send-enabled state and toolbar track edits/focus.
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onChange);
    _controller.removeListener(_onChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isEmpty => _controller.document.toPlainText().trim().isEmpty;

  void _clearDocument() {
    final len = _controller.document.length;
    if (len > 1) {
      _controller.replaceText(
        0,
        len - 1,
        '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  /// Opens the "+" actions sheet (attach / canned / FAQ / expand) and runs the
  /// chosen action. Consolidates every insert/attach entry point behind one
  /// button, WhatsApp-style.
  Future<void> _openPlusMenu() async {
    final action = await showAppSheet<_PlusAction>(
      context: context,
      builder: (_) => const _PlusMenuSheet(),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PlusAction.camera:
        await _pickFrom(AttachSource.camera);
      case _PlusAction.photo:
        await _pickFrom(AttachSource.photos);
      case _PlusAction.file:
        await _pickFrom(AttachSource.files);
      case _PlusAction.canned:
        await _insertCanned();
        if (mounted) _focus.requestFocus();
      case _PlusAction.faq:
        await _insertFaq();
        if (mounted) _focus.requestFocus();
    }
  }

  /// Picks attachments from [source] and appends any new ones.
  Future<void> _pickFrom(AttachSource source) async {
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.name == f.name)) _files.add(f);
      }
    });
  }

  /// Opens the emoji picker and refocuses the editor when it closes.
  Future<void> _openEmojiPicker() async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _EmojiPickerSheet(onSelect: _insertEmoji),
    );
    if (mounted) _focus.requestFocus();
  }

  /// Inserts a plain-text [emoji] at the current cursor position.
  void _insertEmoji(String emoji) {
    final doc = _controller.document;
    final index = _controller.selection.baseOffset.clamp(0, doc.length - 1);
    _controller.replaceText(
      index,
      0,
      emoji,
      selection: TextSelection.collapsed(offset: index + emoji.length),
    );
  }

  /// Picks a canned response, optionally expands its variables, and inserts the
  /// result at the cursor.
  Future<void> _insertCanned() async {
    final canned = await pickCannedResponse(context, ref);
    if (canned == null || !mounted) return;
    var html = canned.body;
    final expand = widget.expandCanned;
    if (expand != null) {
      try {
        final expanded = await expand(canned);
        if (expanded.trim().isNotEmpty) html = expanded;
      } on ApiException {
        // Fall back to the raw (un-expanded) body.
      }
    }
    if (!mounted) return;
    insertRichHtml(_controller, html);
  }

  /// Picks a knowledgebase article and inserts its answer at the cursor.
  Future<void> _insertFaq() async {
    final faq = await pickFaqArticle(context, ref);
    if (faq == null || !mounted) return;
    var html = faq.answer ?? '';
    if (html.trim().isEmpty) {
      try {
        final full = await ref.read(faqRepositoryProvider).get(faq.id);
        html = full.answer ?? '';
      } on ApiException {
        // Nothing to insert.
      }
    }
    if (!mounted || html.trim().isEmpty) return;
    insertRichHtml(_controller, html);
  }

  /// Encodes the document (as HTML) plus attachments and hands them to the host.
  /// Returns true on success so the fullscreen editor knows when to close.
  Future<bool> _send() async {
    final empty = _isEmpty;
    if ((empty && _files.isEmpty) || _sending) return false;
    setState(() => _sending = true);
    try {
      final files = [
        for (final f in _files)
          if (f.bytes != null)
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
      ];
      final typed = empty ? '' : parchmentHtml.encode(_controller.document);
      // Prepend the quoted message (if replying) so the reply carries context.
      final reply = widget.replyTo;
      final body = reply != null ? '${quoteReplyHtml(reply)}$typed' : typed;
      final ok = await widget.onSend(note: _note, html: body, files: files);
      if (!ok) return false;
      _clearDocument();
      widget.onClearReply?.call();
      if (mounted) setState(() => _files.clear());
      if (widget.keepFocusAfterSend && mounted) _focus.requestFocus();
      return true;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFullscreen() async {
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenEditor(
          controller: _controller,
          note: _note,
          onSend: _send,
          onInsertCanned: _insertCanned,
          onInsertFaq: _insertFaq,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _note ? AppTheme.warning : scheme.primary;
    final canSend = !_isEmpty || _files.isNotEmpty;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Each paragraph in the document ends with a newline, so the newline count
    // is the number of text lines. Past 2 the field is tall enough that the
    // side controls read better stacked into a column than crammed in a row.
    final lineCount = '\n'
        .allMatches(_controller.document.toPlainText())
        .length;
    final stacked = lineCount > 2;

    // The leading (+/emoji) and trailing (expand/mode) controls, reused whether
    // we lay them out in a row (compact) or a column (tall field, [stacked]).
    final addButton = ComposerIconButton(
      icon: Icons.add_rounded,
      tooltip: 'Add',
      size: 24,
      onTap: _openPlusMenu,
    );
    final emojiButton = ComposerIconButton(
      icon: Icons.emoji_emotions_outlined,
      tooltip: 'Emoji',
      size: 21,
      onTap: _openEmojiPicker,
    );
    final expandButton = ComposerIconButton(
      icon: Icons.open_in_full_rounded,
      tooltip: 'Expand editor',
      size: 18,
      onTap: _openFullscreen,
    );
    final modeToggle = InlineModeToggle(
      note: _note,
      onChanged: (v) => setState(() => _note = v),
    );

    // The composer no longer paints a full-width bar: it floats over the
    // conversation as a rounded glass pill (matching the bottom nav bar), with
    // the formatting toolbar riding on its own floating pill just below.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        6,
        12,
        (bottomInset > 0 ? bottomInset : 8) + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Reply-to banner + pending attachments (floating card) --------
          if (widget.replyTo != null || _files.isNotEmpty)
            _FrostSurface(
              accent: accent,
              tinted: _note,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.replyTo != null)
                    ReplyQuotePreview(
                      entry: widget.replyTo!,
                      accent: accent,
                      onCancel: () => widget.onClearReply?.call(),
                    ),
                  if (widget.replyTo != null && _files.isNotEmpty)
                    const SizedBox(height: 8),
                  if (_files.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in _files)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 16,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: AppText.subText(
                                context,
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () => setState(() => _files.remove(f)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          // --- Floating input bar: field (icons inside) + send --------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ChatInputField(
                  controller: _controller,
                  focus: _focus,
                  // Hide the hint the moment any character exists (space/newline
                  // included), not only when there's non-whitespace text.
                  showHint: _controller.document.length <= 1,
                  accent: accent,
                  note: _note,
                  hint: _note ? widget.hintNote : widget.hintReply,
                  // +/emoji sit side-by-side when compact, but stack into a
                  // column once the field grows tall so they ride the bottom.
                  // A Flex with a switched direction (instead of Row↔Column)
                  // keeps the same element/children, so toggling it doesn't
                  // remount the subtree and steal focus (which closed the
                  // keyboard when crossing the line threshold).
                  leading: Flex(
                    direction: stacked ? Axis.vertical : Axis.horizontal,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      addButton,
                      const SizedBox(width: 2, height: 2),
                      emojiButton,
                    ],
                  ),
                  // Expand-to-fullscreen lives inside the field, beside the
                  // reply/note toggle — but stacks above it once the field is
                  // tall so both stay reachable without crowding.
                  trailing: Flex(
                    direction: stacked ? Axis.vertical : Axis.horizontal,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      expandButton,
                      const SizedBox(width: 2, height: 2),
                      modeToggle,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SendButton(
                enabled: canSend,
                sending: _sending,
                accent: accent,
                icon: _note ? Icons.note_add_rounded : Icons.send_rounded,
                onTap: _send,
              ),
            ],
          ),
          // --- Formatting toolbar on its own floating pill (while editing) --
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _focus.hasFocus
                ? _FrostSurface(
                    accent: accent,
                    margin: const EdgeInsets.only(top: 8),
                    child: FleatherToolbar.basic(
                      controller: _controller,
                      hideBackgroundColor: true,
                      hideForegroundColor: true,
                      hideDirection: true,
                      hideListChecks: true,
                      hideHorizontalRule: true,
                      hideAlignment: true,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Translucent, blurred fill for the composer's floating pieces so the
/// conversation shows through them as frosted glass. Mirrors the bottom nav
/// bar's recipe; a faint [accent] wash echoes note mode when [tinted].
Color composerFrostFill(
  BuildContext context,
  Color accent, {
  bool tinted = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = (isDark ? const Color(0xFF141A2B) : Colors.white).withValues(
    alpha: isDark ? 0.62 : 0.70,
  );
  return tinted ? Color.alphaBlend(accent.withValues(alpha: 0.12), base) : base;
}

/// Rounded, softly-shadowed **frosted-glass** surface used for the composer's
/// floating pieces (the reply/attachment card and the formatting toolbar): a
/// real `BackdropFilter` blur behind a translucent fill so the messages behind
/// it read through. When [tinted] it takes on a faint [accent] wash + hairline
/// to echo note mode.
class _FrostSurface extends StatelessWidget {
  const _FrostSurface({
    required this.accent,
    required this.child,
    this.tinted = false,
    this.padding,
    this.margin,
  });

  final Color accent;
  final Widget child;
  final bool tinted;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      // The shadow rides outside the clip so it isn't blurred away.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Glass.frost(
          sigma: 20,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: composerFrostFill(context, accent, tinted: tinted),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: tinted
                    ? accent.withValues(alpha: 0.4)
                    : Glass.border(context, 0.28),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Editor theme shared by the composer.
///
/// Two fixes over Fleather's fallback:
///  * **Links** default to `colorScheme.primaryContainer`, which in this app is
///    near-black in dark mode and near-white in light — unreadable either way.
///    We recolour them to the accent ([ColorScheme.primary]) so URLs stand out
///    in both themes.
///  * In [compact] mode the fallback renders paragraphs at 16px with 6px above /
///    10px below — inside a chat pill each Enter feels like a double line-break
///    and inflates the pill. We trim paragraphs (and list items) to the app's
///    14px body with **zero** inter-paragraph gap so the field reads like a
///    plain text box, not a document. Fullscreen keeps the normal spacing.
FleatherThemeData _editorTheme(BuildContext context, {bool compact = false}) {
  final base = FleatherThemeData.fallback(context);
  final link = base.link.copyWith(
    color: Theme.of(context).colorScheme.primary,
  );
  if (!compact) return base.copyWith(link: link);
  final style = base.paragraph.style.copyWith(fontSize: 14, height: 1.3);
  const none = VerticalSpacing(top: 0, bottom: 0);
  return base.copyWith(
    link: link,
    paragraph: TextBlockTheme(style: style, spacing: none),
    lists: TextBlockTheme(style: style, spacing: none, lineSpacing: none),
  );
}

/// The rounded "pill" input: a filled, softly-bordered field that hosts the
/// Fleather editor, grows from one line up to five (then scrolls), and tucks a
/// [leading] (attachment) and [trailing] (mode toggle) control inside so the
/// field, its icons and the hint all sit on one line.
class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.controller,
    required this.focus,
    required this.showHint,
    required this.hint,
    required this.accent,
    this.note = false,
    this.leading,
    this.trailing,
  });

  final FleatherController controller;
  final FocusNode focus;

  /// Whether the placeholder is visible. Driven by the *raw* document length —
  /// not a trimmed check — so typing a space or pressing Enter (which leaves
  /// only whitespace) still hides the hint, matching a normal text field.
  final bool showHint;
  final String hint;
  final Color accent;

  /// Note mode gives the pill a faint amber wash + hairline.
  final bool note;
  final Widget? leading;
  final Widget? trailing;

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  // ~5 lines of Inter-14 body text before the editor starts scrolling.
  static const double _minEditor = 20;
  static const double _maxEditor = 104;
  static const double _vPad = 8;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focus = widget.focus;
    final accent = widget.accent;
    final note = widget.note;
    final hint = widget.hint;
    final showHint = widget.showHint;
    final leading = widget.leading;
    final trailing = widget.trailing;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final focused = focus.hasFocus;

    // Translucent frosted fill so the conversation shows through the pill; a
    // faint amber wash tints it in note mode.
    final fill = composerFrostFill(context, accent, tinted: note);
    // No hard outline: a hairline at rest, a soft accent ring while focused,
    // an amber hairline in note mode.
    final borderColor = focused
        ? accent.withValues(alpha: 0.55)
        : note
        ? accent.withValues(alpha: 0.4)
        : Glass.border(context, isDark ? 0.34 : 0.18);

    // The shadow rides outside the clip so the blur doesn't eat it, then a
    // BackdropFilter frosts the messages behind the translucent pill.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Glass.frost(
          sigma: 20,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.only(left: leading != null ? 3 : 12, right: 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: focused ? 1.3 : 1),
            ),
            // A single line stays centered (the container centers the short
            // row); once it grows past [_maxEditor] the editor scrolls
            // internally and the icons ride the bottom line. The ConstrainedBox
            // is what HARD-caps the height â€” FleatherEditor's own maxHeight
            // isn't enforced under a Row's unbounded vertical constraints, which
            // otherwise lets it fill the screen (and throws "hit test a render
            // box with no size").
            // Icons ride the BOTTOM line so, as the field grows, the "+"/emoji
            // and the mode toggle stay level with the last row of text (chat
            // style) instead of floating in the vertical centre.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (leading != null) leading,
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: leading != null ? 2 : 0,
                      right: 6,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _minEditor,
                        maxHeight: _maxEditor,
                      ),
                      child: Stack(
                        alignment: Alignment.topLeft,
                        children: [
                          // Cursor + selection follow the active accent; the
                          // compact theme kills Fleather's fat paragraph gaps.
                          Theme(
                            data: Theme.of(context).copyWith(
                              textSelectionTheme: TextSelectionThemeData(
                                cursorColor: accent,
                                selectionColor: accent.withValues(alpha: 0.28),
                                selectionHandleColor: accent,
                              ),
                            ),
                            child: FleatherTheme(
                              data: _editorTheme(context, compact: true),
                              // Fleather scrolls internally (so the caret stays
                              // visible while typing and focus/keyboard behave
                              // natively). A thin accent scrollbar rides the
                              // right edge once the text outgrows the pill, so
                              // the user can see there's more to scroll.
                              child: _EditorScrollbar(
                                accent: accent,
                                thickness: 3,
                                trackMargin: const EdgeInsets.symmetric(
                                  vertical: 5,
                                  horizontal: 2,
                                ),
                                builder: (scroll) => FleatherEditor(
                                  controller: controller,
                                  focusNode: focus,
                                  scrollController: scroll,
                                  minHeight: _minEditor,
                                  maxHeight: _maxEditor,
                                  // Extra right pad leaves room for the thumb so
                                  // it never sits on top of the text.
                                  padding: const EdgeInsets.only(
                                    top: _vPad,
                                    bottom: _vPad,
                                    right: 8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Hint pinned to the first line (top-left) so it never
                          // drifts to the middle when blank lines are added.
                          if (showHint)
                            Positioned(
                              top: _vPad,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: AppText.subText(
                                  context,
                                  hint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A **custom** scrollbar for a scrolling [FleatherEditor] (built by [builder]
/// with the shared [ScrollController]). Rather than Flutter's [RawScrollbar] —
/// which measured a short track and stopped updating once the editor lost focus
/// — this paints its own thumb as a [Positioned] overlay driven straight off the
/// scroll metrics. That means it:
///   * spans the **full** track height ([trackMargin] only trims the rounded
///     corners), with the thumb length showing how much of the text is visible;
///   * keeps tracking when the keyboard is dismissed (via back / tap-away),
///     because it also listens for [ScrollMetricsNotification] — the viewport
///     resize that a plain scroll listener never hears;
///   * is draggable to scroll, and simply vanishes when there's no overflow.
class _EditorScrollbar extends StatefulWidget {
  const _EditorScrollbar({
    required this.accent,
    required this.builder,
    this.thickness = 4,
    this.trackMargin = const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
  });

  final Color accent;
  final double thickness;
  final EdgeInsets trackMargin;
  final Widget Function(ScrollController scroll) builder;

  @override
  State<_EditorScrollbar> createState() => _EditorScrollbarState();
}

class _EditorScrollbarState extends State<_EditorScrollbar> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Follow the thumb live as the content scrolls.
    _scroll.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.removeListener(_tick);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A metrics change with no scroll (keyboard opening/closing resized the
    // viewport, or the document grew while pinned at the top) doesn't reach a
    // plain scroll listener — repaint the thumb against the new extent.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            widget.builder(_scroll),
            _thumb(constraints.maxHeight),
          ],
        ),
      ),
    );
  }

  Widget _thumb(double height) {
    if (!_scroll.hasClients ||
        !_scroll.position.hasContentDimensions ||
        !height.isFinite) {
      return const SizedBox.shrink();
    }
    final pos = _scroll.position;
    final maxExtent = pos.maxScrollExtent;
    final track = height - widget.trackMargin.vertical;
    // Nothing to scroll (or no room for a track) — hide the bar entirely.
    if (maxExtent <= 0 || track <= 0) return const SizedBox.shrink();

    final viewport = pos.viewportDimension;
    final thumb = (viewport / (viewport + maxExtent) * track).clamp(24.0, track);
    final t = (pos.pixels / maxExtent).clamp(0.0, 1.0);
    final top = widget.trackMargin.top + t * (track - thumb);

    return Positioned(
      top: top,
      right: 0,
      height: thumb,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) {
          final travel = track - thumb;
          if (travel <= 0) return;
          final next = pos.pixels + d.primaryDelta! / travel * maxExtent;
          _scroll.jumpTo(next.clamp(0.0, maxExtent));
        },
        // A wider transparent strip makes the thin thumb easy to grab; the
        // visible bar hugs the right edge inside [trackMargin].
        child: Padding(
          padding: EdgeInsets.only(right: widget.trackMargin.right),
          child: SizedBox(
            width: widget.thickness + 10,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: widget.thickness,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(widget.thickness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon button that lives inside the input field (the "+" and emoji
/// affordances). A 32Ã—36 target keeps it tappable while sitting on a single
/// line of text.
class ComposerIconButton extends StatelessWidget {
  const ComposerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        splashRadius: 20,
        icon: Icon(icon, size: size, color: scheme.onSurfaceVariant),
        onPressed: onTap,
      ),
    );
  }
}

/// Premium circular send button: grey + disabled when empty, animating to the
/// accent colour with a slight pop when there's something to send. Shows a
/// spinner while a send is in flight.
class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.enabled,
    required this.sending,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  // Matches the input pill's min height so the two sit level as one bar.
  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (sending) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
          ),
        ),
      );
    }

    final disabledColor = scheme.onSurfaceVariant.withValues(alpha: 0.28);
    return AnimatedScale(
      scale: enabled ? 1 : 0.88,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: enabled ? accent : disabledColor,
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

/// Single icon-only Reply/Note toggle that lives inside the input field as a
/// suffix. It shows the **current** mode — a blue reply glyph, or an amber note
/// glyph — on a matching tinted disc; tapping flips the mode and the icon
/// cross-fades to the other state.
class InlineModeToggle extends StatelessWidget {
  const InlineModeToggle({
    super.key,
    required this.note,
    required this.onChanged,
  });

  final bool note;
  final ValueChanged<bool> onChanged;

  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = note ? AppTheme.warning : scheme.primary;

    return Tooltip(
      message: note ? 'Internal note — tap to reply' : 'Reply — tap for note',
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!note),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  note ? Icons.reply_rounded : Icons.sticky_note_2_rounded,
                  key: ValueKey(note),
                  size: 18,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen rich-text editor that shares the composer's [FleatherController].
///
/// Mirrors the compact composer's insert affordances: [onInsertCanned] /
/// [onInsertFaq] pick a saved reply / FAQ and splice it into the shared
/// document at the cursor (they don't touch focus — this editor refocuses its
/// own field afterwards so the keyboard returns here, not to the collapsed pill
/// behind the route).
class _FullscreenEditor extends StatefulWidget {
  const _FullscreenEditor({
    required this.controller,
    required this.note,
    required this.onSend,
    required this.onInsertCanned,
    required this.onInsertFaq,
  });

  final FleatherController controller;
  final bool note;
  final Future<bool> Function() onSend;
  final Future<void> Function() onInsertCanned;
  final Future<void> Function() onInsertFaq;

  @override
  State<_FullscreenEditor> createState() => _FullscreenEditorState();
}

class _FullscreenEditorState extends State<_FullscreenEditor> {
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await widget.onSend();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  Future<void> _insertCanned() async {
    await widget.onInsertCanned();
    if (mounted) _focus.requestFocus();
  }

  Future<void> _insertFaq() async {
    await widget.onInsertFaq();
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.note ? AppTheme.warning : scheme.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Collapse',
          icon: const Icon(Icons.close_fullscreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.note ? 'Internal note' : 'Reply'),
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: _send,
                    icon: Icon(
                      widget.note ? Icons.note_add : Icons.send,
                      size: 18,
                    ),
                    label: const Text('Send'),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          // The fullscreen editor keeps Fleather's own built-in scrollbar (its
          // Scrollable sets scrollbars: true) — no custom overlay needed at this
          // size, and wrapping expands:true in an extra Stack/LayoutBuilder was
          // a needless layout risk.
          Expanded(
            child: FleatherTheme(
              data: _editorTheme(context),
              child: FleatherEditor(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                expands: true,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
          // The formatting toolbar rides its own raised surface with a hairline
          // divider so its icons read clearly against the (dark) editor
          // background instead of dissolving into it. An explicit icon colour
          // guarantees contrast in both themes.
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Theme(
                data: Theme.of(context).copyWith(
                  iconTheme: IconThemeData(color: scheme.onSurface),
                ),
                // Insert affordances (saved reply / FAQ) sit on their own row
                // above the formatting toolbar, which stays a full-width child
                // (its own horizontal scroll). Keeping them here — not in the
                // AppBar, and not wrapped in a flex around the toolbar's scroll
                // view — avoids the layout overflow that broke gestures.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Saved replies',
                          icon: const Icon(Icons.quickreply_outlined),
                          onPressed: _insertCanned,
                        ),
                        IconButton(
                          tooltip: 'Insert FAQ',
                          icon: const Icon(Icons.menu_book_outlined),
                          onPressed: _insertFaq,
                        ),
                      ],
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    FleatherToolbar.basic(controller: widget.controller),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Actions surfaced by the composer's "+" button.
enum _PlusAction { camera, photo, file, canned, faq }

/// Bottom sheet opened by the "+" button: attachment sources plus the
/// canned-reply / FAQ inserters and the expand-editor action, all in one place.
class _PlusMenuSheet extends StatelessWidget {
  const _PlusMenuSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSheet(
      title: 'Add to message',
      scrollable: false,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            context,
            icon: Icons.photo_camera_outlined,
            label: 'Camera',
            action: _PlusAction.camera,
          ),
          _row(
            context,
            icon: Icons.image_outlined,
            label: 'Photo',
            action: _PlusAction.photo,
          ),
          _row(
            context,
            icon: Icons.attach_file_rounded,
            label: 'File',
            action: _PlusAction.file,
          ),
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: scheme.outlineVariant,
          ),
          _row(
            context,
            icon: Icons.quickreply_outlined,
            label: 'Saved replies',
            action: _PlusAction.canned,
          ),
          _row(
            context,
            icon: Icons.menu_book_outlined,
            label: 'Insert FAQ',
            action: _PlusAction.faq,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required _PlusAction action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.pop(context, action),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            AppText.subText(context, label, fw: 1),
          ],
        ),
      ),
    );
  }
}

/// Lightweight emoji picker: a grid of common emojis that insert into the
/// editor at the cursor. Stays open so several can be tapped in a row.
class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({required this.onSelect});
  final ValueChanged<String> onSelect;

  static const List<String> _emojis = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '😂',
    '🙂',
    '😉',
    '😊',
    '😍',
    '😘',
    '😗',
    '🤔',
    '🤨',
    '😐',
    '😴',
    '😎',
    '🤩',
    '🥳',
    '😏',
    '😒',
    '😞',
    '😔',
    '😢',
    '😭',
    '😤',
    '😠',
    '👍',
    '👎',
    '👏',
    '🙌',
    '🙏',
    '💪',
    '👋',
    '🤝',
    '✌️',
    '🤞',
    '👌',
    '🔥',
    '⭐',
    '✨',
    '🎉',
    '✅',
    '❌',
    '❗',
    '❓',
    '💯',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '📎',
    '📌',
    '📝',
    '📄',
    '📈',
    '⏰',
    '🚀',
    '💡',
    '☑️',
    '🙃',
  ];

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Emoji',
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: SizedBox(
        height: 260,
        child: GridView.builder(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: _emojis.length,
          itemBuilder: (context, i) {
            final e = _emojis[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(e),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            );
          },
        ),
      ),
    );
  }
}
