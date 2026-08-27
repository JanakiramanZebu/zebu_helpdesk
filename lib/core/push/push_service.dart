import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../router/app_router.dart';
import '../router/routes.dart';

/// Android notification channel used for foreground FCM messages. Must match the
/// `android:name` in the manifest's default-channel meta-data so background
/// (system-tray) notifications land in the same channel.
const _androidChannel = AndroidNotificationChannel(
  'zebu_high_importance',
  'Helpdesk alerts',
  description: 'Ticket, task and mention notifications.',
  importance: Importance.high,
);

/// FCM background/terminated message handler. Must be a top-level function
/// annotated with `@pragma('vm:entry-point')` — it runs in a separate isolate.
///
/// A message carrying a `notification` block is rendered by the OS itself, so
/// this returns immediately and the tap arrives via `onMessageOpenedApp`. A
/// **data-only** message is delivered here silently — the OS draws nothing —
/// so it has to be rendered by hand, or a backgrounded app shows no alert at
/// all while a foregrounded one does.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  final title = message.data['title']?.toString() ?? '';
  final body = message.data['body']?.toString() ?? '';
  if (title.isEmpty && body.isEmpty) return;
  try {
    // Fresh plugin instance: this isolate shares no state with the app's.
    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
    await local.show(
      _notificationId(message),
      title.isEmpty ? 'New notification' : title,
      body,
      _notificationDetails(),
      payload: _payloadFrom(message.data),
    );
  } catch (e) {
    debugPrint('[push] background render failed: $e');
  }
}

/// Android notification ids must fit in a 32-bit int, and reusing one replaces
/// the tray entry it belongs to. Key on the object so repeated alerts about the
/// same ticket collapse into one row instead of stacking.
int _notificationId(RemoteMessage message) {
  final key = _payloadFrom(message.data) ?? message.messageId ?? '';
  return key.isEmpty ? 0 : key.hashCode & 0x7fffffff;
}

/// Encode just the fields needed to route a tap (`type:id`) through the
/// local-notification payload round-trip.
String? _payloadFrom(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  final id = data['object_id']?.toString() ?? data['id']?.toString();
  if (type == null || id == null) return null;
  return '$type:$id';
}

NotificationDetails _notificationDetails() => NotificationDetails(
  android: AndroidNotificationDetails(
    _androidChannel.id,
    _androidChannel.name,
    channelDescription: _androidChannel.description,
    importance: Importance.high,
    priority: Priority.high,
  ),
  iOS: const DarwinNotificationDetails(),
);

