import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/canned_vars.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../data/canned_repository.dart';
import '../../models/canned.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';
import '../../widgets/thread_html.dart';

/// Sentinel department id for "— All Departments —" (osTicket stores 0 on the
/// canned row for the global pool).
const int _kAllDepartments = 0;

/// `Canned::update()` rejects anything shorter than this.
const int _kMinTitleLength = 3;

class CannedScreen extends ConsumerStatefulWidget {
  const CannedScreen({super.key});

  @override
  ConsumerState<CannedScreen> createState() => _CannedScreenState();
}

/// The staff list's Status column, as a view over one fetch. osTicket's
/// `scp/canned.php` lists every response the agent can manage and offers bulk
/// Enable / Disable; the API serves the same set behind `include_disabled=1`.
enum _StatusView {
  active('Active'),
  disabled('Disabled'),
  all('All');

  const _StatusView(this.label);
  final String label;

  bool accepts(CannedResponse c) => switch (this) {
    _StatusView.active => c.isEnabled,
    _StatusView.disabled => !c.isEnabled,
    _StatusView.all => true,
  };
}

class _CannedScreenState extends ConsumerState<CannedScreen> {
  int _reload = 0;
  _StatusView _status = _StatusView.active;

  void _toast(String msg) => AppSnack.info(context, msg);

