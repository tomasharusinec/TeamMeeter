import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/snackbar_utils.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final shouldShowBlockingLoader = _notifications.isEmpty;
    if (mounted && shouldShowBlockingLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final notifications = await api.getNotifications();
      await api.markNotificationsSeen();
      if (!mounted) return;
      setState(() => _notifications = notifications);
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted && shouldShowBlockingLoader) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteNotification(int notificationId) async {
    final previous = List<Map<String, dynamic>>.from(_notifications);
    setState(
      () => _notifications.removeWhere(
        (n) => n['id_notification'] == notificationId,
      ),
    );
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteNotification(notificationId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifications = previous);
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  Future<void> _respondMembershipRequest({
    required int notificationId,
    required bool accept,
  }) async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.respondToMembershipNotification(
        notificationId: notificationId,
        accept: accept,
      );
      await _loadNotifications();
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  String _notificationTitle(Map<String, dynamic> notification) {
    final type = (notification['type'] as num?)?.toInt() ?? 0;
    if (type == 3) {
      final requester =
          notification['requester_username']?.toString() ?? 'Niekto';
      final targetType =
          notification['membership_target_type']?.toString() ?? '';
      final targetName = targetType == 'group'
          ? notification['group_name']?.toString() ?? 'skupiny'
          : notification['conversation_name']?.toString() ?? 'konverzácie';
      return '$requester ťa pozýva do $targetName';
    }
    if (type == 4) {
      final activity =
          notification['assigned_activity_name']?.toString() ?? 'aktivity';
      final assigner =
          notification['assigned_by_username']?.toString() ?? 'Niekto';
      return '$assigner ti pridelil aktivitu: $activity';
    }
    if (type == 1) {
      final senderUsername = notification['message_sender_username']
          ?.toString()
          .trim();
      final senderId = (notification['message_sender_id'] as num?)?.toInt();
      final sender = (senderUsername != null && senderUsername.isNotEmpty)
          ? senderUsername
          : (senderId != null ? 'User #$senderId' : 'A user');

      final conversationRaw = notification['message_conversation_name']
          ?.toString()
          .trim();
      final conversationId = (notification['message_conversation_id'] as num?)
          ?.toInt();
      final conversationName =
          (conversationRaw != null && conversationRaw.isNotEmpty)
          ? conversationRaw
          : (conversationId != null
                ? 'Conversation #$conversationId'
                : 'a conversation');
      return '$sender sent a new message into conversation $conversationName';
    }
    if (type == 2) return 'Nová aktivita v skupine';
    if (type == 5) {
      final activity =
          notification['completed_activity_name']?.toString() ?? 'aktivity';
      final completer =
          notification['completed_by_username']?.toString() ?? 'Niekto';
      return '$completer dokončil aktivitu: $activity';
    }
    if (type == 6) {
      final activity =
          notification['expired_activity_name']?.toString() ?? 'aktivita';
      final group = notification['expired_group_name']?.toString();
      if (group != null && group.trim().isNotEmpty) {
        return 'Aktivita "$activity" bola zmazaná po deadlin-e v skupine $group';
      }
      return 'Aktivita "$activity" bola zmazaná po deadlin-e';
    }
    return 'Notifikácia';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikácie'),
        backgroundColor: const Color(0xFF1A0A0A),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF8B1A2C),
              Color(0xFF3D0C0C),
              Color(0xFF1A0A0A),
              Color(0xFF0D0D0D),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _notifications.isEmpty
            ? const Center(
                child: Text(
                  'Nemáš žiadne notifikácie',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadNotifications,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final notificationId =
                        (notification['id_notification'] as num?)?.toInt();
                    final status = notification['membership_status']
                        ?.toString()
                        .toLowerCase();
                    final isMembershipPending = status == 'pending';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0A0A).withAlpha(210),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withAlpha(20)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _notificationTitle(notification),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (status != null && status.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Status: $status',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (isMembershipPending &&
                                    notificationId != null)
                                  ElevatedButton(
                                    onPressed: () => _respondMembershipRequest(
                                      notificationId: notificationId,
                                      accept: true,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Prijať'),
                                  ),
                                if (isMembershipPending &&
                                    notificationId != null)
                                  const SizedBox(width: 8),
                                if (isMembershipPending &&
                                    notificationId != null)
                                  OutlinedButton(
                                    onPressed: () => _respondMembershipRequest(
                                      notificationId: notificationId,
                                      accept: false,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: const BorderSide(
                                        color: Colors.white54,
                                      ),
                                    ),
                                    child: const Text('Odmietnuť'),
                                  ),
                                const Spacer(),
                                if (notificationId != null)
                                  IconButton(
                                    onPressed: () =>
                                        _deleteNotification(notificationId),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
