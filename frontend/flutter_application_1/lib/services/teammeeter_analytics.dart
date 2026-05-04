// Obal okolo Firebase Analytics s konkrétnymi udalosťami ktoré TeamMeeter potrebuje sledovať.
// Metódy zapisujú pomenované udalosti a chyby pri logovaní potichu ignorujú aby nerozbili beh aplikácie.
// AI generated with manual refinements




import 'package:firebase_analytics/firebase_analytics.dart';


class TeamMeeterAnalytics {
  TeamMeeterAnalytics._();
  static final TeamMeeterAnalytics instance = TeamMeeterAnalytics._();

  final FirebaseAnalytics _a = FirebaseAnalytics.instance;

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  
  Future<void> setUserId(String? registrationId) async {
    await _safe(() async {
      if (registrationId == null || registrationId.isEmpty) {
        await _a.setUserId(id: null);
      } else {
        await _a.setUserId(id: registrationId);
      }
    });
  }

  Future<void> clearUser() async {
    await _safe(() => _a.setUserId(id: null));
  }

  
  Future<void> logCalendarView() async {
    await _safe(() => _a.logEvent(name: 'calendar_view'));
  }

  Future<void> logConversationsView() async {
    await _safe(() => _a.logEvent(name: 'conversations_view'));
  }

  Future<void> logGroupsView() async {
    await _safe(() => _a.logEvent(name: 'groups_view'));
  }

  
  Future<void> logMainPageView() async {
    await _safe(() => _a.logEvent(name: 'main_page_view'));
  }

  
  // Tato funkcia riesi autentifikaciu uzivatela.
  // Spracuje odpoved servera a nastavi session stav.
  Future<void> logLogin({required String method}) async {
    await _safe(
      () => _a.logLogin(loginMethod: method),
    );
  }

  
  Future<void> logSignUp({required String method}) async {
    await _safe(
      () => _a.logSignUp(signUpMethod: method),
    );
  }

  // Tato funkcia riesi autentifikaciu uzivatela.
  // Spracuje odpoved servera a nastavi session stav.
  Future<void> logLogout() async {
    await _safe(() => _a.logEvent(name: 'logout'));
  }

  
  // Tato funkcia spravi navigaciu medzi obrazovkami.
  // Pred prechodom pripravi potrebne data.
  Future<void> logGroupOpen({required int groupId}) async {
    await _safe(
      () => _a.logEvent(
        name: 'group_open',
        parameters: {'group_id': groupId},
      ),
    );
  }

  
  Future<void> logGroupCreate({
    required bool queuedOffline,
    required bool inviteQrEnabled,
  }) async {
    await _safe(
      () => _a.logEvent(
        name: 'group_create',
        parameters: {
          'queued_offline': queuedOffline ? 1 : 0,
          'invite_qr_enabled': inviteQrEnabled ? 1 : 0,
        },
      ),
    );
  }

  
  Future<void> logGroupJoin({
    required bool queuedOffline,
    required String entryMethod,
  }) async {
    await _safe(
      () => _a.logEvent(
        name: 'group_join',
        parameters: {
          'queued_offline': queuedOffline ? 1 : 0,
          'entry_method': entryMethod,
        },
      ),
    );
  }

  
  Future<void> logChatMessageSend({
    required int conversationId,
    required bool socketConnected,
    required bool isReply,
  }) async {
    await _safe(
      () => _a.logEvent(
        name: 'chat_message_send',
        parameters: {
          'conversation_id': conversationId,
          'transport': socketConnected ? 'websocket' : 'offline_queue',
          'is_reply': isReply ? 1 : 0,
        },
      ),
    );
  }

  
  Future<void> logActivityCreate({
    required bool isGroupActivity,
    required bool queuedOffline,
    required bool roleAssigned,
  }) async {
    await _safe(
      () => _a.logEvent(
        name: 'activity_create',
        parameters: {
          'scope': isGroupActivity ? 'group' : 'individual',
          'queued_offline': queuedOffline ? 1 : 0,
          'role_assigned': roleAssigned ? 1 : 0,
        },
      ),
    );
  }

  
  Future<void> logPushNotificationOpen({
    required String notificationType,
    int? conversationId,
    int? activityId,
  }) async {
    await _safe(
      () => _a.logEvent(
        name: 'push_notification_open',
        parameters: {
          'notification_type': notificationType,
          if (conversationId != null) 'conversation_id': conversationId,
          if (activityId != null) 'activity_id': activityId,
        },
      ),
    );
  }
}
