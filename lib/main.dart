import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/ssl_override.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Trust the helpdesk server's incomplete TLS chain (Android rejects it
  // otherwise). Scoped to the helpdesk host only — see [MyHttpOverrides].
  HttpOverrides.global = MyHttpOverrides();
  runApp(const ProviderScope(child: ZebuHelpdeskApp()));
}
