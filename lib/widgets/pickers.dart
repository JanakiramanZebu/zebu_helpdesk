import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_exception.dart';
import '../models/meta.dart';
import '../models/user.dart';
import '../providers.dart';

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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
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

/// Bottom-sheet picker over a `GET /meta/{kind}` list. Returns the chosen id.
Future<MetaItem?> pickMeta(
  BuildContext context,
  WidgetRef ref,
  String kind, {
  String title = 'Select',
}) async {
  final List<MetaItem> items;
  try {
    items = await ref.read(metaRepositoryProvider).get(kind);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<MetaItem>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final m in items)
            ListTile(
              title: Text(m.name),
              onTap: () => Navigator.pop(context, m),
            ),
        ],
      ),
    ),
  );
}

/// Bottom-sheet user search/picker (`GET /users?q=`). Returns the chosen user.
Future<AppUser?> pickUser(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<AppUser>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
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
  String? _error;

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
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final insets = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select requester',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Search by name or email',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _ctrl.clear();
                        _search('');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _results.isEmpty
                ? const Center(child: Text('No users found'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final u = _results[i];
                      return ListTile(
                        title: Text(u.name),
                        subtitle: Text(u.email),
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
