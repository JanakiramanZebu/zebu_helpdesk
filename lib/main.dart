import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/ssl_override.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Trust the helpdesk server's incomplete TLS chain (Android rejects it
  // otherwise). Scoped to the helpdesk host only — see [MyHttpOverrides].
  HttpOverrides.global = MyHttpOverrides();
  _applyHighRefreshRate();
  runApp(const ProviderScope(child: ZebuHelpdeskApp()));
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
