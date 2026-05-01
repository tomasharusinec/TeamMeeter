import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.instance.ensureInitialized();
  // In background, Android/iOS already show notification payload automatically.
  // Show local notification only for data-only messages.
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

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    await Firebase.initializeApp();

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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && initialMessage.data.isNotEmpty) {
      _emitTapData(initialMessage.data);
    }

    FirebaseMessaging.onMessage.listen(showLocalFromRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data.isNotEmpty) {
        _emitTapData(message.data);
      }
    });

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

  Future<void> showLocalFromRemoteMessage(RemoteMessage message) async {
    // Avoid duplicate alerts when FCM already contains a system notification.
    if (message.notification != null) {
      return;
    }

    final notification = message.notification;
    final type = message.data['notification_type']?.toString();
    final title =
        notification?.title ?? _titleFromData(type: type, data: message.data);
    final body =
        notification?.body ?? _bodyFromData(type: type, data: message.data);

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
    await ensureInitialized();
    await requestPermissions();

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await apiService.registerPushToken(token: token, platform: 'flutter');
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
