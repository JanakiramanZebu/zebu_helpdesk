import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_exception.dart';
import '../core/theme/app_text.dart';
import '../data/agent_directory.dart';
import '../models/meta.dart';
import '../models/user.dart';
import '../providers.dart';
import 'app_snack.dart';
import 'app_sheet.dart';
import 'states.dart';

/// Where an attachment comes from. Surfaced as a bottom sheet on the composer
/// (see `pickAttachSource`).
enum AttachSource { photos, camera, files }

/// Picks attachment(s) from the given [source] and returns them with bytes,
/// ready to upload. Empty if the user cancels. No UI of its own — the caller
/// presents the source choice (e.g. a [PopupMenuButton]).
Future<List<PlatformFile>> pickAttachmentsOf(AttachSource source) async {
  switch (source) {
    case AttachSource.files:
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (res == null) return const [];
      return [
        for (final f in res.files)
          if (f.bytes != null) f,
      ];
    case AttachSource.photos:
    case AttachSource.camera:
      final picker = ImagePicker();
      final List<XFile> picked;
      if (source == AttachSource.camera) {
        final x = await picker.pickImage(source: ImageSource.camera);
        picked = x == null ? const [] : [x];
      } else {
        picked = await picker.pickMultiImage();
      }
      final out = <PlatformFile>[];
      for (final x in picked) {
        final bytes = await x.readAsBytes();
        out.add(PlatformFile(name: x.name, size: bytes.length, bytes: bytes));
      }
      return out;
  }
}

/// A single option row inside a picker sheet. When [selected], the label is
/// rendered in the brand colour and bold so the current choice stands out.
class PickerOptionTile extends StatelessWidget {
  const PickerOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: AppText.subText(
        context,
        label,
        color: selected ? scheme.primary : scheme.onSurface,
        fw: selected ? 2 : 3,
      ),
      subtitle: subtitle == null ? null : AppText.subText(context, subtitle!),
      onTap: onTap,
    );
  }
}

/// Bottom-sheet picker over a `GET /meta/{kind}` list. Returns the chosen id.
/// Pass [selectedId] to highlight the current choice.
///
/// A search box is shown when [searchable] is true (e.g. the agent/team
/// assignment sheets) or automatically for any long list, so the user can
/// filter instead of scrolling.
Future<MetaItem?> pickMeta(
  BuildContext context,
  WidgetRef ref,
  String kind, {
  String title = 'Select',
  int? selectedId,
  bool searchable = false,
}) async {
  final List<MetaItem> items;
  try {
    items = await ref.read(metaRepositoryProvider).get(kind);
  } on ApiException catch (e) {
    if (context.mounted) {
      AppSnack.error(context, e.message);
    }
    return null;
  }
  if (!context.mounted) return null;
  return showAppSheet<MetaItem>(
    context: context,
    builder: (_) => _MetaPickerSheet(
      title: title,
      items: items,
      selectedId: selectedId,
      // Auto-enable search once the list is long enough to be tedious to scan.
      searchable: searchable || items.length > 8,
    ),
  );
}

/// Bottom-sheet picker over a fixed `{value: label}` list — the custom-field
/// choices on a ticket form, and the server-driven Source / Status / SLA lists.
///
/// Always scrolls (a long custom list would otherwise overflow the sheet), and
/// shows a search box once the list passes [searchThreshold] entries so a long
/// list stays scannable. Returns the chosen key, or null if dismissed.
Future<String?> pickChoice(
  BuildContext context, {
  required String title,
  required Map<String, String> choices,
  String? selectedValue,
  int searchThreshold = 10,
}) => showAppSheet<String>(
  context: context,
  builder: (_) => _ChoicePickerSheet(
    title: title,
    choices: choices,
    selectedValue: selectedValue,
    searchable: choices.length > searchThreshold,
  ),
);

class _ChoicePickerSheet extends StatefulWidget {
  const _ChoicePickerSheet({
    required this.title,
    required this.choices,
    required this.selectedValue,
    required this.searchable,
  });

  final String title;
  final Map<String, String> choices;
  final String? selectedValue;
  final bool searchable;

  @override
  State<_ChoicePickerSheet> createState() => _ChoicePickerSheetState();
}

