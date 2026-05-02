import 'package:firebase_analytics/firebase_analytics.dart';

/// Zmysluplné udalosti pre TeamMeeter (skupiny, chat, aktivity) — zlyhanie logu nesmie ovplyvniť UX.
class TeamMeeterAnalytics {
  TeamMeeterAnalytics._();
  static final TeamMeeterAnalytics instance = TeamMeeterAnalytics._();

  final FirebaseAnalytics _a = FirebaseAnalytics.instance;

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  /// Priradí anonymné ID používateľa (interné ID registrácie, nie e-mail).
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

  /// GA4 odporúčaná udalosť [login] — metóda prihlásenia.
  Future<void> logLogin({required String method}) async {
    await _safe(
      () => _a.logLogin(loginMethod: method),
    );
  }

  /// GA4 odporúčaná udalosť [sign_up].
  Future<void> logSignUp({required String method}) async {
    await _safe(
      () => _a.logSignUp(signUpMethod: method),
    );
  }

  Future<void> logLogout() async {
    await _safe(() => _a.logEvent(name: 'logout'));
  }

  /// Používateľ otvoril detail skupiny (záujem o konkrétnu skupinu).
  Future<void> logGroupOpen({required int groupId}) async {
    await _safe(
      () => _a.logEvent(
        name: 'group_open',
        parameters: {'group_id': groupId},
      ),
    );
  }

  /// Vytvorenie skupiny (offline fronta = stále zmysluplný funnel).
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

  /// Pripojenie ku skupine cez invite kód (QR len doplní pole — rozlíšime spôsob zadania).
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

  /// Odoslanie textovej správy v chate (žiadny obsah správy).
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

  /// Nová aktivita (skupinová alebo individuálna).
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

  /// Používateľ otvoril konverzáciu z push notifikácie.
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
