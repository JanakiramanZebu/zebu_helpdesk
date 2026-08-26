import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';
import 'widgets/dynamic_fields_section.dart';

/// Ticket source options (the `source` param), mirroring the web dropdown.
const _sources = ['Phone', 'Email', 'Web', 'Other'];

/// `POST /tickets` — create a ticket for an existing user.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = FleatherController();
  final _internalNote = TextEditingController();
  // Optional first reply to the requester — the web's "Response" section. Posted
  // as a follow-up `POST /tickets/{id}/reply` after the ticket is created.
  final _response = FleatherController();
  bool _responseAlert = false;
  // Focus target so a failed submit can jump to the empty subject field.
  final _subjectFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  // Anchors so a failed submit can scroll the first offending required field
  // into view — Requester/Subject/Message sit up top, Help topic/Due date lower.
  final _requesterKey = GlobalKey();
  final _subjectKey = GlobalKey();
  final _messageKey = GlobalKey();
  final _topicKey = GlobalKey();
  final _dueKey = GlobalKey();
  // Set true once the user first tries to submit, so the required tiles only
  // show their error after an attempt (not on a pristine form).
  bool _attempted = false;

  AppUser? _user;
  final List<AppUser> _collaborators = [];
  String _source = 'Phone';
  // True once the agent picks a Source, so a topic change stops overwriting it
  // with the server default.
  bool _sourceTouched = false;
  MetaItem? _topic;
  MetaItem? _department;
  MetaItem? _priority;
  MetaItem? _status;
  MetaItem? _agent;
  MetaItem? _team;
  DateTime? _due;
  final List<PlatformFile> _files = [];

  // The topic's create form (`GET /tickets/form`) — custom fields, defaults,
  // and the server's Source/Status option lists. This is the same schema the
  // web renders when a Help Topic is picked, so it works even for a topic that
  // has no tickets yet.
  final _customFieldsKey = GlobalKey();
  TicketCreateForm? _form;
  Map<String, dynamic> _customValues = {};
  Map<String, String> _customErrors = const {};
  bool _loadingForm = false;
  Object? _formError;
  // Guards against an out-of-order response when topics are switched quickly:
  // only the newest request may apply its result.
  int _formRequest = 0;
  // Per-topic cache so re-selecting a topic doesn't refetch.
  final Map<int, TicketCreateForm> _formCache = {};
  // The SLA plan the topic implies. Sent back unchanged on create — the server
  // uses it to decide whether a due date is required/computed.
  int? _slaId;
  // True once the agent picks a plan themselves. Until then the due-date lock
  // comes from the server, not from the selection (see [_canSetDue]).
  bool _slaTouched = false;
  // Plans from `GET /meta/sla`, used when the create form doesn't publish its
  // own list. This is the same set the web's create dropdown renders.
  List<FormOption> _metaSlas = const [];
  // id -> enabled, for the plans we listed. osTicket offers disabled plans in
  // the same dropdown and only an active one computes the due date.
  Map<int, bool?> _slaActive = const {};

  List<TicketField> get _customFields => _form?.fields ?? const [];

  /// The agent may set the due date only when no SLA plan drives it.
  ///
  /// Until the agent picks a plan themselves the server's `sla_locked` is
  /// authoritative — the web works the same way, locking from the help topic's
  /// `defaults.sla_id` on load and only recomputing when the dropdown changes
  /// (`toggleDueDateLock`). Deciding locally from the selection instead gets
  /// `0` wrong: "System Default" is not "no plan". `Ticket::create()` resolves
  /// it through `selectSLAId()` — department → help topic → the configured
  /// default plan — so a due date typed against a wrongly-unlocked row is
  /// dropped server-side and replaced by the SLA-computed one.
  ///
  /// Once the agent picks, the selection wins: the web hands the date back the
  /// same way when they choose System Default themselves. A **disabled** plan
  /// still doesn't drive it — the server's `$slaWillDrive` also requires
  /// `isActive()`, so locking on `id > 0` alone (as the web's JS does) would
  /// demand a due date the locked field can't provide.
  bool get _canSetDue {
    final form = _form;
    if (form == null) return true;
    if (_slaTouched && _slaOptions.isNotEmpty) return !_slaDrivesDue;
    return form.canSetDuedate;
  }

  /// True when the selected plan computes the due date server-side: a real
  /// plan (0 = System Default hands it back) that isn't disabled. Falls back to
  /// the label ("… - Disabled)") the server-published lists carry, and finally
  /// to "it drives", matching the web.
  bool get _slaDrivesDue {
    final id = _slaId ?? 0;
    if (id == 0) return false;
    final known = _slaActive[id];
    if (known != null) return known;
    final label = _slaName;
    return label == null ? true : (MetaItem.activeFromLabel(label) ?? true);
  }

  /// Selectable plans: whatever the create form publishes, else `GET /meta/sla`,
  /// led by osTicket's own "System Default" (0) entry so the agent can hand the
  /// due date back to themselves exactly like the web dropdown.
  List<FormOption> get _slaOptions {
    final fromForm = _form?.slas ?? const <FormOption>[];
    final plans = fromForm.isNotEmpty ? fromForm : _metaSlas;
    if (plans.isEmpty) return const [];
    if (plans.any((o) => o.value == '0')) return plans;
    return [
      const FormOption(value: '0', label: '— System Default —'),
      ...plans,
    ];
  }

  /// The display name of the selected SLA plan, when the plans are known.
  String? get _slaName {
    for (final o in _slaOptions) {
      if (o.value == '${_slaId ?? 0}') return o.label;
    }
    return null;
  }

  /// Everything that goes out under `custom_fields`: the topic's own answers,
  /// plus the built-in **priority** field.
  ///
  /// Priority needs special handling. osTicket's ticket form carries a built-in
  /// `priority` field — labelled "Priority Level" — which `GET /tickets/form`
  /// omits (the client renders it natively as the Priority row). But
  /// `Ticket::create()` validates the form from `$vars` and only *afterwards*
  /// applies `priority_id` (`setAnswer('priority', …)` runs past the
  /// `if ($errors) return 0;` gate). So on an install where that field is
  /// required for agents, `priority_id` alone can never satisfy validation and
  /// every create fails with "Priority Level is a required field". Sending it
  /// under the field's own name puts it in `$vars` in time. `priority_id` is
  /// still sent as well, so nothing regresses where this isn't an issue.
  Map<String, dynamic> get _formAnswers => {
    ..._customValues,
    if (_priority != null && !_customValues.containsKey('priority'))
      'priority': _priority!.id,
  };

  /// Server error keys that already render inline on their own row, so the
  /// banner doesn't repeat them. Anything else has nowhere to show and must be
  /// surfaced — otherwise a rejected create looks like nothing happened.
  static const _inlineErrorKeys = {
    'user_id',
    'subject',
    'message',
    'topicId',
    'duedate',
  };

  /// Server-driven options as the `{value: label}` map [pickChoice] takes.
  /// Insertion order is preserved, so the server's ordering survives.
  Map<String, String> _optionMap(List<FormOption> options) => {
    for (final o in options) o.value: o.label,
  };

  /// Pick an SLA plan, when the backend publishes the list.
  Future<void> _pickSla() async {
    final options = _slaOptions;
    if (options.isEmpty) return;
    final picked = await pickChoice(
      context,
      title: 'SLA plan',
      choices: _optionMap(options),
      selectedValue: '${_slaId ?? 0}',
    );
    if (picked == null) return;
    setState(() {
      _slaId = int.tryParse(picked);
      // From here the selection drives the lock, not the server's flag.
      _slaTouched = true;
      // A plan now computes the due date server-side, so drop any manual value
      // (and vice-versa: switching to System Default re-opens the picker).
      if (!_canSetDue) _due = _form?.duedate;
    });
  }

  // --- Subject / message vs. the topic's own fields --------------------------
  // `GET /tickets/form` omits the built-in `subject` and `message` so the client
  // renders them natively — in osTicket they're labelled "Issue Summary" and
  // "Issue Details" (this install renames the latter "Description"), which is
  // why the web shows them inside Ticket Details. If an install instead exposes
  // its OWN summary/description fields, we must not render a second pair, so
  // take the required `subject`/`message` from those instead.
  TicketField? get _topicSubjectField => _form?.summaryField;
  TicketField? get _topicMessageField => _form?.detailsField;

  /// Render the native inputs only when the topic form doesn't already carry an
  /// equivalent — so the agent never sees the same question twice.
  bool get _showNativeSubject => _topicSubjectField == null;
  bool get _showNativeMessage => _topicMessageField == null;

  String _customText(TicketField? f) =>
      f == null ? '' : (_customValues[f.key]?.toString().trim() ?? '');

  /// What actually goes out as the required `subject` / `message`, wherever the
  /// agent typed it.
  String get _effectiveSubject => _showNativeSubject
      ? _subject.text.trim()
      : _customText(_topicSubjectField);

  String get _effectiveMessageText =>
      _showNativeMessage ? _messageText : _customText(_topicMessageField);

  String get _effectiveMessageBody => _showNativeMessage
      ? parchmentHtml.encode(_message.document)
      : _customText(_topicMessageField);

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  String? _messageError;

  @override
  void initState() {
    super.initState();
    // Rebuild the submit button's enabled state as the required text changes.
    _subject.addListener(_onRequiredChanged);
    _message.addListener(_onRequiredChanged);
    // User-first, like the web "Open a New Ticket" flow: prompt for the
    // requester before the form is shown. If the agent cancels, the body falls
    // back to a "select requester" gate (see build()).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _user == null) _pickRequester();
    });
    // Load the default topic's form up front (fields, defaults, Source/Status
    // options) — the web does the same before the agent touches anything.
    _loadTopicForm();
    _loadSlaPlans();
  }

  /// SLA plans, so the row becomes a real picker like the web's `slaId`
  /// dropdown. Backends without the route just leave the list empty and the
  /// plan stays whatever the help topic sets.
  Future<void> _loadSlaPlans() async {
    try {
      final items = await ref.read(metaRepositoryProvider).slaPlans();
      if (!mounted) return;
      setState(() {
        _metaSlas = [
          for (final m in items) FormOption(value: '${m.id}', label: m.name),
        ];
        _slaActive = {for (final m in items) m.id: m.active};
      });
    } catch (_) {
      // No such endpoint on this build - nothing to offer.
    }
  }

  /// Look up or create the requester (`GET /users` / `POST /users`).
  Future<void> _pickRequester() async {
    final u = await pickUser(context, ref);
    if (u != null && mounted) {
      setState(() {
        _user = u;
        if (_fieldErrors.containsKey('user_id')) {
          _fieldErrors = Map.of(_fieldErrors)..remove('user_id');
        }
      });
    }
  }

  void _onRequiredChanged() => setState(() {
    // Clear the message error once the user has typed something.
    if (_messageError != null && _messageText.isNotEmpty) _messageError = null;
  });

  /// Plain-text view of the rich message, for empty/required checks.
  String get _messageText => _message.document.toPlainText().trim();

  /// Plain-text view of the optional response, to know whether to post a reply.
  String get _responseText => _response.document.toPlainText().trim();

  /// True when [v] holds a real answer (non-empty string / non-empty list).
  bool _hasValue(dynamic v) =>
      v != null &&
      !(v is String && v.trim().isEmpty) &&
      !(v is List && v.isEmpty);

  /// Required custom fields (mirroring the topic's web form) that are still
  /// blank — the create would be rejected server-side without them.
  List<TicketField> get _missingCustomFields => [
    for (final f in _customFields)
      if (f.required && !_hasValue(_customValues[f.key])) f,
  ];

  /// The required fields, mirroring the osTicket staff "Open New Ticket" form
  /// (the `/tickets` API validates the create as origin 'staff'): requester,
  /// subject, message, help topic and due date. Source always carries a
  /// default, so it never needs prompting. Plus any required custom fields the
  /// selected help topic pulls in.
  bool get _canSubmit =>
      _user != null &&
      _effectiveSubject.isNotEmpty &&
      _effectiveMessageText.isNotEmpty &&
      _topic != null &&
      (!_canSetDue || _due != null) &&
      _missingCustomFields.isEmpty;

  /// The anchor of the first still-missing required field, in top-to-bottom
  /// order, so a failed submit scrolls straight to it.
  GlobalKey? get _firstInvalidKey {
    if (_user == null) return _requesterKey;
    if (_effectiveSubject.isEmpty) {
      return _showNativeSubject ? _subjectKey : _customFieldsKey;
    }
    if (_effectiveMessageText.isEmpty) {
      return _showNativeMessage ? _messageKey : _customFieldsKey;
    }
    if (_topic == null) return _topicKey;
    if (_canSetDue && _due == null) return _dueKey;
    if (_missingCustomFields.isNotEmpty) return _customFieldsKey;
    return null;
  }

  /// Fetch (and cache) the create form for [topicId] — the topic's custom
  /// fields plus its defaults and option lists — then apply it. Called on entry
  /// (for the default topic) and on every help-topic change, mirroring the web
  /// form's re-render.
  Future<void> _loadTopicForm({int? topicId}) async {
    final cached = topicId == null ? null : _formCache[topicId];
    if (cached != null) {
      setState(() {
        _loadingForm = false;
        _formError = null;
        _applyForm(cached);
      });
      return;
    }
    final request = ++_formRequest;
    setState(() {
      _loadingForm = true;
      _formError = null;
    });
    try {
      final form = await ref
          .read(ticketsRepositoryProvider)
          .createForm(topicId: topicId);
      if (topicId != null) _formCache[topicId] = form;
      // A newer topic selection has superseded this response — drop it.
      if (!mounted || request != _formRequest) return;
      setState(() {
        _loadingForm = false;
        _applyForm(form);
      });
      // Fill in display names for any prefilled defaults (fire and forget).
      _resolveDefaultNames();
    } on ApiException catch (e) {
      if (!mounted || request != _formRequest) return;
      setState(() {
        _loadingForm = false;
        _formError = e;
      });
    }
  }

  /// Adopt [form]: swap in its fields, drop answers that no longer apply, and
  /// prefill the built-in pickers from the topic's defaults — never overwriting
  /// something the agent has already chosen.
  void _applyForm(TicketCreateForm form) {
    _form = form;
    _formError = null;
    _pruneCustomValues();

    // The SLA plan is echoed back on create; the server derives the due date
    // (and whether one is required) from it. A new topic re-issues both, so the
    // lock goes back to the server's word until the agent picks again — the
    // web's `applyHelpTopicDefaults` re-locks from the new defaults the same way.
    _slaId = form.slaId;
    _slaTouched = false;

    // Source: adopt the server's default only while the agent hasn't picked.
    final defaultSource = form.defaultSource;
    if (!_sourceTouched && defaultSource != null && defaultSource.isNotEmpty) {
      _source = defaultSource;
    }

    // The server answers for the default topic when we didn't name one — adopt
    // it so the Help topic row reflects what the form actually describes.
    if (_topic == null && form.topicId != null) {
      _topic = _placeholder(form.topicId!);
      _formCache[form.topicId!] = form;
    }
    if (_priority == null && form.priorityId != null) {
      _priority = _placeholder(form.priorityId!);
    }
    if (_department == null && form.deptId != null) {
      _department = _placeholder(form.deptId!);
    }
    // "Assign to agent" is deliberately NOT prefilled. The form's `staff_id`
    // comes back as the agent requesting it, so adopting it would silently
    // self-assign every new ticket; the row stays blank until picked.
    if (_team == null && form.teamId != null) {
      _team = _placeholder(form.teamId!);
    }
    if (_status == null) {
      final id = form.statusId ?? form.defaultStatusId;
      if (id != null) {
        _status = MetaItem(id: id, name: _statusName(form, id));
      }
    }

    // Due date: SLA-driven installs compute it, so mirror the server's value
    // and keep the row read-only. Otherwise leave whatever the agent set.
    if (form.slaLocked) {
      _due = form.duedate;
    } else if (_due == null && form.duedate != null) {
      _due = form.duedate;
    }
  }

  /// The display name for status [id] from the form's own option list, falling
  /// back to a neutral label when the server didn't list it.
  String _statusName(TicketCreateForm form, int id) {
    for (final o in form.statuses) {
      if (o.value == '$id') return o.label;
    }
    return 'Status #$id';
  }

  /// A prefilled picker value whose display name isn't known yet — the id is
  /// already correct, so the row submits fine while the name resolves.
  MetaItem _placeholder(int id) => MetaItem(id: id, name: '#$id');

  bool _isPlaceholder(MetaItem? m) => m != null && m.name == '#${m.id}';

  /// Swap any placeholder default for its real `/meta` entry, so a prefilled
  /// Department/Priority/Assignee shows its name instead of "#3". Silent on
  /// failure — the ids are already right.
  Future<void> _resolveDefaultNames() async {
    final repo = ref.read(metaRepositoryProvider);
    Future<MetaItem?> find(String kind, MetaItem? current) async {
      if (!_isPlaceholder(current)) return null;
      try {
        for (final m in await repo.get(kind)) {
          if (m.id == current!.id) return m;
        }
      } on ApiException {
        // Keep the placeholder; the id still submits correctly.
      }
      return null;
    }

    final resolved = await Future.wait([
      find(MetaKind.priorities, _priority),
      find(MetaKind.departments, _department),
      find(MetaKind.agents, _agent),
      find(MetaKind.teams, _team),
      find(MetaKind.topics, _topic),
    ]);
    if (!mounted) return;
    setState(() {
      if (resolved[0] != null) _priority = resolved[0];
      if (resolved[1] != null) _department = resolved[1];
      if (resolved[2] != null) _agent = resolved[2];
      if (resolved[3] != null) _team = resolved[3];
      if (resolved[4] != null) _topic = resolved[4];
    });
  }

  /// Drop answers/errors for fields that don't exist under the current topic.
  void _pruneCustomValues() {
    final names = _customFields.map((f) => f.key).toSet();
    _customValues = {
      for (final e in _customValues.entries)
        if (names.contains(e.key)) e.key: e.value,
    };
    _customErrors = {
      for (final e in _customErrors.entries)
        if (names.contains(e.key)) e.key: e.value,
    };
  }

  /// A field-level error to show for [key], preferring a clear, field-named
  /// message over the API's terse `"Required"` (or an empty string). Any other
  /// server message (e.g. "Subject is too long") passes through unchanged.
  String? _apiFieldError(String key, String label) {
    final msg = _fieldErrors[key];
    if (msg == null) return null;
    final t = msg.trim();
    return (t.isEmpty || t.toLowerCase() == 'required') ? '$label is required' : t;
  }

  @override
  void dispose() {
    _subject.removeListener(_onRequiredChanged);
    _message.removeListener(_onRequiredChanged);
    _subject.dispose();
    _message.dispose();
    _internalNote.dispose();
    _response.dispose();
    _subjectFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppSnack.info(context, msg);

  /// Drop an assignee the newly chosen department can't take. The picker is
  /// department-scoped, so a stale pick from the previous department would
  /// otherwise sit in the form until the server rejected it on submit.
  Future<void> _revalidateAgent() async {
    final agent = _agent;
    final dept = _department;
    if (agent == null || dept == null) return;
    final ok = await ref
        .read(agentDirectoryProvider)
        .isAssignable(
          agent.id,
          departmentName: _isPlaceholder(dept) ? null : dept.name,
          departmentId: dept.id,
        );
    if (ok || !mounted) return;
    setState(() => _agent = null);
    _toast('${agent.name} is not assignable in ${dept.name} — pick another agent');
  }

  Future<void> _submit() async {
    setState(() => _attempted = true);
    // Validate the subject field inline via the Form, and the rich message
    // separately (it's not a FormField).
    final formOk = _formKey.currentState?.validate() ?? false;
    final messageOk = _effectiveMessageText.isNotEmpty;
    // Flag each still-blank required custom field inline (by field name).
    final customErrors = <String, String>{
      for (final f in _missingCustomFields) f.key: '${f.label} is required',
    };
    setState(() {
      _messageError = (messageOk || !_showNativeMessage)
          ? null
          : 'Message is required';
      _customErrors = customErrors;
    });
    // Any missing required field (requester, subject, message, help topic, due
    // date, or a topic custom field) surfaces its own inline error — scroll the
    // first one into view and stop before calling the API.
    if (!_canSubmit || !formOk || !messageOk) {
      final ctx = _firstInvalidKey?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      // Everything the create call can't carry is applied afterwards and must
      // never fail the ticket — but each miss is collected so the agent is
      // told what didn't stick instead of being shown a bare success.
      final failed = <String>[];
      final ticket = await repo.create(
        {
          'user_id': _user!.id,
          // Wherever the agent typed them — the native inputs, or the topic's
          // own summary/description fields when it provides them.
          'subject': _effectiveSubject,
          'message': _effectiveMessageBody,
          'source': _source,
          if (_topic != null) 'topic_id': _topic!.id,
          if (_department != null) 'dept_id': _department!.id,
          if (_priority != null) 'priority_id': _priority!.id,
          if (_status != null) 'status_id': _status!.id,
          // Echo the topic's SLA back — the server derives the due date (and
          // whether one is required) from it.
          if (_slaId != null) 'sla_id': _slaId,
          // Only send a due date when the agent owns it; on an SLA-driven
          // install the server computes it and rejects a manual value.
          if (_canSetDue && _due != null) 'duedate': Fmt.apiDateTime(_due!),
          // The topic's form answers, keyed by field name — exactly the shape
          // POST /tickets accepts under `custom_fields`.
          if (_formAnswers.isNotEmpty) 'custom_fields': _formAnswers,
          // Assign INSIDE the create: one round trip, and the ticket is
          // assigned the moment it exists rather than a request later.
          if (_agent != null) 'assign_staff_id': _agent!.id,
          if (_team != null) 'assign_team_id': _team!.id,
        },
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
        onFilesFailed: (_) => failed.add('attachments'),
      );

      // Everything the create body can't carry goes out through its own
      // endpoint below — best-effort, so none of them can fail the ticket.
      //
      // Assignment fallback only: a backend that ignores the inline assign keys
      // hands the ticket back with no assignee, so try the dedicated endpoint.
      if ((_agent != null || _team != null) && ticket.assignee == null) {
        try {
          await repo.assign(
            ticket.id,
            staffId: _agent?.id,
            teamId: _team?.id,
          );
        } catch (_) {
          failed.add('assignment');
        }
      }
      // Optional first reply to the requester (the web's "Response" section).
      // The status already went out with the create, so it isn't repeated here.
      if (_responseText.isNotEmpty) {
        try {
          await repo.reply(
            ticket.id,
            body: parchmentHtml.encode(_response.document),
            alert: _responseAlert,
          );
        } catch (_) {
          failed.add('response');
        }
      }
      var collaboratorsFailed = false;
      for (final c in _collaborators) {
        try {
          await repo.addCollaborator(ticket.id, c.id);
        } catch (_) {
          collaboratorsFailed = true;
        }
      }
      if (collaboratorsFailed) failed.add('collaborators');
      if (_internalNote.text.trim().isNotEmpty) {
        try {
          await repo.note(ticket.id, body: _internalNote.text.trim());
        } catch (_) {
          failed.add('internal note');
        }
      }

      if (!mounted) return;
      // Tell the list screens a ticket now exists so they refetch rows and
      // tab count badges without waiting for a manual pull-to-refresh.
      ref.read(ticketsChangedProvider.notifier).bump();

      if (failed.isEmpty) {
        _toast('Ticket #${ticket.number} created');
      } else {
        AppSnack.error(
          context,
          'Ticket #${ticket.number} created, but the ${_phrase(failed)} '
          'could not be saved.',
        );
      }
      context.pushReplacement(Routes.ticket(ticket.id));
    } on ApiException catch (e) {
      // Route each field error to the input that owns it. Custom-field errors
      // arrive keyed by the numeric field id (sometimes by name).
      final byField = <String, String>{};
      final unattached = <String>[];
      for (final entry in e.fields.entries) {
        TicketField? owner;
        for (final f in _customFields) {
          if (entry.key == f.name || entry.key == f.key || entry.key == '${f.id}') {
            owner = f;
            break;
          }
        }
        if (owner != null) {
          byField[owner.key] = entry.value;
        } else if (!_inlineErrorKeys.contains(entry.key)) {
          // Nothing on screen can show this one — surface it in the banner
          // rather than failing the create with no explanation.
          final msg = entry.value.trim();
          unattached.add(msg.isEmpty ? '${entry.key} is required' : msg);
        }
      }
      setState(() {
        _fieldErrors = e.fields;
        if (byField.isNotEmpty) _customErrors = byField;
        _error = unattached.isNotEmpty
            ? '${e.message}\n• ${unattached.join('\n• ')}'
            : (e.fields.isEmpty ? e.message : null);
      });
      if (!mounted) return;
      AppSnack.error(context, e.message);
      // Put the reason in front of the agent: the offending custom field, or
      // the banner at the top of the form.
      final fieldCtx = byField.isEmpty
          ? null
          : _customFieldsKey.currentContext;
      if (fieldCtx != null && fieldCtx.mounted) {
        Scrollable.ensureVisible(
          fieldCtx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      } else if (_error != null && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "the response and the attachments" — a readable list for the partial
  /// success message.
  String _phrase(List<String> items) => items.length == 1
      ? items.single
      : '${items.take(items.length - 1).join(', ')} and ${items.last}';

  Future<void> _pickFiles() async {
    // Offer Camera / Photo / File, then pick from the chosen source (mirrors
    // the reply composer's "+" attach flow).
    final source = await pickAttachSource(context);
    if (source == null || !mounted) return;
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.name == f.name)) _files.add(f);
      }
    });
  }

  Future<void> _addCollaborator() async {
    final u = await pickUser(context, ref);
    if (u != null && !_collaborators.any((c) => c.id == u.id)) {
      setState(() => _collaborators.add(u));
    }
  }

  Future<void> _pickSource() async {
    // Prefer the server's permission-aware list; fall back to the static set
    // when the form hasn't loaded.
    final options = _form?.sources.isNotEmpty == true
        ? _form!.sources
        : [for (final s in _sources) FormOption(value: s, label: s)];
    final s = await pickChoice(
      context,
      title: 'Source',
      choices: _optionMap(options),
      selectedValue: _source,
    );
    if (s != null) {
      setState(() {
        _source = s;
        _sourceTouched = true;
      });
    }
  }

  /// Status options come from the create form (closed statuses are omitted for
  /// agents without the permission); `/meta/statuses` is the fallback.
  Future<void> _pickStatus() async {
    final options = _form?.statuses ?? const <FormOption>[];
    if (options.isEmpty) {
      final m = await pickMeta(
        context,
        ref,
        MetaKind.statuses,
        title: 'Status',
        selectedId: _status?.id,
      );
      if (m != null) setState(() => _status = m);
      return;
    }
    final choices = _optionMap(options);
    final picked = await pickChoice(
      context,
      title: 'Status',
      choices: choices,
      selectedValue: '${_status?.id}',
    );
    if (picked != null) {
      final id = int.tryParse(picked);
      if (id != null) {
        setState(
          () => _status = MetaItem(id: id, name: choices[picked] ?? '#$id'),
        );
      }
    }
  }

  /// Picks a saved reply and splices its (rich) body into the message at the
  /// cursor.
  Future<void> _insertCanned() async {
    final canned = await pickCannedResponse(context, ref);
    if (canned == null || !mounted) return;
    insertRichHtml(_message, canned.body);
    setState(() {
      if (_messageError != null) _messageError = null;
    });
  }

  /// Picks a saved reply and splices its (rich) body into the optional
  /// Response field — the web's "Canned Response" selector on that section.
  Future<void> _insertResponseCanned() async {
    final canned = await pickCannedResponse(context, ref);
    if (canned == null || !mounted) return;
    insertRichHtml(_response, canned.body);
    setState(() {});
  }

  /// Picks a knowledgebase article and splices its answer into the message. The
  /// list payload may omit the body, so we fetch the full article when needed.
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
    insertRichHtml(_message, html);
    setState(() {
      if (_messageError != null) _messageError = null;
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await pickDate(
      context,
      initial: _due ?? now,
      first: DateTime(now.year, now.month, now.day), // today at the earliest
      last: DateTime(now.year + 3, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );
    // Reject a due time already in the past (e.g. today + an earlier hour).
    if (picked.isBefore(DateTime.now())) {
      _toast('Due date must be in the future');
      return;
    }
    setState(() => _due = picked);
  }

  /// Uppercase caption header sitting above a grouped card section — matches
  /// the settings-style section headers used across the app (e.g. the More tab).
  Widget _sectionLabel(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: AppText.captionText(
      context,
      title.toUpperCase(),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fw: 0,
    ),
  );

  /// Wraps a set of list [rows] in a flat, rounded "list group" surface —
  /// a hairline border, no card elevation — with an inset divider between each
  /// row (aligned under the label column: 16 pad + 20 icon + 14 gap = 50).
  Widget _group(List<Widget> rows, {double dividerIndent = 50}) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            indent: dividerIndent,
            color: scheme.outlineVariant,
          ),
        );
      }
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: AppText.titleText(context, 'New ticket', fw: 1)),
      body: SafeArea(
        // Web flow: the whole form is always visible, with Requester as the
        // first required field. Closing the initial requester sheet no longer
        // gates the rest of the fields behind a "select requester" screen.
        child: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            autovalidateMode: _attempted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(message: _error!),
                ],

                // --- User & collaborators --------------------------------
                _sectionLabel('User & collaborators'),
                _group([
                  _ListRow(
                    key: _requesterKey,
                    icon: Icons.person_outline,
                    label: 'Requester',
                    value: _user?.name,
                    hint: 'Required · tap to choose',
                    error:
                        _apiFieldError('user_id', 'Requester') ??
                        (_attempted && _user == null
                            ? 'Please select a requester'
                            : null),
                    // Tap the row to choose/change the requester; the trailing
                    // "×" clears it back to the "Required · tap to choose" state.
                    trailing: _user == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove requester',
                            onPressed: () => setState(() {
                              _user = null;
                              if (_fieldErrors.containsKey('user_id')) {
                                _fieldErrors = Map.of(_fieldErrors)
                                  ..remove('user_id');
                              }
                            }),
                          ),
                    onTap: () async {
                      final u = await pickUser(context, ref);
                      if (u != null) setState(() => _user = u);
                    },
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ListRow(
                        icon: Icons.group_outlined,
                        label: 'Collaborators (Cc)',
                        value: _collaborators.isEmpty
                            ? null
                            : '${_collaborators.length} added',
                        hint: 'Optional',
                        trailing: IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: _addCollaborator,
                        ),
                        onTap: _addCollaborator,
                      ),
                      if (_collaborators.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in _collaborators)
                                Chip(
                                  label: Text(c.name),
                                  onDeleted: () => setState(
                                    () => _collaborators.remove(c),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ]),

                // --- Ticket information (source/topic/dept/priority/…) ----
                _sectionLabel('Ticket information'),
                _group([
                  _ListRow(
                    icon: Icons.podcasts_outlined,
                    label: 'Source',
                    value: _source,
                    onTap: _pickSource,
                  ),
                  _ListRow(
                    key: _topicKey,
                    icon: Icons.topic_outlined,
                    label: 'Help topic',
                    value: _topic?.name,
                    hint: 'Required · tap to choose',
                    error:
                        _apiFieldError('topicId', 'Help topic') ??
                        (_attempted && _topic == null
                            ? 'Help topic is required'
                            : null),
                    onTap: () async {
                      final m = await pickMeta(
                        context,
                        ref,
                        MetaKind.topics,
                        title: 'Help topic',
                        selectedId: _topic?.id,
                        searchable: true,
                      );
                      if (m != null && m.id != _topic?.id) {
                        setState(() => _topic = m);
                        // Re-render the form for the new topic, like the web.
                        _loadTopicForm(topicId: m.id);
                      }
                    },
                  ),
                  _ListRow(
                    icon: Icons.apartment_outlined,
                    label: 'Department',
                    value: _department?.name,
                    onTap: () async {
                      final m = await pickMeta(
                        context,
                        ref,
                        MetaKind.departments,
                        title: 'Department',
                        selectedId: _department?.id,
                      );
                      if (m != null) {
                        setState(() => _department = m);
                        await _revalidateAgent();
                      }
                    },
                  ),
                  _ListRow(
                    icon: Icons.flag_outlined,
                    label: 'Priority',
                    value: _priority?.name,
                    onTap: () async {
                      final m = await pickMeta(
                        context,
                        ref,
                        MetaKind.priorities,
                        title: 'Priority',
                        selectedId: _priority?.id,
                      );
                      if (m != null) setState(() => _priority = m);
                    },
                  ),
                  // SLA plan. A picker wherever the plans can be listed (the
                  // create form's own list, or `GET /meta/sla`) - matching the
                  // web's dropdown; read-only otherwise, since then only the
                  // help topic can pick it.
                  if (_form != null)
                    _ListRow(
                      icon: Icons.speed_outlined,
                      label: 'SLA plan',
                      value:
                          _slaName ??
                          ((_slaId == null || _slaId == 0)
                              ? 'System default'
                              : 'Set by help topic'),
                      trailing: _slaOptions.isNotEmpty
                          ? null
                          : const Icon(Icons.lock_outline, size: 18),
                      onTap: _slaOptions.isNotEmpty
                          ? _pickSla
                          : () => _toast(
                              (_slaId == null || _slaId == 0)
                                  ? 'No SLA plan on this help topic — the system default applies'
                                  : 'The help topic sets the SLA plan',
                            ),
                    ),
                  _ListRow(
                    key: _dueKey,
                    icon: Icons.event_outlined,
                    label: 'Due date',
                    value: _due == null ? null : Fmt.dateTime(_due),
                    // SLA-driven installs compute the due date server-side, so
                    // the row goes read-only and explains itself (the web shows
                    // "Computed from SLA plan" the same way).
                    hint: _canSetDue
                        ? 'Required · tap to set'
                        : 'Computed from SLA plan',
                    error: _canSetDue
                        ? (_apiFieldError('duedate', 'Due date') ??
                              (_attempted && _due == null
                                  ? 'Due date is required'
                                  : null))
                        : null,
                    trailing: !_canSetDue
                        ? const Icon(Icons.lock_outline, size: 18)
                        : _due == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _due = null),
                          ),
                    onTap: _canSetDue
                        ? _pickDue
                        : () => _toast(
                            'The SLA plan sets this ticket\'s due date',
                          ),
                  ),
                  if (_form?.canAssign ?? true)
                  _ListRow(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Assign to agent',
                    value: _agent?.name,
                    trailing: _agent == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _agent = null),
                          ),
                    onTap: () async {
                      final m = await pickAgent(
                        context,
                        ref,
                        departmentName: _isPlaceholder(_department)
                            ? null
                            : _department?.name,
                        departmentId: _department?.id,
                        title: 'Assign to agent',
                        selectedId: _agent?.id,
                      );
                      if (m != null) setState(() => _agent = m);
                    },
                  ),
                  if (_form?.canAssign ?? true)
                  _ListRow(
                    icon: Icons.groups_outlined,
                    label: 'Assign to team',
                    value: _team?.name,
                    trailing: _team == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _team = null),
                          ),
                    onTap: () async {
                      final m = await pickMeta(
                        context,
                        ref,
                        MetaKind.teams,
                        title: 'Assign to team',
                        selectedId: _team?.id,
                        searchable: true,
                      );
                      if (m != null) setState(() => _team = m);
                    },
                  ),
                ]),

                // --- Ticket details --------------------------------------
                // The built-in subject/message, which the API omits from the
                // topic form for the client to render. osTicket labels them
                // "Issue Summary" and "Issue Details" — this install shows
                // "Description" for the latter — so they read the same as the
                // web. Skipped entirely when the topic supplies its own.
                _sectionLabel('Ticket details'),
                if (_showNativeSubject || _showNativeMessage)
                  _group([
                    if (_showNativeSubject)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        child: TextFormField(
                          key: _subjectKey,
                          controller: _subject,
                          focusNode: _subjectFocus,
                          textInputAction: TextInputAction.next,
                          style: AppText.style(context, fontSize: 15, fw: 0),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Issue summary is required'
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Issue Summary *',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            errorText: _apiFieldError(
                              'subject',
                              'Issue summary',
                            ),
                          ),
                        ),
                      ),
                    if (_showNativeMessage)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText.paraText(
                              context,
                              'Description *',
                              color: scheme.onSurfaceVariant,
                            ),
                            RichMessageField(
                              key: _messageKey,
                              controller: _message,
                              hintText: 'Describe the issue…',
                              bordered: false,
                              onInsertCanned: _insertCanned,
                              onInsertFaq: _insertFaq,
                              errorText:
                                  _messageError ??
                                  _apiFieldError('message', 'Description'),
                            ),
                          ],
                        ),
                      ),
                  ], dividerIndent: 0),

                // --- Topic custom fields ---------------------------------
                // Continues the "Ticket details" section above: the web groups
                // the topic's fields with the subject/message under one header,
                // so this renders as a second card with no heading of its own.
                if (_loadingForm ||
                    _formError != null ||
                    _customFields.isNotEmpty) ...[
                  KeyedSubtree(
                    key: _customFieldsKey,
                    child: const SizedBox(height: 10),
                  ),
                  _group([
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: _loadingForm
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                ),
                              ),
                            )
                          : _formError != null
                          // The topic's fields couldn't be loaded — say so and
                          // offer a retry rather than silently showing nothing.
                          ? Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 20,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AppText.subText(
                                    context,
                                    "Couldn't load this topic's fields",
                                    color: scheme.error,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _loadTopicForm(topicId: _topic?.id),
                                  child: const Text('Retry'),
                                ),
                              ],
                            )
                          : DynamicFieldsSection(
                              fields: _customFields,
                              values: _customValues,
                              errors: _customErrors,
                              onChanged: (v) => setState(() {
                                _customValues = v;
                                // Clear inline errors for now-answered fields.
                                _customErrors = {
                                  for (final e in _customErrors.entries)
                                    if (!_hasValue(v[e.key])) e.key: e.value,
                                };
                              }),
                            ),
                    ),
                  ], dividerIndent: 0),
                ],

                // --- Attachments -----------------------------------------
                _sectionLabel('Attachments'),
                _group([
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ListRow(
                        icon: Icons.attach_file,
                        label: 'Files',
                        value: _files.isEmpty
                            ? null
                            : '${_files.length} attached',
                        hint: 'No files added',
                        trailing: TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                        onTap: _pickFiles,
                      ),
                      if (_files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final f in _files)
                                Chip(
                                  avatar: const Icon(
                                    Icons.insert_drive_file_outlined,
                                    size: 18,
                                  ),
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 180,
                                    ),
                                    child: Text(
                                      '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onDeleted: () =>
                                      setState(() => _files.remove(f)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ]),

                // --- Response (optional first reply to the requester) -----
                _sectionLabel('Response'),
                _group([
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: RichMessageField(
                      controller: _response,
                      hintText: 'Optional reply to the requester…',
                      bordered: false,
                      onInsertCanned: _insertResponseCanned,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    value: _responseAlert,
                    onChanged: (v) => setState(() => _responseAlert = v),
                    title: AppText.subText(context, 'Alert requester', fw: 0),
                    subtitle: AppText.paraText(
                      context,
                      'Email this reply to the requester',
                    ),
                  ),
                  _ListRow(
                    icon: Icons.label_outline,
                    label: 'Status',
                    value: _status?.name,
                    onTap: _pickStatus,
                  ),
                ], dividerIndent: 0),

                // --- Internal note ---------------------------------------
                _sectionLabel('Internal note'),
                _group([
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _internalNote,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Visible to staff only',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        icon: Icon(Icons.lock_outline, size: 20),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_canSubmit && !_saving) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AppText.paraText(
                          context,
                          _missingHint,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  // Always tappable (except mid-save): tapping an incomplete
                  // form runs validation and surfaces a clear inline error on
                  // each missing field, rather than leaving the user stuck at a
                  // disabled button with no explanation.
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create ticket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Human-readable list of the still-missing required fields, shown above the
  /// submit button as a nudge.
  String get _missingHint {
    final missing = <String>[
      if (_user == null) 'requester',
      if (_effectiveSubject.isEmpty) 'subject',
      if (_effectiveMessageText.isEmpty) 'message',
      if (_topic == null) 'help topic',
      if (_canSetDue && _due == null) 'due date',
      for (final f in _missingCustomFields) f.label.toLowerCase(),
    ];
    if (missing.isEmpty) return '';
    return 'Add ${missing.join(', ')} to continue';
  }
}

/// A prominent inline error banner (icon + tinted container) shown at the top
/// of the form for submit-level failures.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: AppText.subText(
              context,
              message,
              color: scheme.error,
              fw: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact, single-line "settings list" row: a small muted leading icon, the
/// field label, its selected value (or a hint) trailing on the right, and a
/// chevron. Flat and simple — no tinted badge, no stacked value. An [error]
/// paints the value line in the error color.
class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.hint,
    this.error,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final String? hint;
  final String? error;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null;
    final display = error ?? value ?? hint;
    final valueColor = hasError
        ? scheme.error
        : value != null
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: hasError ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            AppText.subText(context, label, fw: 0),
            const SizedBox(width: 12),
            Expanded(
              child: display == null
                  ? const SizedBox.shrink()
                  : AppText.subText(
                      context,
                      display,
                      color: valueColor,
                      fw: value != null ? 0 : 0,
                      align: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 4),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}
