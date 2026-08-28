import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_text.dart';
import '../../core/update/update_info.dart';
import '../../widgets/app_sheet.dart';

/// Bottom sheet prompting staff to install a newer native build.
///
/// Two modes, decided by [UpdateInfo.force] straight from the CMS:
///  * optional — "Later" dismisses it for this app session,
///  * forced — no dismiss path at all: no "Later", no back gesture, no swipe
///    and no scrim tap. The only way out is installing the update.
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // Swallows the Android back gesture/button on a forced update.
      canPop: !info.force,
      child: AppSheet(
        title: info.force ? 'Update required' : 'Update available',
        subtitle: 'Zebu Helpdesk ${info.version} is ready to install.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info.force) ...[
              AppText.captionText(
                context,
                'This update is required to keep using the app.',
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: () => _open(context),
              child: const Text('Update now'),
            ),
            if (!info.force) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Later'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(info.downloadUrl);

    // Leaves the app for the browser, so the sheet stays up behind it: coming
    // back without installing keeps a forced update enforced.
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open ${info.downloadUrl}')),
      );
    }
  }
}

/// Presents [UpdateSheet]. Forced updates are non-dismissible.
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: !info.force,
    enableDrag: !info.force,
    builder: (_) => UpdateSheet(info: info),
  );
}
