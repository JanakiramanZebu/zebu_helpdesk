import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';

/// Streams the device's coarse network reachability: `true` while any transport
/// (wifi / mobile / ethernet / vpn) is up, `false` when fully offline.
///
/// This reflects *link* status, not that the helpdesk host is actually
/// reachable — good enough to drive the offline banner. For a real end-to-end
/// check use [pingServerProvider], which hits the API.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});

/// End-to-end reachability check for a given base URL: `true` if the dispatcher
/// script answers with *any* HTTP status (even 401/404 proves the host is up),
/// `false` on DNS/connection/timeout failures. Used by the Server Settings
/// "Test connection" action.
final pingServerProvider = FutureProvider.family<bool, String>((
  ref,
  baseUrl,
) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true, // any response = reachable
    ),
  );
  try {
    await dio.get(AppConfig.apiRootFor(baseUrl));
    return true;
  } on DioException {
    return false;
  } finally {
    dio.close();
  }
});
