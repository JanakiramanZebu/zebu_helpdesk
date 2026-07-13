import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/server_config.dart';
import 'core/network/ssl_override.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved server base URL before anything talks to the network, so the
  // API client is built pointing at the right host on the very first frame.
  final baseUrl = await ServerConfig.load();

  // Trust the helpdesk server's incomplete TLS chain (Android rejects it
  // otherwise). Scoped to the configured helpdesk host only — see
  // [MyHttpOverrides].
  HttpOverrides.global = MyHttpOverrides(baseUrl);

  await _initFirebase();
  _applyHighRefreshRate();

  runApp(
    ProviderScope(
      // Seed the runtime config with the persisted value so the first API
      // client build already targets the saved server.
      overrides: [
        serverConfigProvider.overrideWith(
          () => _SeededServerConfig(baseUrl),
        ),
      ],
      child: const ZebuHelpdeskApp(),
    ),
  );
}

/// Initialize Firebase for push. If the native config files
/// (`google-services.json` / `GoogleService-Info.plist`) are missing this
/// throws — we swallow it so the app runs with push simply disabled.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[push] Firebase not configured — push disabled ($e)');
  }
}

/// A [ServerConfig] whose initial state is the value loaded from storage.
class _SeededServerConfig extends ServerConfig {
  _SeededServerConfig(this._seed);
  final String _seed;

  @override
  String build() => _seed;
}

/// Opt into the display's highest refresh rate on Android (many phones default
/// to 60Hz even on 90/120Hz panels). No-op on other platforms — iOS ProMotion
/// is enabled via Info.plist's `CADisableMinimumFrameDurationOnPhone`.
Future<void> _applyHighRefreshRate() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {
    // Device doesn't support mode switching — safe to ignore.
  }
}