class _ChoicePickerSheetState extends State<_ChoicePickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final entries = [
      for (final e in widget.choices.entries)
        if (q.isEmpty || e.value.toLowerCase().contains(q)) e,
    ];
    return AppSheet(
      title: widget.title,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SheetSearchField(
                  controller: _ctrl,
                  hintText: 'Search ${widget.title.toLowerCase()}',
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () => setState(() => _query = ''),
                ),
              ),
            Flexible(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: AppText.subText(
                        context,
                        'No matches',
                        color: scheme.onSurfaceVariant,
                        align: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in entries)
                          PickerOptionTile(
                            label: e.value,
                            selected: e.key == widget.selectedValue,
                            onTap: () => Navigator.pop(context, e.key),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPickerSheet extends StatefulWidget {
  const _MetaPickerSheet({
    required this.title,
    required this.items,
    required this.selectedId,
    required this.searchable,
  });

  final String title;
  final List<MetaItem> items;
  final int? selectedId;
  final bool searchable;

  @override
  State<_MetaPickerSheet> createState() => _MetaPickerSheetState();
}

class _MetaPickerSheetState extends State<_MetaPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : [
            for (final m in widget.items)
              if (m.name.toLowerCase().contains(q)) m,
          ];
    return AppSheet(
      title: widget.title,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SheetSearchField(
                  controller: _ctrl,
                  hintText: 'Search ${widget.title.toLowerCase()}',
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () => setState(() => _query = ''),
                ),
              ),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: AppText.subText(
                        context,
                        'No matches',
                        color: scheme.onSurfaceVariant,
                        align: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in filtered)
                          PickerOptionTile(
                            label: m.name,
                            selected: m.id == widget.selectedId,
                            onTap: () => Navigator.pop(context, m),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet agent picker for the assign/reassign flows, narrowed to the
/// department that will own the ticket/task (see [AgentDirectory]) so the sheet
/// only offers picks the server can accept. A "Show all agents" toggle stays
/// available for the cases the client-side scope can't prove — an agent with
/// extended department access, say.
///
/// Pass whichever the caller holds: [departmentName], or [departmentId] to have
/// it resolved from `/meta/departments`. With neither, this is the plain agent
/// list. The sheet opens straight away and fills in as the roster loads — only
/// the first assignment of a session waits on the department lookups.
Future<MetaItem?> pickAgent(
  BuildContext context,
  WidgetRef ref, {
  String? departmentName,
  int? departmentId,
  String title = 'Assign to agent',
  int? selectedId,
}) => showAppSheet<MetaItem>(
  context: context,
  builder: (_) => _AgentPickerSheet(
    title: title,
    departmentName: departmentName,
    departmentId: departmentId,
    selectedId: selectedId,
  ),
);

class _AgentPickerSheet extends ConsumerStatefulWidget {
  const _AgentPickerSheet({
    required this.title,
    required this.departmentName,
    required this.departmentId,
    required this.selectedId,
  });

  final String title;
  final String? departmentName;
  final int? departmentId;
  final int? selectedId;

  @override
  ConsumerState<_AgentPickerSheet> createState() => _AgentPickerSheetState();
}

class _AgentPickerSheetState extends ConsumerState<_AgentPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';
  AgentPickList? _list;
  String? _error;
  bool _loading = true;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(agentDirectoryProvider)
          .assignable(
            departmentName: widget.departmentName,
            departmentId: widget.departmentId,
          );
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
        // Keep the current assignee visible even when they sit outside the
        // department — otherwise the sheet opens with the selection missing.
        _showAll =
            widget.selectedId != null &&
            list.scoped &&
            !list.agents.any((a) => a.id == widget.selectedId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load agents';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _list;
    final items = list == null
        ? const <MetaItem>[]
        : (_showAll ? list.all : list.agents);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? items
        : [
            for (final m in items)
              if (m.name.toLowerCase().contains(q)) m,
          ];

    return AppSheet(
      title: widget.title,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 32,
                ),
                child: AppText.subText(
                  context,
                  _error!,
                  color: scheme.error,
                  align: TextAlign.center,
                ),
              )
            else ...[
              if (items.length > 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SheetSearchField(
                    controller: _ctrl,
                    hintText: 'Search agents',
                    onChanged: (v) => setState(() => _query = v),
                    onClear: () => setState(() => _query = ''),
                  ),
                ),
              if (list != null && list.scoped)
                _ScopeNote(
                  department: list.departmentName ?? '',
                  showingAll: _showAll,
                  onToggle: () => setState(() => _showAll = !_showAll),
                ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: AppText.subText(
                          context,
                          'No matches',
                          color: scheme.onSurfaceVariant,
                          align: TextAlign.center,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in filtered)
                            PickerOptionTile(
                              label: m.name,
                              selected: m.id == widget.selectedId,
                              onTap: () => Navigator.pop(context, m),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Agents in Support · Show all" strip above the scoped agent list, and the
/// way back to the full roster.
class _ScopeNote extends StatelessWidget {
  const _ScopeNote({
    required this.department,
    required this.showingAll,
    required this.onToggle,
  });

  final String department;
  final bool showingAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: AppText.subText(
              context,
              showingAll
                  ? 'All agents'
                  : 'Agents in ${department.isEmpty ? 'this department' : department}',
              color: scheme.onSurfaceVariant,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onToggle,
            child: AppText.subText(
              context,
              showingAll ? 'Department only' : 'Show all agents',
              color: scheme.primary,
              fw: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet requester picker. Searches existing users (`GET /users?q=`) and
/// can create a new one (`POST /users`) inline — mirroring the web "Lookup or
/// create a user" step that precedes the New Ticket form. Returns the chosen
/// (or newly created) user.
Future<AppUser?> pickUser(BuildContext context, WidgetRef ref) =>
    showAppSheet<AppUser>(
      context: context,
      builder: (_) => const _UserPickerSheet(),
    );

class _UserPickerSheet extends ConsumerStatefulWidget {
  const _UserPickerSheet();

  @override
  ConsumerState<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends ConsumerState<_UserPickerSheet> {
  final _ctrl = TextEditingController();
  List<AppUser> _results = [];
  bool _loading = false;
  Object? _error;
  String _lastQuery = '';
  Timer? _debounce;

  // "Create new user" sub-form (the web's "Add New User" panel).
  bool _creating = false;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Debounce keystrokes so we issue one `GET /users?q=` after the user pauses,
  /// not one per character.
  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    _debounce?.cancel(); // a submit/clear should win over a pending debounce
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(usersRepositoryProvider)
          .list(q: q, limit: 25);
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Open the create form, pre-filling name or email from the current query.
  void _startCreate() {
    final q = _ctrl.text.trim();
    if (q.isNotEmpty) {
      if (q.contains('@')) {
        _email.text = q;
      } else {
        _name.text = q;
      }
    }
    setState(() => _creating = true);
  }

  /// `POST /users` — de-dupes by email server-side, returning the existing user
  /// if the email is already known. Pops the sheet with the resulting user.
  Future<void> _submitCreate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final u = await ref
          .read(usersRepositoryProvider)
          .create(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, u);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: _creating ? 'New requester' : 'Select requester',
      child: _creating ? _buildCreate() : _buildSearch(),
    );
  }

  Widget _buildSearch() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetSearchField(
          controller: _ctrl,
          autofocus: true,
          hintText: 'Search by name or email',
          onChanged: _onChanged,
          onSubmitted: _search,
          onClear: () => _search(''),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 300,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorView(
                  error: _error!,
                  compact: true,
                  onRetry: () => _search(_lastQuery),
                )
              : _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText.subText(context, 'No users found'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _startCreate,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Create new user'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final u = _results[i];
                    return ListTile(
                      title: AppText.subText(context, u.name),
                      subtitle: AppText.subText(context, u.email),
                      onTap: () => Navigator.pop(context, u),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _startCreate,
            icon: const Icon(Icons.person_add_alt_1, size: 20),
            label: const Text('Create new user'),
          ),
        ),
      ],
    );
  }

  Widget _buildCreate() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email address *',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Email is required';
              if (!t.contains('@') || !t.contains('.')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Full name *',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => setState(() => _creating = false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _submitCreate,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add user'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
