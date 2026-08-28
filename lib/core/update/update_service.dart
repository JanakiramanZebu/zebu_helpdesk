import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import 'update_info.dart';

/// This build's own version, read from the platform package metadata.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Dio dedicated to the CMS.
///
/// Deliberately *not* the app's [ApiClient]: that one targets the osTicket
/// dispatcher and injects the staff bearer token on every call. The CMS is a
/// different host and must never see helpdesk credentials.
final _updateDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: AppConfig.updateTimeout,
      receiveTimeout: AppConfig.updateTimeout,
      responseType: ResponseType.json,
      headers: {
        'Accept': 'application/json',
        if (AppConfig.updateToken.isNotEmpty)
          'Authorization': 'Bearer ${AppConfig.updateToken}',
      },
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// Resolves to the pending update, or null when the app is current.
///
/// **Fails open.** A CMS outage, an unpopulated field, a malformed entry or any
/// network error all resolve to null. An update prompt is an inconvenience;
/// locking staff out of the helpdesk because a CMS is unreachable is not an
/// acceptable failure mode — so anything we cannot positively confirm is
/// treated as "no update".
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (AppConfig.updateUrl.isEmpty) return null;

  final String currentVersion;
  try {
    final info = await ref.watch(packageInfoProvider.future);
    currentVersion = info.version.trim();
    if (currentVersion.isEmpty) return null;
  } catch (e) {
    debugPrint('[update] could not read current version: $e');
    return null;
  }

  try {
    final res = await ref
        .watch(_updateDioProvider)
        .get<Object?>(AppConfig.updateUrl);

    final latest = UpdateInfo.parse(
      res.data,
      field: AppConfig.updateField,
      fallbackUrl: AppConfig.downloadPageUrl,
    );
    if (latest == null) {
      // Normal while nobody has filled the CMS field in yet.
      debugPrint('[update] no version published in "${AppConfig.updateField}"');
      return null;
    }

    if (!UpdateInfo.isNewer(latest.version, currentVersion)) return null;

    // Without somewhere to send them, the sheet's only button is a dead end.
    if (latest.downloadUrl.isEmpty) {
      debugPrint('[update] ${latest.version} available but no download URL set');
      return null;
    }

    debugPrint(
      '[update] $currentVersion -> ${latest.version} (force=${latest.force})',
    );
    return latest;
  } catch (e) {
    debugPrint('[update] check failed, treating as up to date: $e');
    return null;
  }
});