/// Owns the Firebase Cloud Messaging lifecycle:
///  * requests the OS "Allow notifications" permission,
///  * registers/removes the device token with the backend (`/push/devices`),
///  * shows foreground data messages as local notifications,
///  * routes notification taps to the relevant ticket/task.
///
/// The whole service **no-ops gracefully** when Firebase has not been configured
/// (no `google-services.json` / `GoogleService-Info.plist`), so the app builds
/// and runs unchanged until push is provisioned. Check [isAvailable] for state.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _token;
  bool _started = false;

  /// Guards against a second `start()` landing while the first is still in its
  /// awaits — the shell calls it on mount and on every resume.
  bool _starting = false;

  /// Whether the backend has acknowledged this device's token. Until it has,
  /// the agent receives nothing, so every resume retries.
  bool _registered = false;

  /// True only when `Firebase.initializeApp()` succeeded in `main` — i.e. the
  /// native Firebase config files are present.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Idempotently start the push pipeline. Safe to call on every login / app
  /// resume; only the first call does real work.
  Future<void> start() async {
    if (!isAvailable) return;
    if (_started) {
      // Already wired. A previous registration may still have failed (offline
      // at login, or a 401 mid token-refresh), so take the opportunity.
      await _ensureRegistered();
      return;
    }
    if (_starting) return;
    _starting = true;
    try {
      await _initLocalNotifications();
      await _requestPermission();

      _subs.add(
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken),
      );
      _subs.add(FirebaseMessaging.onMessage.listen(_onForegroundMessage));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromTray));

      // Only now: a throw above used to leave `_started` true, so every later
      // attempt no-opped and push stayed dead for the rest of the session.
      _started = true;
      await _registerCurrentToken();

      // Cold start: the app was launched by tapping a notification.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeFromData(initial.data);
    } catch (e) {
      debugPrint('[push] start failed: $e');
      // Leave `_started` as it is: false if setup itself failed (so the next
      // resume retries the whole thing), true if only the token round-trip did
      // (the listeners are live and _ensureRegistered will catch up).
    } finally {
      _starting = false;
    }
  }

  /// Re-attempt device registration if it hasn't succeeded yet. Cheap no-op
  /// once the backend has the token.
  Future<void> _ensureRegistered() async {
    if (_registered) return;
    await _registerCurrentToken();
  }

  /// Unregister this device and tear down listeners. Call on logout **before**
  /// tokens are cleared so the backend delete can authenticate.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _started = false;
    _registered = false;
    final token = _token;
    _token = null;
    if (token == null || !isAvailable) return;
    try {
      await _ref.read(pushRepositoryProvider).removeDevice(token);
    } catch (e) {
      debugPrint('[push] removeDevice failed: $e');
    }
  }

  // --- Setup ----------------------------------------------------------------

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // We request permission explicitly below; don't prompt twice here.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) =>
          _routeFromPayload(resp.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }

  Future<void> _requestPermission() async {
    // iOS + Android 13+: the OS "Allow notifications?" prompt.
    await FirebaseMessaging.instance.requestPermission();
    // Android 13+ POST_NOTIFICATIONS also gates local-notification display.
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    // Show banners while the app is foregrounded on iOS.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // --- Token registration ---------------------------------------------------

  Future<void> _registerCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  /// Backoff between registration attempts. An unregistered device receives
  /// *nothing*, and the failure is invisible to the agent, so a transient
  /// error at login must not be the end of it — a flaky network or a 401
  /// raced against the token refresh both land here.
  static const _registerBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  Future<void> _registerToken(String token) async {
    if (_token != token) _registered = false;
    _token = token;
    for (var attempt = 0; attempt <= _registerBackoff.length; attempt++) {
      try {
        await _ref
            .read(pushRepositoryProvider)
            .registerDevice(token: token, platform: _platform);
        _registered = true;
        return;
      } catch (e) {
        debugPrint('[push] registerDevice attempt ${attempt + 1} failed: $e');
        // The token may have rotated (or we logged out) while we waited.
        if (attempt == _registerBackoff.length || _token != token) break;
        await Future<void>.delayed(_registerBackoff[attempt]);
        if (_token != token) break;
      }
    }
    // Left unregistered on purpose: the next resume calls _ensureRegistered.
  }

  // --- Incoming messages ----------------------------------------------------

  void _onForegroundMessage(RemoteMessage message) {
    // A new alert arrived — refresh the badge and reload the Alerts list if it
    // is on screen. Must invalidate the counts provider, not the derived
    // unreadCountProvider, or the badge re-derives the cached number.
    _ref.invalidate(notificationCountsProvider);
    _ref.read(notificationsChangedProvider.notifier).bump();

    final n = message.notification;
    final title = n?.title ?? _titleFromData(message.data);
    final body = n?.body ?? _bodyFromData(message.data);
    if (title.isEmpty && body.isEmpty) return;

    _local.show(
      _notificationId(message),
      title,
      body,
      _notificationDetails(),
      payload: _payloadFrom(message.data),
    );
  }

  void _onOpenedFromTray(RemoteMessage message) =>
      _routeFromData(message.data);

  // --- Routing --------------------------------------------------------------

  void _routeFromPayload(String? payload) {
    if (payload == null) return;
    final parts = payload.split(':');
    if (parts.length != 2) return;
    _navigate(parts[0], int.tryParse(parts[1]));
  }

  void _routeFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final id = int.tryParse(
      (data['object_id'] ?? data['id'] ?? '').toString(),
    );
    _navigate(type, id);
  }

  void _navigate(String? type, int? id) {
    if (id == null) return;
    final router = _ref.read(routerProvider);
    if (type == 'task') {
      router.push(Routes.task(id));
    } else {
      router.push(Routes.ticket(id));
    }
  }

  String _titleFromData(Map<String, dynamic> data) =>
      data['title']?.toString() ?? 'New notification';

  String _bodyFromData(Map<String, dynamic> data) =>
      data['body']?.toString() ?? '';
}
