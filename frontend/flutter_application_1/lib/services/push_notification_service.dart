import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_service.dart';

void _fcmLog(String message, [Object? error, StackTrace? stack]) {
  if (error != null) {
    developer.log(message, name: 'TeamMeeterFCM', error: error, stackTrace: stack);
  } else {
    developer.log(message, name: 'TeamMeeterFCM');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Samostatný isolate: nevolaj ensureInitialized() (FCM listenery + duplicitný handler).
  await PushNotificationService.instance.ensureBgIsolateReady();
  // Na pozadí systém zobrazí správy s FCM „notification“; data-only riešime lokálne.
  if (message.notification == null) {
    await PushNotificationService.instance.showLocalFromRemoteMessage(message);
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'teammeeter_notifications',
    'TeamMeeter Notifications',
    description: 'General notifications for TeamMeeter',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;
  bool _localNotificationsReady = false;
  Map<String, dynamic>? _initialTapData;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Stream<Map<String, dynamic>> get onNotificationTap => _tapController.stream;

  Map<String, dynamic>? takeInitialTapData() {
    final data = _initialTapData;
    _initialTapData = null;
    return data;
  }

  void _emitTapData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _initialTapData = data;
    if (_tapController.hasListener) {
      _tapController.add(data);
    }
  }

  /// Minimálna inicializácia v headless isolate (FCM background); bez onMessage / duplicitného handlera.
  Future<void> ensureBgIsolateReady() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await _setupLocalNotifications();
  }

  Future<void> _setupLocalNotifications() async {
    if (_localNotificationsReady) return;

    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(payload));
          _emitTapData(data);
        } catch (_) {}
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    _localNotificationsReady = true;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    try {
      await _setupLocalNotifications();
    } catch (e, st) {
      _fcmLog('ensureInitialized: flutter_local_notifications zlyhalo', e, st);
      rethrow;
    }

    var openedFromLocalNotification = false;
    try {
      final details = await _localNotifications.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final payload = details!.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              _emitTapData(Map<String, dynamic>.from(decoded));
              openedFromLocalNotification = true;
            }
          } catch (e, st) {
            _fcmLog('getNotificationAppLaunchDetails: payload', e, st);
          }
        }
      }
    } catch (e, st) {
      _fcmLog('getNotificationAppLaunchDetails zlyhalo (ignorujeme)', e, st);
    }

    try {
      if (!openedFromLocalNotification) {
        final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null && initialMessage.data.isNotEmpty) {
          _emitTapData(initialMessage.data);
        }
      }
    } catch (e, st) {
      _fcmLog('ensureInitialized: getInitialMessage zlyhalo (ignorujeme)', e, st);
    }

    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        // V popredí Android/iOS často nezobrazia systémovú notifikáciu z FCM „notification“
        // bloku — musíme ju spracovať lokálne (inak sa nič neukáže).
        showLocalFromRemoteMessage(m, foreground: true);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data.isNotEmpty) {
          _emitTapData(message.data);
        }
      });
    } catch (e, st) {
      _fcmLog('ensureInitialized: FCM stream listen zlyhal', e, st);
      rethrow;
    }

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  Future<void> showLocalFromRemoteMessage(
    RemoteMessage message, {
    bool foreground = false,
  }) async {
    // Na pozadí systém sám zobrazí správy s FCM „notification“ — lokálne len data-only.
    if (!foreground && message.notification != null) {
      return;
    }

    final notification = message.notification;
    final type = message.data['notification_type']?.toString();
    final pushTitle = message.data['push_title']?.toString().trim();
    final pushBody = message.data['push_body']?.toString().trim();
    final title =
        notification?.title ??
        (pushTitle != null && pushTitle.isNotEmpty ? pushTitle : null) ??
        _titleFromData(type: type, data: message.data);
    final body =
        notification?.body ??
        (pushBody != null && pushBody.isNotEmpty ? pushBody : null) ??
        _bodyFromData(type: type, data: message.data);

    // Ignore unknown generic payloads to avoid "notification about notification".
    if (body == null || body.trim().isEmpty) {
      return;
    }
    final payload = jsonEncode(message.data);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: 'ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  String _titleFromType(String? type) {
    if (type == '1') return 'New message';
    if (type == '2') return 'New activity';
    if (type == '3') return 'New invitation';
    if (type == '4') return 'New assignment';
    if (type == '5') return 'Activity completed';
    if (type == '6') return 'Activity expired';
    return 'TeamMeeter';
  }

  String _titleFromData({
    required String? type,
    required Map<String, dynamic> data,
  }) {
    if (type == '1') {
      final conversationName = data['conversation_name']?.toString().trim();
      if (conversationName != null && conversationName.isNotEmpty) {
        return 'New message in $conversationName';
      }
      final conversationId = data['conversation_id']?.toString().trim();
      if (conversationId != null && conversationId.isNotEmpty) {
        return 'New message in Conversation #$conversationId';
      }
      return 'New message';
    }
    if (type == '2') {
      final activityName = data['activity_name']?.toString().trim();
      if (activityName != null && activityName.isNotEmpty) {
        return 'New activity $activityName';
      }
      final groupName = data['group_name']?.toString().trim();
      if (groupName != null && groupName.isNotEmpty) {
        return 'New activity in $groupName';
      }
      final groupId = data['group_id']?.toString().trim();
      if (groupId != null && groupId.isNotEmpty) {
        return 'New activity in Group #$groupId';
      }
      return 'New activity';
    }
    if (type == '3') {
      final targetName = data['target_name']?.toString().trim();
      if (targetName != null && targetName.isNotEmpty) {
        return 'New invitation to $targetName';
      }
      return 'New invitation';
    }
    if (type == '4') {
      final activityName = data['activity_name']?.toString().trim();
      if (activityName != null && activityName.isNotEmpty) {
        return 'New assignment in $activityName';
      }
      return 'New assignment';
    }
    if (type == '5') {
      final activityName = data['activity_name']?.toString().trim();
      if (activityName != null && activityName.isNotEmpty) {
        return 'Activity completed $activityName';
      }
      return 'Activity completed';
    }
    if (type == '6') {
      final activityName = data['activity_name']?.toString().trim();
      if (activityName != null && activityName.isNotEmpty) {
        return 'Activity expired $activityName';
      }
      return 'Activity expired';
    }
    return _titleFromType(type);
  }

  String? _bodyFromData({
    required String? type,
    required Map<String, dynamic> data,
  }) {
    if (type == '1') {
      final sender = data['sender_username']?.toString().trim();
      if (sender != null && sender.isNotEmpty) {
        return 'From $sender';
      }
      return null;
    }
    if (type == '2') {
      final groupName = data['group_name']?.toString().trim();
      if (groupName != null && groupName.isNotEmpty) {
        return 'New group activity in $groupName';
      }
      final groupId = data['group_id']?.toString().trim();
      if (groupId != null && groupId.isNotEmpty) {
        return 'New group activity in Group #$groupId';
      }
      return 'New group activity';
    }
    if (type == '3') {
      final requester = data['requester_username']?.toString().trim();
      if (requester != null && requester.isNotEmpty) {
        return 'From $requester';
      }
      return null;
    }
    if (type == '4') {
      final assigner = data['assigned_by_username']?.toString().trim();
      if (assigner != null && assigner.isNotEmpty) {
        return 'Assigned by $assigner';
      }
      return null;
    }
    if (type == '5') {
      final completer = data['completed_by_username']?.toString().trim();
      if (completer != null && completer.isNotEmpty) {
        return 'Completed by $completer';
      }
      return null;
    }
    if (type == '6') {
      final groupName = data['group_name']?.toString().trim();
      if (groupName != null && groupName.isNotEmpty) {
        return 'Deadline passed in $groupName. Activity was removed.';
      }
      return 'Deadline passed. Activity was removed.';
    }
    return null;
  }

  Future<void> syncPushTokenWithBackend(ApiService apiService) async {
    _fcmLog('syncPushTokenWithBackend: start');
    if (!apiService.hasAuthToken) {
      _fcmLog('syncPushTokenWithBackend: skip — žiadny JWT (hasAuthToken=false)');
      return;
    }

    try {
      await ensureInitialized();
    } catch (e, st) {
      _fcmLog(
        'syncPushTokenWithBackend: ensureInitialized zlyhalo, skúšam len Firebase.initializeApp',
        e,
        st,
      );
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
      } catch (e2, st2) {
        _fcmLog('syncPushTokenWithBackend: ani Firebase.initializeApp neprešlo', e2, st2);
        return;
      }
    }

    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (e, st) {
      _fcmLog('setAutoInitEnabled', e, st);
    }

    try {
      await requestPermissions();
    } catch (e, st) {
      _fcmLog('requestPermission (FCM)', e, st);
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await Permission.notification.request();
      }
    } catch (e, st) {
      _fcmLog('Permission.notification', e, st);
    }

    if (kIsWeb) {
      _fcmLog('syncPushTokenWithBackend: skip — web (bez VAPID)');
      return;
    }

    try {
      final supported = await FirebaseMessaging.instance.isSupported();
      if (!supported) {
        _fcmLog(
          'syncPushTokenWithBackend: FirebaseMessaging.isSupported() == false '
          '($defaultTargetPlatform)',
        );
        return;
      }
    } catch (e, st) {
      _fcmLog('isSupported() check', e, st);
    }

    // Po cold start niekedy getToken() zlyhá skôr, než sa viaže Play služba — krátky odklad.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    String? token;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e, st) {
        _fcmLog('getToken() pokus $attempt', e, st);
        token = null;
      }
      if (token != null && token.isNotEmpty) break;
    }
    if (token == null || token.isEmpty) {
      _fcmLog(
        'syncPushTokenWithBackend: getToken() prázdne — žiadny POST /notifications/push-token '
        '($defaultTargetPlatform; na PC desktope FCM často nie je)',
      );
      if (kDebugMode) {
        debugPrint(
          'TeamMeeter FCM: getToken() prázdny — pozri Logcat filter TeamMeeterFCM',
        );
      }
      return;
    }

    _fcmLog(
      'syncPushTokenWithBackend: volám POST /notifications/push-token (FCM token dĺžka ${token.length})',
    );
    try {
      await apiService.registerPushToken(token: token, platform: 'flutter');
      _fcmLog('syncPushTokenWithBackend: push-token OK');
    } catch (e, st) {
      _fcmLog('syncPushTokenWithBackend: registerPushToken zlyhal — žiadny zápis do DB', e, st);
      if (kDebugMode) {
        debugPrint('TeamMeeter FCM: registerPushToken zlyhal: $e\n$st');
      }
      return;
    }

    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((newToken) async {
          if (newToken.isEmpty) return;
          try {
            await apiService.registerPushToken(
              token: newToken,
              platform: 'flutter',
            );
          } catch (_) {}
        });
  }
}
