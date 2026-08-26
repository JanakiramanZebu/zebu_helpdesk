import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../data/faq_repository.dart';
import '../../models/common.dart';
import '../../models/faq.dart';
import '../../models/meta.dart';
import '../../providers.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/multi_select_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';

/// The web's **Add New FAQ** / **Update FAQ** form (`scp/faq.php`, rendered by
/// `include/staff/faq.inc.php`), as a bottom sheet.
///
/// Field set and order are the web's: Category Listing, Help Topics, Listing
/// Type, then the article itself — Question, Answer — with Attachments and
/// Internal Notes. Answer and notes travel as HTML through `parchmentHtml`,
/// the same codec the reply composer and the canned editor use, so an article
/// written here reads as formatted text in the web's rich-text editor.
///
/// Editing sends the whole form rather than a diff: unlike the category
/// payload, `GET /faq/{id}` serves every field back, so nothing is being
/// blanked unseen. Attachments are the exception — they are never part of the
/// edit call (the server would treat the list as "keep only these"), and go
/// through their own endpoints after the save.
///
/// Resolves to the saved [Faq], or null if the sheet was dismissed.
Future<Faq?> showFaqEditorSheet(
  BuildContext context, {
  required List<FaqCategory> categories,
  FaqCategory? category,
  Faq? existing,
}) => showAppSheet<Faq>(
  context: context,
  builder: (_) => _FaqEditorSheet(
    categories: categories,
    category: category,
    existing: existing,
  ),
);

/// What each listing type means, in the web select's order. **Featured is
/// offered only for an article that already is Featured** — the API's
/// `published` is a boolean, so `ispublished = 2` can be preserved but never
/// set. Leaving the dropdown on Featured omits `published` from the payload
/// entirely, and a partial edit leaves the column alone.
const _kListingHints = <FaqListing, String>{
  FaqListing.featured: 'Promoted to the help centre front page',
  FaqListing.public: 'Published to the knowledgebase',
  FaqListing.internal: 'Agents only',
};

class _FaqEditorSheet extends ConsumerStatefulWidget {
  const _FaqEditorSheet({
    required this.categories,
    this.category,
    this.existing,
  });

  /// Every category the Knowledgebase screen has loaded — the Category
  /// Listing dropdown's options, passed down rather than re-fetched.
  final List<FaqCategory> categories;

  /// The category a *new* article starts in, when the sheet was opened from
  /// one (the web's `faq.php?cid=N&a=add`).
  final FaqCategory? category;

  /// The article being edited, or null to create one. Must be the **full**
  /// article (`GET /faq/{id}`), not a list row: the form sends every field.
  final Faq? existing;

  @override
  ConsumerState<_FaqEditorSheet> createState() => _FaqEditorSheetState();
}

class _FaqEditorSheetState extends ConsumerState<_FaqEditorSheet> {
  late final _question = TextEditingController(
    text: widget.existing?.question ?? '',
  );
  late final FleatherController _answer = _documentController(
    widget.existing?.answer,
  );
  late final FleatherController _notes = _documentController(
    widget.existing?.notes,
  );

  /// 0 = the web's "Select FAQ Category" placeholder, which its own validation
  /// rejects ("Category is required").
  late int _categoryId =
      widget.existing?.category?.id ?? widget.category?.id ?? 0;
  /// Read from the article's `type` string, not its `published` boolean —
  /// see [Faq.listing] for why that distinction is load-bearing.
  late final FaqListing _originalListing =
      widget.existing?.listing ?? FaqListing.internal;
  late FaqListing _listing = _originalListing;

  /// Featured cannot be *chosen*; it can only be left alone.
  List<FaqListing> get _listingOptions => [
    if (_originalListing == FaqListing.featured) FaqListing.featured,
    FaqListing.public,
    FaqListing.internal,
  ];

  /// `GET /meta/topics`, the same list the web builds from
  /// `$thisstaff->getTopicNames()`. Optional, so a failure just leaves the
  /// picker with nothing to offer.
  List<MetaItem> _topics = const [];
  late Set<int> _topicIds = {...?widget.existing?.topicIds};

  /// Attachments already on the article, minus any marked for removal here.
  late List<Attachment> _attachments = [...?widget.existing?.attachments];

  /// Ids of stored attachments to delete on save.
  final Set<int> _removedAttachmentIds = {};

  /// Files picked in this session; uploaded after the article is saved.
  final List<PlatformFile> _newFiles = [];

