import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/network/server_config.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';

/// Lets an agent re-point the app at a different helpdesk backend without a
/// rebuild, and verify the host is reachable. The saved value persists across
/// launches (see [ServerConfig]); changing it rebuilds the API client so every
/// subsequent request targets the new server.
class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();
  bool _testing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(serverConfigProvider));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a server URL';
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL (e.g. https://host:port)';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL must start with http:// or https://';
    }
    return null;
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _testing = true);
    final url = _ctrl.text.trim();
    // Force a fresh check rather than a cached family result.
    ref.invalidate(pingServerProvider(url));
    final reachable = await ref.read(pingServerProvider(url).future);
    if (!mounted) return;
    setState(() => _testing = false);
    reachable
        ? AppSnack.success(context, 'Server is reachable')
        : AppSnack.error(context, 'Could not reach $url');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    await ref.read(serverConfigProvider.notifier).save(_ctrl.text.trim());
    // Rebuild the API client (and everything downstream) against the new host.
    ref.invalidate(apiClientProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    AppSnack.success(context, 'Server updated. Sign in again to continue.');
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    await ref.read(serverConfigProvider.notifier).reset();
    ref.invalidate(apiClientProvider);
    if (!mounted) return;
    _ctrl.text = ref.read(serverConfigProvider);
    setState(() => _saving = false);
    AppSnack.info(context, 'Reset to default server');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = ref
        .watch(connectivityProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final current = ref.watch(serverConfigProvider);
    final busy = _testing || _saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Live network status pill.
            Row(
              children: [
                Icon(
                  online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 18,
                  color: online ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  online ? 'Device online' : 'Device offline',
                  style: TextStyle(
                    color: online ? scheme.primary : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _ctrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              validator: _validate,
              decoration: const InputDecoration(
                labelText: 'Helpdesk base URL',
                hintText: 'https://ticket.example.com',
                prefixIcon: Icon(Icons.dns_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The API dispatcher will be:\n${AppConfig.apiRootFor(_ctrl.text.trim().isEmpty ? current : _ctrl.text.trim())}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: busy ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('Test connection'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save server'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy ? null : _reset,
              child: const Text('Reset to default'),
            ),
            const SizedBox(height: 24),
            Text(
              'Changing the server signs you out of the current session — you '
              'will need to sign in again against the new backend.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
