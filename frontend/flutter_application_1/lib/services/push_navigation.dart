// Spája dáta zo systémovej push správy so skutočnou navigáciou v aplikácii TeamMeeter.
// Ak ešte navigator alebo prihlásenie nie sú hotové správu podrží a doručí až keď je aplikácia pripravená.
// AI generated with manual refinements




import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/notifications_screen.dart';
import '../services/teammeeter_analytics.dart';










class PushNavigator {
  PushNavigator._();

  static final PushNavigator instance = PushNavigator._();

  GlobalKey<NavigatorState>? _navigatorKey;
  Map<String, dynamic>? _pendingData;
  VoidCallback? _authListener;
  AuthProvider? _watchedAuth;
  bool _appReady = false;

  
  
  
  
  
  void attach(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  
  
  
  
  void notifyAppReady() {
    _appReady = true;
    if (_pendingData == null) return;
    if ((_navigatorKey?.currentState) == null) {
      
      _log('notifyAppReady: navigator still null, retry next frame');
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyAppReady());
      return;
    }
    final data = _pendingData!;
    _pendingData = null;
    _log('notifyAppReady: replaying buffered cold-start tap');
    scheduleMicrotask(() => dispatch(data));
  }

  
  
  
  Future<void> dispatch(Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final navigator = _navigatorKey?.currentState;
    final ctx = _navigatorKey?.currentContext;
    if (navigator == null || ctx == null) {
      _pendingData = data;
      _log(
        'dispatch: navigator not ready (appReady=$_appReady) — buffering '
        'until notifyAppReady fires',
      );
      
      
      
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingData != null) {
          notifyAppReady();
        }
      });
      return;
    }

    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    if (auth.isInitializing || !auth.isAuthenticated) {
      _pendingData = data;
      _log(
        'dispatch: auth not ready (init=${auth.isInitializing}, '
        'authed=${auth.isAuthenticated}) — waiting for AuthProvider',
      );
      _waitForAuth(auth);
      return;
    }

    await _route(navigator, ctx, auth, data);
  }

  void _waitForAuth(AuthProvider auth) {
    if (identical(_watchedAuth, auth) && _authListener != null) return;
    _detachAuthListener();
    _watchedAuth = auth;
    _authListener = () {
      if (_pendingData == null) {
        _detachAuthListener();
        return;
      }
      if (auth.isInitializing) return;
      if (!auth.isAuthenticated) return;
      final data = _pendingData!;
      _pendingData = null;
      _detachAuthListener();
      scheduleMicrotask(() => dispatch(data));
    };
    auth.addListener(_authListener!);
  }

  void _detachAuthListener() {
    final listener = _authListener;
    final auth = _watchedAuth;
    if (listener != null && auth != null) {
      auth.removeListener(listener);
    }
    _authListener = null;
    _watchedAuth = null;
  }

  Future<void> _route(
    NavigatorState navigator,
    BuildContext ctx,
    AuthProvider auth,
    Map<String, dynamic> data,
  ) async {
    final type = _parseInt(data['notification_type']);
    final conversationId = _parseInt(data['conversation_id']);
    final messageId = _parseInt(data['message_id']);

    _log(
      '_route: type=$type conversationId=$conversationId messageId=$messageId',
    );

    final isChatPush =
        (type == 1 || (messageId != null && messageId > 0)) &&
        conversationId != null &&
        conversationId > 0;

    if (isChatPush) {
      await _openChat(navigator, auth, conversationId, data);
      return;
    }

    if (conversationId != null && conversationId > 0) {
      await _openChat(navigator, auth, conversationId, data);
      return;
    }

    await _openNotificationsList(navigator);
  }

  Future<void> _openChat(
    NavigatorState navigator,
    AuthProvider auth,
    int conversationId,
    Map<String, dynamic> data,
  ) async {
    unawaited(
      TeamMeeterAnalytics.instance.logPushNotificationOpen(
        notificationType: 'chat',
        conversationId: conversationId,
      ),
    );

    var title = data['conversation_name']?.toString().trim() ?? '';
    if (title.isEmpty) {
      title = 'Conversation #$conversationId';
    }

    try {
      final conversation = await auth.apiService.getConversation(
        conversationId,
      );
      final resolvedTitle = conversation['name']?.toString().trim();
      if (resolvedTitle != null && resolvedTitle.isNotEmpty) {
        title = resolvedTitle;
      }
    } catch (e) {
      _log('_openChat: getConversation failed (using fallback title): $e');
    }

    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(conversationId: conversationId, title: title),
      ),
    );
  }

  // Tato funkcia spravi navigaciu medzi obrazovkami.
  // Pred prechodom pripravi potrebne data.
  Future<void> _openNotificationsList(NavigatorState navigator) async {
    unawaited(
      TeamMeeterAnalytics.instance.logPushNotificationOpen(
        notificationType: 'notifications_list',
      ),
    );
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  static void _log(String message) {
    
    
    
    developer.log(message, name: 'TeamMeeterPushNav');
    debugPrint('[TeamMeeterPushNav] $message');
  }
}