  void _refresh() => setState(() => _reload++);

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(cannedRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Canned Responses')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<CannedResponse>(
        refreshKey: _reload,
        emptyMessage: _status == _StatusView.disabled
            ? 'No disabled responses'
            : 'No canned responses',
        emptyIcon: Icons.quickreply_outlined,
        header: _statusFilter(),
        // Disabled rows are fetched alongside the active ones and filtered
        // here, so switching the view costs nothing and a disabled response
        // can be reopened and re-enabled (it used to 404 on every endpoint).
        fetch: (page) => repo.list(page: page, includeDisabled: true),
        itemFilter: _status.accepts,
        itemBuilder: (context, c) => _CannedCard(
          canned: c,
          onTap: () => _openDetail(c),
          onEdit: () => _openEdit(c),
          onDelete: () => _confirmDelete(c),
          onToggleEnabled: () => _setEnabled(c, !c.isEnabled),
        ),
      ),
    );
  }

  Widget _statusFilter() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        for (final v in _StatusView.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(v.label),
              selected: _status == v,
              onSelected: (_) => setState(() => _status = v),
            ),
          ),
      ],
    ),
  );

  /// Enable / disable in place — the web's bulk action, one row at a time.
  Future<void> _setEnabled(CannedResponse c, bool enabled) async {
    try {
      await ref
          .read(cannedRepositoryProvider)
          .update(c.id, {'is_enabled': enabled});
      _toast(enabled ? 'Enabled' : 'Disabled');
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openDetail(CannedResponse c) async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _CannedDetailSheet(canned: c, onToast: _toast),
    );
  }

  Future<void> _openCreate() async {
    final saved = await showAppSheet<bool>(
      context: context,
      builder: (_) => const _CannedEditor(),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openEdit(CannedResponse c) async {
    final saved = await showAppSheet<bool>(
      context: context,
      builder: (_) => _CannedEditor(existing: c),
    );
    if (saved == true) _refresh();
  }

  Future<void> _confirmDelete(CannedResponse c) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete response?',
      message: 'Delete "${c.title}"? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(cannedRepositoryProvider).delete(c.id);
      _toast('Deleted');
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _CannedCard extends StatelessWidget {
  const _CannedCard({
    required this.canned,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  final CannedResponse canned;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.subText(context, canned.title, fw: 2),
                    const SizedBox(height: 4),
                    AppText.paraText(
                      context,
                      Fmt.stripHtml(canned.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    // The staff list's Status / Department / Last Updated
                    // columns, plus its attachment icon.
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!canned.isEnabled)
                          _chip(context, 'Disabled', theme.colorScheme.error),
                        _chip(
                          context,
                          canned.scopeLabel,
                          theme.colorScheme.primary,
                        ),
                        if (canned.fileCount > 0)
                          Icon(
                            Icons.attach_file,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        if (canned.updatedLabel != null)
                          AppText.paraText(
                            context,
                            'Updated ${canned.updatedLabel}',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'toggle') onToggleEnabled();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(canned.isEnabled ? 'Disable' : 'Enable'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AppText.paraText(context, label, color: color, fw: 0),
  );
}


/// Read-only detail sheet.
///
/// The list payload carries the staff list's columns; this re-reads the
/// response with `GET /canned/{id}` for the rest — internal notes, the
/// attachments themselves, and the email filters using it.
class _CannedDetailSheet extends ConsumerStatefulWidget {
  const _CannedDetailSheet({required this.canned, required this.onToast});

  /// The list row that was tapped — used for the title while the full record
  /// loads, and as the fallback if the fetch fails.
  final CannedResponse canned;
  final ValueChanged<String> onToast;

  @override
  ConsumerState<_CannedDetailSheet> createState() => _CannedDetailSheetState();
}

class _CannedDetailSheetState extends ConsumerState<_CannedDetailSheet> {
  CannedResponse? _full;
  List<Attachment> _attachments = const [];
  String? _deptName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(cannedRepositoryProvider);
    try {
      final full = await repo.get(widget.canned.id);
      final atts = await repo.attachments(widget.canned.id);
      if (!mounted) return;
      setState(() {
        _full = full;
        _attachments = atts;
        _loading = false;
      });
      _resolveDept(full.deptId);
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Looks the department name up out of the session-cached meta list. Silent
  /// on failure — the row then just reads "Department #id".
  Future<void> _resolveDept(int deptId) async {
    if (deptId == _kAllDepartments) return;
    try {
      final depts = await ref.read(metaRepositoryProvider).departments();
      if (!mounted) return;
      final match = depts.where((MetaItem d) => d.id == deptId);
      if (match.isNotEmpty) setState(() => _deptName = match.first.name);
    } on ApiException {
      // Non-fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _full ?? widget.canned;
    final notes = (c.notes ?? '').trim();

    return AppSheet(
      title: c.title,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              if (_full != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(
                      label: c.isEnabled ? 'Active' : 'Disabled',
                      color: c.isEnabled ? scheme.primary : scheme.error,
                    ),
                    _MetaChip(
                      label: c.isGlobal
                          ? 'All Departments'
                          : (_deptName ??
                                c.deptName ??
                                'Department #${c.deptId}'),
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              // `Canned::delete()` refuses while an email filter references
              // the response (the API answers 409), so say so up front rather
              // than only after a failed delete.
              if (c.filters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AppText.paraText(
                    context,
                    'In use by email '
                    '${c.filters.length == 1 ? 'filter' : 'filters'}: '
                    '${c.filters.join(', ')}. It cannot be deleted while '
                    'they reference it.',
                    color: scheme.error,
                  ),
                ),
              ],
              if (_full != null) const SizedBox(height: 14),
              ThreadHtml(
                html: c.body,
                textStyle: theme.textTheme.bodyMedium,
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                AppText.subText(context, 'Internal notes', fw: 1),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // Notes are HTML too (the editor writes them with the same
                  // codec as the body), so render rather than dump markup.
                  child: ThreadHtml(
                    html: notes,
                    textStyle: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                AppText.subText(context, 'Attachments', fw: 1),
                for (final a in _attachments) AttachmentTile(attachment: a),
              ],
              if (_loading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: Fmt.stripHtml(c.body)),
                  );
                  if (context.mounted) Navigator.pop(context);
                  widget.onToast('Copied');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small tinted chip for the detail sheet's status / department line.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AppText.paraText(context, label, color: color, fw: 1),
  );
}

/// Create / edit bottom sheet.
///
/// Field set and grouping follow the osTicket staff form
/// (`include/staff/cannedresponse.inc.php`):
///
///  1. *Canned response settings* — Status (Active / Disabled) + Department;
///  2. *Canned Response* — Title, the rich-text body with its Supported
///     Variables affordance, and the optional canned attachments;
///  3. *Internal Notes* — notes about the response, agents only.
///
/// Body and notes travel as HTML, so both are edited with [RichMessageField]
/// and round-tripped through `parchmentHtml` — the same codec the ticket
/// composer uses. A response authored in osTicket therefore opens as
/// formatted text instead of raw markup.
class _CannedEditor extends ConsumerStatefulWidget {
  const _CannedEditor({this.existing});
  final CannedResponse? existing;

  @override
  ConsumerState<_CannedEditor> createState() => _CannedEditorState();
}

class _CannedEditorState extends ConsumerState<_CannedEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );

  // Rebuilt by Reset, so these are plain fields rather than `late final`.
  late FleatherController _response;
  late FleatherController _notes;

  late bool _enabled = widget.existing?.isEnabled ?? true;
  late int _deptId = widget.existing?.deptId ?? _kAllDepartments;

  /// `GET /meta/departments`, loaded once so the Department row can show a
  /// name — the canned payload only carries the id.
  List<MetaItem> _departments = const [];

  /// Attachments already stored against an existing response, minus any the
  /// user has marked for removal in this session.
  List<Attachment> _attachments = const [];

  /// Ids of stored attachments the user removed; deleted on save.
  final Set<int> _removedAttachmentIds = {};

  /// Files picked in this session; uploaded after the response is saved.
  final List<PlatformFile> _newFiles = [];

  /// Set once a *create* has succeeded so a retry after a failed attachment
  /// upload edits that response instead of creating a duplicate.
  int? _createdId;

  bool _saving = false;
  final Map<String, String> _fieldErrors = {};

  bool get _isEdit => widget.existing != null;

  /// The response id to attach files to — the edited row, or the one this
  /// sheet just created.
  int? get _targetId => widget.existing?.id ?? _createdId;

  @override
  void initState() {
    super.initState();
    _response = _documentController(widget.existing?.body);
    _notes = _documentController(widget.existing?.notes);
    _loadDepartments();
    if (_isEdit) _loadAttachments();
  }

  @override
  void dispose() {
    _title.dispose();
    _response.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Builds a Fleather controller seeded from stored HTML. A body osTicket
  /// wrote is valid HTML; anything the codec chokes on falls back to its
  /// plain-text form so the content stays editable instead of being lost.
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

  /// Encodes a document back to HTML, collapsing an empty document to `''`
  /// rather than the codec's empty-paragraph markup.
  static String _html(FleatherController c) =>
      c.document.toPlainText().trim().isEmpty
      ? ''
      : parchmentHtml.encode(c.document);

  static bool _isBlank(FleatherController c) =>
      c.document.toPlainText().trim().isEmpty;

  Future<void> _loadDepartments() async {
    try {
      final items = await ref.read(metaRepositoryProvider).departments();
      if (mounted) setState(() => _departments = items);
    } on ApiException {
      // Non-fatal: the row falls back to "All Departments".
    }
  }

  Future<void> _loadAttachments() async {
    try {
      final items = await ref
          .read(cannedRepositoryProvider)
          .attachments(widget.existing!.id);
      if (mounted) setState(() => _attachments = items);
    } on ApiException {
      // Non-fatal: existing files just aren't listed for editing.
    }
  }

  String get _deptLabel {
    if (_deptId == _kAllDepartments) return 'All Departments';
    for (final d in _departments) {
      if (d.id == _deptId) return d.name;
    }
    return 'Department #$_deptId';
  }

  /// osTicket's Department select, including its "— All Departments —" row.
  /// [pickMeta] has no such entry, so this drives [pickChoice] off a map that
  /// puts the global pool first.
  Future<void> _pickDepartment() async {
    var items = _departments;
    if (items.isEmpty) {
      try {
        items = await ref.read(metaRepositoryProvider).departments();
        if (mounted) setState(() => _departments = items);
      } on ApiException catch (e) {
        if (mounted) AppSnack.error(context, e.message);
        return;
      }
    }
    if (!mounted) return;
    final chosen = await pickChoice(
      context,
      title: 'Department',
      choices: {
        '$_kAllDepartments': '— All Departments —',
        for (final d in items) '${d.id}': d.name,
      },
      selectedValue: '$_deptId',
    );
    final id = int.tryParse(chosen ?? '');
    if (id != null && mounted) setState(() => _deptId = id);
  }

  Future<void> _pickVariable() async {
    final chosen = await pickChoice(
      context,
      title: 'Supported variables',
      choices: {
        for (final v in kCannedVariables) v.$1: '${v.$1}  —  ${v.$2}',
      },
    );
    if (chosen == null || !mounted) return;
    _insertVariable(chosen);
  }

  /// Splices [token] in at the caret (replacing any selection) rather than
  /// appending, so agents can drop a variable mid-sentence.
  void _insertVariable(String token) {
    final sel = _response.selection;
    // The document always ends in a trailing "\n" and parchment asserts an
    // insert index strictly inside it, so the last valid offset is length - 1.
    final len = _response.document.length - 1;
    final start = sel.start.clamp(0, len);
    final end = sel.end.clamp(start, len);
    _response.replaceText(
      start,
      end - start,
      token,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
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

  void _removeStoredAttachment(Attachment a) {
    setState(() {
      _removedAttachmentIds.add(a.id);
      _attachments = [
        for (final x in _attachments)
          if (x.id != a.id) x,
      ];
    });
  }

  /// The osTicket form's Reset button — throws away every edit and reloads
  /// the values the sheet opened with.
  void _reset() {
    final old = [_response, _notes];
    setState(() {
      _title.text = widget.existing?.title ?? '';
      _enabled = widget.existing?.isEnabled ?? true;
      _deptId = widget.existing?.deptId ?? _kAllDepartments;
      _response = _documentController(widget.existing?.body);
      _notes = _documentController(widget.existing?.notes);
      _newFiles.clear();
      _removedAttachmentIds.clear();
      _attachments = const [];
      _fieldErrors.clear();
    });
    // Dispose after the rebuild has swapped the editors onto the new
    // controllers — the live field still points at the old ones until then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
    if (_isEdit) _loadAttachments();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    // Mirrors Canned::update(): title required, 3 chars minimum, response
    // required. Uniqueness is server-side and comes back as a `title` error.
    final errors = <String, String>{};
    if (title.isEmpty) {
      errors['title'] = 'Title required';
    } else if (title.length < _kMinTitleLength) {
      errors['title'] = 'Title is too short. 3 chars minimum';
    }
    if (_isBlank(_response)) errors['response'] = 'Response text is required';
    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(errors);
      });
      return;
    }

    setState(() {
      _saving = true;
      _fieldErrors.clear();
    });

    final repo = ref.read(cannedRepositoryProvider);
    final responseHtml = _html(_response);
    final notesHtml = _html(_notes);
    try {
      final existingId = _targetId;
      if (existingId != null) {
        // `notes` is always sent (empty clears it) so the field behaves like
        // the osTicket form, which posts the textarea either way.
        await repo.update(existingId, {
          'title': title,
          'response': responseHtml,
          'dept_id': _deptId,
          'is_enabled': _enabled,
          'notes': notesHtml,
        });
      } else {
        final created = await repo.create(
          title: title,
          response: responseHtml,
          deptId: _deptId,
          isEnabled: _enabled,
          notes: notesHtml,
        );
        _createdId = created.id;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e.fields.isNotEmpty) {
          _fieldErrors.addAll(e.fields);
        } else {
          AppSnack.error(context, e.message);
        }
      });
      return;
    }

    final failures = await _syncAttachments(repo, _targetId!);
    if (!mounted) return;
    if (failures.isNotEmpty) {
      // The response itself saved. Keep the sheet open so the user can retry
      // just the files — _createdId makes the retry an update, not a duplicate.
      setState(() => _saving = false);
      AppSnack.error(
        context,
        'Response saved, but ${failures.length} file(s) failed. '
        'Tap save again to retry.',
      );
      return;
    }
    Navigator.pop(context, true);
  }

  /// Applies the pending attachment deletes and uploads against [id].
  /// Anything that succeeds is dropped from the pending sets so a retry only
  /// replays what actually failed. Returns the failed file names.
  Future<List<String>> _syncAttachments(CannedRepository repo, int id) async {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSheet(
      title: _isEdit ? 'Update canned response' : 'Add new canned response',
      subtitle: _isEdit ? widget.existing!.title : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. Canned response settings ---------------------------------
          const _SectionHeader(title: 'Canned response settings'),
          const SizedBox(height: 12),
          const _FieldLabel(text: 'Status', required: true),
          const SizedBox(height: 6),
          _StatusRadios(
            value: _enabled,
            onChanged: _saving ? null : (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 14),
          const _FieldLabel(text: 'Department', required: true),
          const SizedBox(height: 6),
          _PickerRow(
            icon: Icons.apartment_outlined,
            value: _deptLabel,
            onTap: _saving ? null : _pickDepartment,
          ),

          // --- 2. Canned Response ------------------------------------------
          const SizedBox(height: 20),
          const _SectionHeader(
            title: 'Canned Response',
            hint: 'Make the title short and clear.',
          ),
          const SizedBox(height: 12),
          const _FieldLabel(text: 'Title', required: true),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. Password reset instructions',
              errorText: _fieldErrors['title'],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const _FieldLabel(text: 'Response', required: true),
              const Spacer(),
              TextButton.icon(
                onPressed: _saving ? null : _pickVariable,
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('Variables'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichMessageField(
            controller: _response,
            hintText: 'Write the response agents will insert…',
            errorText: _fieldErrors['response'],
            minHeight: 140,
            maxHeight: 260,
          ),
          const SizedBox(height: 14),
          _AttachmentsSection(
            stored: _attachments,
            pending: _newFiles,
            onAdd: _saving ? null : _addFiles,
            onRemoveStored: _removeStoredAttachment,
            onRemovePending: (f) => setState(() => _newFiles.remove(f)),
          ),
          if (_fieldErrors['file'] != null) ...[
            const SizedBox(height: 4),
            AppText.paraText(
              context,
              _fieldErrors['file']!,
              color: scheme.error,
            ),
          ],

          // --- 3. Internal Notes -------------------------------------------
          const SizedBox(height: 20),
          const _SectionHeader(
            title: 'Internal Notes',
            hint: 'Notes about the canned response.',
          ),
          const SizedBox(height: 12),
          RichMessageField(
            controller: _notes,
            hintText: 'Only agents managing canned responses see this.',
            errorText: _fieldErrors['notes'],
            minHeight: 90,
            maxHeight: 180,
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _reset,
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
                      : Text(_isEdit ? 'Save changes' : 'Add response'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form primitives
// ---------------------------------------------------------------------------

/// The `<th><em>…</em></th>` rows that split the osTicket form into its
/// settings / response / notes blocks.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.hint});
  final String title;

  /// The explanatory half of the osTicket header, e.g. "Make the title short
  /// and clear." Rendered muted after a colon.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          AppText.paraText(context, title, fw: 2, color: scheme.onSurface),
          if (hint != null)
            Expanded(
              child: AppText.paraText(
                context,
                ': $hint',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Field label with the red `*` the osTicket form puts on its required rows
/// (Status, Department, Title, Response).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!required) return AppText.paraText(context, text, fw: 2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText.paraText(context, text, fw: 2),
        AppText.paraText(context, ' *', fw: 2, color: scheme.error),
      ],
    );
  }
}

/// The Active / Disabled radio pair from the osTicket form.
class _StatusRadios extends StatelessWidget {
  const _StatusRadios({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatusOption(
            label: 'Active',
            selected: value,
            onTap: onChanged == null ? null : () => onChanged!(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusOption(
            label: 'Disabled',
            selected: !value,
            onTap: onChanged == null ? null : () => onChanged!(false),
          ),
        ),
      ],
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = selected ? scheme.primary : scheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(color: tone, width: selected ? 1.4 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            AppText.subText(
              context,
              label,
              fw: selected ? 2 : 0,
              color: selected ? scheme.primary : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable value row used for the Department select.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: AppText.subText(
                context,
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Canned attachments — stored files (deleted on save) plus files picked in
/// this session (uploaded on save).
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
            const _FieldLabel(text: 'Canned attachments (optional)'),
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
