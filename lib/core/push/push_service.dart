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
/// For "notification" messages the OS renders the system-tray entry itself, so
/// there's nothing to do here; the tap is delivered via `onMessageOpenedApp`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — no UI/isolate state is available here.
}

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

  /// True only when `Firebase.initializeApp()` succeeded in `main` — i.e. the
  /// native Firebase config files are present.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Idempotently start the push pipeline. Safe to call on every login / app
  /// resume; only the first call does real work.
  Future<void> start() async {
    if (_started || !isAvailable) return;
    _started = true;
    try {
      await _initLocalNotifications();
      await _requestPermission();
      await _registerCurrentToken();

      _subs.add(
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken),
      );
      _subs.add(FirebaseMessaging.onMessage.listen(_onForegroundMessage));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromTray));

      // Cold start: the app was launched by tapping a notification.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeFromData(initial.data);
    } catch (e) {
      debugPrint('[push] start failed: $e');
    }
  }

  /// Unregister this device and tear down listeners. Call on logout **before**
  /// tokens are cleared so the backend delete can authenticate.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _started = false;
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

  Future<void> _registerToken(String token) async {
    _token = token;
    try {
      await _ref
          .read(pushRepositoryProvider)
          .registerDevice(token: token, platform: _platform);
    } catch (e) {
      debugPrint('[push] registerDevice failed: $e');
    }
  }

  // --- Incoming messages ----------------------------------------------------

  void _onForegroundMessage(RemoteMessage message) {
    // A new alert arrived — refresh the unread badge immediately.
    _ref.invalidate(unreadCountProvider);

    final n = message.notification;
    final title = n?.title ?? _titleFromData(message.data);
    final body = n?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _payloadFromData(message.data),
    );
  }

  void _onOpenedFromTray(RemoteMessage message) =>
      _routeFromData(message.data);

  // --- Routing --------------------------------------------------------------

  /// Encode just the fields we need to route a tap into a compact payload
  /// string (`type:id`) carried through the local-notification round-trip.
  String? _payloadFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final id = data['object_id']?.toString() ?? data['id']?.toString();
    if (type == null || id == null) return null;
    return '$type:$id';
  }

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
}
