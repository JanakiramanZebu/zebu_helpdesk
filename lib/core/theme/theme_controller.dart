import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns the app's [ThemeMode] (system / light / dark) and persists the choice
/// so it survives restarts. Starts on [ThemeMode.system] until the stored value
/// loads.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  static const _storage = FlutterSecureStorage();

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    final mode = _parse(raw);
    if (mode != state) state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _storage.write(key: _key, value: mode.name);
  }

  static ThemeMode _parse(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