  /// Set once a *create* has succeeded, so a retry after a failed upload edits
  /// that article instead of creating a duplicate.
  int? _createdId;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _isEdit => widget.existing != null;
  int? get _targetId => widget.existing?.id ?? _createdId;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    try {
      final items = await ref.read(metaRepositoryProvider).topics();
      if (mounted) setState(() => _topics = items);
    } on ApiException {
      // Help topics are optional on the web form too.
    }
  }

  /// A Fleather document seeded from stored HTML. An article osTicket wrote is
  /// valid HTML; anything the codec chokes on falls back to its plain-text
  /// form so the content stays editable instead of being lost.
  static FleatherController _documentController(String? html) {
    final src = (html ?? '').trim();
    if (src.isEmpty) return FleatherController();
    try {
      return FleatherController(document: parchmentHtml.decode(src));
    } catch (_) {
      final controller = FleatherController();
      final plain = Fmt.stripHtml(src);
      if (plain.isNotEmpty) {
        controller.replaceText(
          0,
          0,
          plain,
          selection: TextSelection.collapsed(offset: plain.length),
        );
      }
      return controller;
    }
  }

  /// Empty document to `''` rather than the codec's empty-paragraph markup,
  /// so a blank notes field clears instead of storing `<p><br></p>`.
  static String _html(FleatherController c) =>
      c.document.toPlainText().trim().isEmpty
      ? ''
      : parchmentHtml.encode(c.document);

  static bool _isBlank(FleatherController c) =>
      c.document.toPlainText().trim().isEmpty;

  /// "Funds / Pay in (Public)" — the web renders each option as the category's
  /// full path plus its visibility, because a public article under a private
  /// category is still invisible to end users.
  String _categoryLabel(FaqCategory c) =>
      '${c.displayName} (${c.public ? 'Public' : 'Private'})';

  String get _topicsLabel {
    if (_topicIds.isEmpty) return 'None';
    final names = [
      for (final t in _topics)
        if (_topicIds.contains(t.id)) t.name,
    ];
    return names.isEmpty ? '${_topicIds.length} selected' : names.join(', ');
  }

  Future<void> _pickTopics() async {
    if (_topics.isEmpty) return;
    final picked = await pickMultiMeta(
      context,
      title: 'Help topics',
      items: _topics,
      selected: _topicIds,
    );
    if (picked == null || !mounted) return;
    setState(() => _topicIds = picked);
  }

  Future<void> _addFiles() async {
    // Same Camera / Photos / Files sheet the reply composer uses.
    final source = await pickAttachSource(context);
    if (source == null || !mounted) return;
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_newFiles.any((e) => e.name == f.name)) continue;
        _newFiles.add(f);
      }
    });
  }

  Future<void> _save() async {
    final question = _question.text.trim();
    // `FAQ::update()`'s own required set, worded the way it words it. A
    // duplicate question is the one rule only the server can answer.
    final errors = <String, String>{
      if (question.isEmpty) 'question': 'Question required',
      if (_categoryId == 0) 'category_id': 'Category is required',
      if (_isBlank(_answer)) 'answer': 'FAQ answer is required',
    };
    if (errors.isNotEmpty) {
      setState(() {
        _error = null;
        _fieldErrors = errors;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final repo = ref.read(faqRepositoryProvider);
    final topicIds = _topicIds.toList()..sort();
    Faq saved;
    try {
      final id = _targetId;
      if (id != null) {
        // Every key here is one the sheet owns and the payload serves back, so
        // sending the whole form blanks nothing unseen. Attachments are
        // deliberately absent — they are synced below.
        saved = await repo.updateArticle(id, {
          'category_id': _categoryId,
          'question': question,
          'answer': _html(_answer),
          // Only when the agent actually moved it. Omitted, the partial edit
          // leaves `ispublished` exactly as it is — which is the only way a
          // Featured article survives an edit, and the only way a Public
          // article under a Private category isn't silently demoted by a
          // boolean that was never about its own column.
          if (_listing != _originalListing)
            'published': _listing == FaqListing.public,
          'topic_ids': topicIds,
          'notes': _html(_notes),
        });
      } else {
        saved = await repo.createArticle(
          categoryId: _categoryId,
          question: question,
          answer: _html(_answer),
          published: _listing == FaqListing.public,
          topicIds: topicIds,
          notes: _html(_notes),
        );
        _createdId = saved.id;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
      return;
    }

    final failures = await _syncAttachments(repo, saved.id);
    if (!mounted) return;
    if (failures.isNotEmpty) {
      // The article itself saved. Keep the sheet open so only the files are
      // retried — _createdId makes that retry an edit, not a duplicate.
      setState(() => _saving = false);
      AppSnack.error(
        context,
        'Article saved, but ${failures.length} file(s) failed. '
        'Tap save again to retry.',
      );
      return;
    }
    Navigator.pop(context, saved);
  }

  /// Applies the pending attachment deletes and uploads against [id].
  /// Anything that succeeds is dropped from the pending sets, so a retry only
  /// replays what actually failed. Returns the failed file names.
  Future<List<String>> _syncAttachments(FaqRepository repo, int id) async {
    final failures = <String>[];

    for (final attId in _removedAttachmentIds.toList()) {
      try {
        await repo.deleteAttachment(id, attId);
        _removedAttachmentIds.remove(attId);
      } on ApiException {
        failures.add('#$attId');
      }
    }

    for (final f in _newFiles.toList()) {
      final bytes = f.bytes;
      if (bytes == null) {
        _newFiles.remove(f);
        continue;
      }
      try {
        await repo.uploadAttachment(
          id,
          MultipartFile.fromBytes(bytes, filename: f.name),
        );
        _newFiles.remove(f);
      } on ApiException {
        failures.add(f.name);
      }
    }
    return failures;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSheet(
      title: _isEdit ? 'Update FAQ' : 'Add new FAQ',
      subtitle: _isEdit
          ? widget.existing!.question
          : widget.category?.displayName,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AppText.subText(context, _error!, color: scheme.error),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Category listing',
                helperText: 'FAQ category the question belongs to.',
                errorText: _fieldErrors['category_id'],
              ),
              items: [
                const DropdownMenuItem(
                  value: 0,
                  child: Text('Select FAQ category'),
                ),
                for (final c in widget.categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      _categoryLabel(c),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
            ),
            const SizedBox(height: 12),
            // The web's multi-select of the agent's own help topics. Optional
            // there and here: an article with none shows to every agent.
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Help topics',
                helperText: _topics.isEmpty
                    ? 'No help topics available'
                    : 'Topics this article answers.',
                errorText: _fieldErrors['topic_ids'],
              ),
              child: InkWell(
                onTap: _topics.isEmpty ? null : _pickTopics,
                child: Row(
                  children: [
                    Expanded(
                      child: AppText.subText(
                        context,
                        _topicsLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        color: _topicIds.isEmpty
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FaqListing>(
              initialValue: _listing,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Listing type',
                helperText: _originalListing == FaqListing.featured
                    ? 'Leave on Featured to keep it on the front page — the '
                          'API cannot set Featured back.'
                    : null,
                errorText: _fieldErrors['published'],
              ),
              items: [
                for (final l in _listingOptions)
                  DropdownMenuItem(
                    value: l,
                    child: Text(
                      '${l.label} — ${_kListingHints[l]}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _listing = v ?? _listing),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _question,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Question',
                errorText: _fieldErrors['question'],
              ),
            ),
            const SizedBox(height: 12),
            RichMessageField(
              controller: _answer,
              label: 'Answer',
              hintText: 'Write the answer agents and users will read…',
              errorText: _fieldErrors['answer'],
              minHeight: 140,
              maxHeight: 260,
            ),
            const SizedBox(height: 12),
            _AttachmentsSection(
              stored: _attachments,
              pending: _newFiles,
              onAdd: _saving ? null : _addFiles,
              onRemoveStored: (a) => setState(() {
                _removedAttachmentIds.add(a.id);
                _attachments = [
                  for (final x in _attachments)
                    if (x.id != a.id) x,
                ];
              }),
              onRemovePending: (f) => setState(() => _newFiles.remove(f)),
            ),
            const SizedBox(height: 12),
            RichMessageField(
              controller: _notes,
              label: 'Internal notes',
              hintText: "Be liberal, they're internal.",
              errorText: _fieldErrors['notes'],
              minHeight: 90,
              maxHeight: 180,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEdit ? 'Save changes' : 'Add FAQ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The web form's Attachments tab: what the article already carries, what is
/// queued for upload, and one Attach action. Same chip treatment as the canned
/// response editor, which solves the identical problem.
class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.stored,
    required this.pending,
    required this.onAdd,
    required this.onRemoveStored,
    required this.onRemovePending,
  });

  final List<Attachment> stored;
  final List<PlatformFile> pending;
  final VoidCallback? onAdd;
  final ValueChanged<Attachment> onRemoveStored;
  final ValueChanged<PlatformFile> onRemovePending;

  @override
  Widget build(BuildContext context) {
    final empty = stored.isEmpty && pending.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppText.subText(
              context,
              'Attachments (${stored.length + pending.length})',
              fw: 1,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.attach_file, size: 16),
              label: const Text('Add'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (empty)
          AppText.paraText(context, 'No files attached')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in stored)
                _FileChip(
                  label: a.size != null
                      ? '${a.name}  ·  ${Fmt.fileSize(a.size)}'
                      : a.name,
                  onDelete: () => onRemoveStored(a),
                ),
              for (final f in pending)
                _FileChip(
                  label: '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                  pending: true,
                  onDelete: () => onRemovePending(f),
                ),
            ],
          ),
      ],
    );
  }
}

/// One attachment chip. [pending] tints it with the primary colour so files
/// not yet uploaded read differently from ones already stored.
class _FileChip extends StatelessWidget {
  const _FileChip({
    required this.label,
    required this.onDelete,
    this.pending = false,
  });

  final String label;
  final VoidCallback onDelete;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = pending ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      decoration: BoxDecoration(
        color: pending
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pending
                ? Icons.upload_file_outlined
                : Icons.insert_drive_file_outlined,
            size: 14,
            color: tone,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: AppText.paraText(
              context,
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 14),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
