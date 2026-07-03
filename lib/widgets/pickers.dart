import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_exception.dart';
import '../core/theme/app_text.dart';
import '../models/meta.dart';
import '../models/user.dart';
import '../providers.dart';
import 'app_snack.dart';
import 'app_sheet.dart';
import 'states.dart';

/// Where an attachment comes from. Surfaced as a popup menu on the composer.
enum AttachSource { photos, camera, files }

/// Colourful (Telegram-style) popup-menu entries for the attachment sources.
List<PopupMenuEntry<AttachSource>> attachMenuItems() => const [
  PopupMenuItem(
    value: AttachSource.photos,
    child: _AttachTile(
      icon: Icons.photo_library_rounded,
      color: Color(0xFF2F80ED),
      label: 'Photos',
    ),
  ),
  PopupMenuItem(
    value: AttachSource.camera,
    child: _AttachTile(
      icon: Icons.photo_camera_rounded,
      color: Color(0xFFEB5757),
      label: 'Camera',
    ),
  ),
  PopupMenuItem(
    value: AttachSource.files,
    child: _AttachTile(
      icon: Icons.insert_drive_file_rounded,
      color: Color(0xFF27AE60),
      label: 'Files',
    ),
  ),
];

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 12),
        AppText.subText(context, label, fw: 0),
      ],
    );
  }
}

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
Future<MetaItem?> pickMeta(
  BuildContext context,
  WidgetRef ref,
  String kind, {
  String title = 'Select',
  int? selectedId,
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
    builder: (_) => AppSheet(
      title: title,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in items)
              PickerOptionTile(
                label: m.name,
                selected: m.id == selectedId,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom-sheet user search/picker (`GET /users?q=`). Returns the chosen user.
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

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
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

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Select requester',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetSearchField(
            controller: _ctrl,
            autofocus: true,
            hintText: 'Search by name or email',
            onSubmitted: _search,
            onClear: () => _search(''),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorView(
                    error: _error!,
                    compact: true,
                    onRetry: () => _search(_lastQuery),
                  )
                : _results.isEmpty
                ? Center(child: AppText.subText(context, 'No users found'))
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
        ],
      ),
    );
  }
}
