import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/activity.dart';
import '../models/role.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.1.123:5000';
  static const String _activityCacheKey = 'cached_activities_v1';
  static const String _activityOpsKey = 'pending_activity_ops_v1';
  static const String _activityTempIdKey = 'activity_temp_id_seed_v1';
  static const String _groupCacheKey = 'cached_groups_v1';
  static const String _groupOpsKey = 'pending_group_ops_v1';
  static const String _profileOpsKey = 'pending_profile_ops_v1';
  static const String _chatOpsKey = 'pending_chat_ops_v1';
  static const String _notificationOpsKey = 'pending_notification_ops_v1';
  static const String _conversationCacheKey = 'cached_conversations_v1';
  static const String _conversationMessagesCachePrefix =
      'cached_conversation_messages_v1_';
  static const String _notificationCacheKey = 'cached_notifications_v1';
  static const String _notificationSeenAtKey = 'notifications_seen_at_v1';
  static const String _groupTempIdKey = 'group_temp_id_seed_v1';
  static const String _groupIdMappingKey = 'group_id_mapping_v1';
  static const String _roleTempIdKey = 'role_temp_id_seed_v1';
  static const String _groupMembersCachePrefix = 'cached_group_members_v1_';
  static const String _groupRolesCachePrefix = 'cached_group_roles_v1_';
  static const String _groupIconBytesPrefix = 'cached_group_icon_bytes_v1_';

  String? _token;
  String _cacheNamespace = 'global';

  void setCacheNamespace(String? namespace) {
    final cleaned = namespace?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      _cacheNamespace = 'global';
      return;
    }
    _cacheNamespace = cleaned;
  }

  String _namespacedKey(String baseKey) => '${baseKey}_$_cacheNamespace';

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Exception _buildApiException(http.Response response, String fallbackMessage) {
    try {
      final body = jsonDecode(response.body);
      return Exception(body['message'] ?? fallbackMessage);
    } catch (_) {
      return Exception(fallbackMessage);
    }
  }

  bool _isConnectivityError(Object error) {
    return error is SocketException ||
        error is http.ClientException ||
        error.toString().toLowerCase().contains('failed host lookup') ||
        error.toString().toLowerCase().contains('connection refused');
  }

  Future<bool> isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/groups/'), headers: _headers)
          .timeout(const Duration(seconds: 4));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<List<Activity>> _loadCachedActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activityCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      return list.map(Activity.fromCacheJson).toList();
    } catch (_) {
      return [];
    }
  }

  bool _isActivityExpiredByDeadline(Activity activity) {
    final deadline = activity.parsedDeadline;
    if (deadline == null) return false;
    return deadline.isBefore(DateTime.now());
  }

  List<Activity> _withoutExpiredActivities(List<Activity> activities) {
    return activities
        .where((activity) => !_isActivityExpiredByDeadline(activity))
        .toList();
  }

  Future<void> _saveCachedActivities(List<Activity> activities) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = activities.map((a) => a.toCacheJson()).toList();
    await prefs.setString(_activityCacheKey, jsonEncode(payload));
  }

  Future<List<Map<String, dynamic>>> _loadPendingActivityOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activityOpsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingActivityOps(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activityOpsKey, jsonEncode(ops));
  }

  Future<int> _nextTempActivityId() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getInt(_activityTempIdKey) ?? -1;
    final next = seed - 1;
    await prefs.setInt(_activityTempIdKey, next);
    return seed;
  }

  Future<void> _queueActivityOperation(Map<String, dynamic> op) async {
    final ops = await _loadPendingActivityOps();
    ops.add(op);
    await _savePendingActivityOps(ops);
  }

  Future<void> _upsertCachedActivity(Activity activity) async {
    final activities = await _loadCachedActivities();
    final index = activities.indexWhere(
      (a) => a.idActivity == activity.idActivity,
    );
    if (index == -1) {
      activities.add(activity);
    } else {
      activities[index] = activity;
    }
    await _saveCachedActivities(activities);
  }

  Future<void> _removeCachedActivity(int activityId) async {
    final activities = await _loadCachedActivities();
    activities.removeWhere((a) => a.idActivity == activityId);
    await _saveCachedActivities(activities);
  }

  Future<int> _nextTempGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getInt(_groupTempIdKey) ?? -1000;
    final next = seed - 1;
    await prefs.setInt(_groupTempIdKey, next);
    return seed;
  }

  Future<int> _nextTempRoleId() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getInt(_roleTempIdKey) ?? -2000;
    final next = seed - 1;
    await prefs.setInt(_roleTempIdKey, next);
    return seed;
  }

  Future<List<Group>> _loadCachedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      return list.map(Group.fromCacheJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCachedGroups(List<Group> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _groupCacheKey,
      jsonEncode(groups.map((g) => g.toCacheJson()).toList()),
    );
  }

  Future<void> _upsertCachedGroup(Group group) async {
    final groups = await _loadCachedGroups();
    final index = groups.indexWhere((g) => g.idGroup == group.idGroup);
    if (index == -1) {
      groups.add(group);
    } else {
      groups[index] = group;
    }
    await _saveCachedGroups(groups);
  }

  List<Group> _mergeServerGroupsWithLocalPending({
    required List<Group> serverGroups,
    required List<Group> cachedGroups,
  }) {
    // Start from server data and only preserve groups that are local/pending.
    // If a regular server group disappears from server response, remove it from
    // merged output (e.g. group was deleted by another user).
    final merged = <Group>[...serverGroups];
    final indexById = <int, int>{
      for (var i = 0; i < merged.length; i++) merged[i].idGroup: i,
    };

    for (final cached in cachedGroups) {
      final isPendingLocal =
          cached.idGroup < 0 || cached.hasPendingSync || cached.isLocalOnly;
      final existingIndex = indexById[cached.idGroup];
      if (existingIndex != null) {
        final serverGroup = merged[existingIndex];
        if (isPendingLocal) {
          merged[existingIndex] = cached;
        } else {
          merged[existingIndex] = serverGroup;
        }
      } else if (isPendingLocal) {
        merged.add(cached);
        indexById[cached.idGroup] = merged.length - 1;
      }
    }

    return merged;
  }

  Future<List<Map<String, dynamic>>> _loadPendingGroupOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupOpsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingGroupOps(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupOpsKey, jsonEncode(ops));
  }

  Future<void> _queueGroupOperation(Map<String, dynamic> op) async {
    final ops = await _loadPendingGroupOps();
    ops.add(op);
    await _savePendingGroupOps(ops);
  }

  Future<Map<int, int>> _loadGroupIdMapping() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupIdMappingKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final parsed = Map<String, dynamic>.from(jsonDecode(raw));
      return parsed.map((k, v) => MapEntry(int.parse(k), v as int));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveGroupIdMapping(Map<int, int> mapping) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, int>{
      for (final entry in mapping.entries) entry.key.toString(): entry.value,
    };
    await prefs.setString(_groupIdMappingKey, jsonEncode(payload));
  }

  Future<int> _resolveServerGroupId(int groupId) async {
    if (groupId > 0) return groupId;
    var mapping = await _loadGroupIdMapping();
    final mappedBefore = mapping[groupId];
    if (mappedBefore != null && mappedBefore > 0) return mappedBefore;

    await syncPendingActivityOperations();
    mapping = await _loadGroupIdMapping();
    final mappedAfter = mapping[groupId];
    if (mappedAfter != null && mappedAfter > 0) return mappedAfter;

    throw Exception(
      'Skupina sa ešte synchronizuje. Skús to prosím znova o chvíľu.',
    );
  }

  Future<void> _applyPersistedGroupMappingToCache() async {
    final mapping = await _loadGroupIdMapping();
    if (mapping.isEmpty) return;

    final groups = await _loadCachedGroups();
    var changed = false;
    final migrated = groups.map((g) {
      final mapped = mapping[g.idGroup];
      if (mapped != null && mapped > 0 && g.idGroup != mapped) {
        changed = true;
        return g.copyWith(
          idGroup: mapped,
          isLocalOnly: false,
          hasPendingSync: false,
        );
      }
      return g;
    }).toList();

    if (changed) {
      await _saveCachedGroups(migrated);
      await _migrateGroupScopedCaches(mapping);
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingProfileOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileOpsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingProfileOps(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileOpsKey, jsonEncode(ops));
  }

  Future<void> _queueProfileOperation(Map<String, dynamic> op) async {
    final ops = await _loadPendingProfileOps();
    ops.add(op);
    await _savePendingProfileOps(ops);
  }

  Future<List<Map<String, dynamic>>> _loadPendingChatOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namespacedKey(_chatOpsKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingChatOps(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_namespacedKey(_chatOpsKey), jsonEncode(ops));
  }

  Future<List<Map<String, dynamic>>> _loadCachedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namespacedKey(_notificationCacheKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCachedNotifications(
    List<Map<String, dynamic>> notifications,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _namespacedKey(_notificationCacheKey),
      jsonEncode(notifications),
    );
  }

  int? _parseNotificationId(Map<String, dynamic> n) {
    final raw = n['id_notification'] ?? n['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _removeCachedNotification(int notificationId) async {
    final notifications = await _loadCachedNotifications();
    notifications.removeWhere(
      (n) => _parseNotificationId(n) == notificationId,
    );
    await _saveCachedNotifications(notifications);
  }

  Future<void> _updateCachedMembershipNotificationStatus({
    required int notificationId,
    required bool accept,
  }) async {
    final notifications = await _loadCachedNotifications();
    final updated = notifications.map((n) {
      final id = _parseNotificationId(n);
      if (id != notificationId) return n;
      return {...n, 'membership_status': accept ? 'accepted' : 'rejected'};
    }).toList();
    await _saveCachedNotifications(updated);
  }

  Future<List<Map<String, dynamic>>> _loadPendingNotificationOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namespacedKey(_notificationOpsKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingNotificationOps(
    List<Map<String, dynamic>> ops,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_namespacedKey(_notificationOpsKey), jsonEncode(ops));
  }

  Future<void> _queueNotificationOperation(Map<String, dynamic> op) async {
    final ops = await _loadPendingNotificationOps();
    ops.add(op);
    await _savePendingNotificationOps(ops);
  }

  Future<DateTime?> _getNotificationsSeenAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namespacedKey(_notificationSeenAtKey));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> markNotificationsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _namespacedKey(_notificationSeenAtKey),
      DateTime.now().toIso8601String(),
    );
  }

  Future<bool> hasUnreadNotifications() async {
    try {
      final notifications = await getNotifications();
      if (notifications.isEmpty) return false;
      final seenAt = await _getNotificationsSeenAt();
      if (seenAt == null) return true;
      for (final notification in notifications) {
        final createdAtRaw = notification['created_at']?.toString();
        final createdAt = createdAtRaw == null
            ? null
            : DateTime.tryParse(createdAtRaw);
        if (createdAt != null && createdAt.isAfter(seenAt)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _loadCachedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namespacedKey(_conversationCacheKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCachedConversations(
    List<Map<String, dynamic>> conversations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _namespacedKey(_conversationCacheKey),
      jsonEncode(conversations),
    );
  }

  Future<void> _removeCachedConversation(int conversationId) async {
    final conversations = await _loadCachedConversations();
    conversations.removeWhere((c) => c['id'] == conversationId);
    await _saveCachedConversations(conversations);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      _namespacedKey('$_conversationMessagesCachePrefix$conversationId'),
    );
  }

  Future<List<Map<String, dynamic>>> _loadCachedConversationMessages(
    int conversationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      _namespacedKey('$_conversationMessagesCachePrefix$conversationId'),
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversationMessagesToCache(
    int conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _namespacedKey('$_conversationMessagesCachePrefix$conversationId'),
      jsonEncode(messages),
    );
  }

  List<Map<String, dynamic>> _lastMessages(
    List<Map<String, dynamic>> messages, {
    int limit = 7,
  }) {
    if (messages.length <= limit) return messages;
    return messages.sublist(messages.length - limit);
  }

  Future<void> _prefetchLastMessagesForConversations(
    List<Map<String, dynamic>> conversations,
  ) async {
    for (final conversation in conversations) {
      final idRaw = conversation['id'];
      if (idRaw is! num) continue;
      final conversationId = idRaw.toInt();
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/conversations/$conversationId/messages'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final messages = List<Map<String, dynamic>>.from(
          data['messages'] ?? const [],
        );
        await saveConversationMessagesToCache(
          conversationId,
          _lastMessages(messages),
        );
      } catch (_) {
        // Keep existing cached messages if prefetch fails.
      }
    }
  }

  Future<void> queueOfflineConversationMessage({
    required int conversationId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final ops = await _loadPendingChatOps();
    ops.add({
      'type': 'send_message',
      'conversation_id': conversationId,
      'text': trimmed,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _savePendingChatOps(ops);
  }

  Future<void> queueOfflineConversationFileMessage({
    required int conversationId,
    required String text,
    required String filePath,
    required String fileName,
    required String fileExtension,
  }) async {
    final ops = await _loadPendingChatOps();
    ops.add({
      'type': 'send_message_with_file',
      'conversation_id': conversationId,
      'text': text.trim(),
      'file_path': filePath,
      'file_name': fileName,
      'file_extension': fileExtension,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _savePendingChatOps(ops);
  }

  Future<bool> syncPendingChatOperations() async {
    final pending = await _loadPendingChatOps();
    if (pending.isEmpty || _token == null || _token!.isEmpty) return false;
    final reachable = await isServerReachable();
    if (!reachable) return false;

    final wsUrl = Uri.parse(
      baseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://'),
    ).replace(path: '/websocket');

    WebSocket? socket;
    StreamSubscription? subscription;
    Completer<void>? awaitingFileCompleter;
    var syncedAny = false;
    try {
      socket = await WebSocket.connect(
        wsUrl.toString(),
      ).timeout(const Duration(seconds: 6));
      socket.add(jsonEncode({'type': 'auth', 'token': _token}));

      subscription = socket.listen((raw) {
        if (raw is! String) return;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['type']?.toString() == 'awaiting_file') {
            awaitingFileCompleter?.complete();
            awaitingFileCompleter = null;
          }
        } catch (_) {}
      });

      // Give backend a short moment to complete auth handshake.
      await Future.delayed(const Duration(milliseconds: 150));

      final remaining = <Map<String, dynamic>>[];
      for (final op in pending) {
        try {
          final type = op['type']?.toString();
          if (type == 'send_message') {
            socket.add(
              jsonEncode({
                'type': 'send_message',
                'conversation_id': op['conversation_id'],
                'text': op['text'],
              }),
            );
            syncedAny = true;
            continue;
          }
          if (type == 'send_message_with_file') {
            final filePath = op['file_path']?.toString();
            final fileName = op['file_name']?.toString();
            final fileExtension = op['file_extension']?.toString();
            if (filePath == null ||
                fileName == null ||
                fileExtension == null ||
                filePath.isEmpty ||
                fileName.isEmpty ||
                fileExtension.isEmpty) {
              continue;
            }
            final file = File(filePath);
            if (!file.existsSync()) {
              continue;
            }
            final bytes = await file.readAsBytes();
            if (bytes.isEmpty) {
              continue;
            }

            final fileHandshakeCompleter = Completer<void>();
            awaitingFileCompleter = fileHandshakeCompleter;
            socket.add(
              jsonEncode({
                'type': 'send_message_with_file',
                'conversation_id': op['conversation_id'],
                'text': op['text'] ?? '',
                'file_name': fileName,
                'file_extension': fileExtension,
              }),
            );
            await fileHandshakeCompleter.future.timeout(
              const Duration(seconds: 8),
            );
            socket.add(bytes);
            syncedAny = true;
            continue;
          }
          remaining.add(op);
        } catch (_) {
          remaining.add(op);
        }
      }
      await _savePendingChatOps(remaining);
      return syncedAny;
    } catch (_) {
      return false;
    } finally {
      try {
        await subscription?.cancel();
      } catch (_) {}
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<void> _saveCachedGroupMembers(
    int groupId,
    List<Map<String, dynamic>> members,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_groupMembersCachePrefix$groupId',
      jsonEncode(members),
    );
  }

  Future<List<Map<String, dynamic>>> _loadCachedGroupMembers(
    int groupId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_groupMembersCachePrefix$groupId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCachedGroupRoles(
    int groupId,
    List<Map<String, dynamic>> roles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_groupRolesCachePrefix$groupId', jsonEncode(roles));
  }

  Future<List<Map<String, dynamic>>> _loadCachedGroupRoles(int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_groupRolesCachePrefix$groupId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> _seedDefaultOfflineGroupRoles(int groupId) async {
    final existing = await _loadCachedGroupRoles(groupId);
    if (existing.isNotEmpty) return;
    final managerRoleId = await _nextTempRoleId();
    await _saveCachedGroupRoles(groupId, [
      {
        'id_role': managerRoleId,
        'name': 'Manager',
        'color': '#8B1A2C',
        'permissions': const [
          'view_activities',
          'create_activity',
          'edit_activity',
          'delete_activity',
          'assign_activity_user',
          'assign_activity_role',
          'manage_group',
          'delete_group',
          'add_user',
          'kick_user',
          'create_role',
          'edit_role',
          'delete_role',
          'add_role',
          'manage_roles',
        ],
      },
    ]);
  }

  Future<void> _migrateGroupScopedCaches(Map<int, int> idMapping) async {
    if (idMapping.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in idMapping.entries) {
      final oldId = entry.key;
      final newId = entry.value;
      if (oldId == newId) continue;

      final oldMembersKey = '$_groupMembersCachePrefix$oldId';
      final oldRolesKey = '$_groupRolesCachePrefix$oldId';
      final oldIconKey = '$_groupIconBytesPrefix$oldId';
      final newMembersKey = '$_groupMembersCachePrefix$newId';
      final newRolesKey = '$_groupRolesCachePrefix$newId';
      final newIconKey = '$_groupIconBytesPrefix$newId';

      final oldMembers = prefs.getString(oldMembersKey);
      if (oldMembers != null && oldMembers.isNotEmpty) {
        await prefs.setString(newMembersKey, oldMembers);
        await prefs.remove(oldMembersKey);
      }

      final oldRoles = prefs.getString(oldRolesKey);
      if (oldRoles != null && oldRoles.isNotEmpty) {
        await prefs.setString(newRolesKey, oldRoles);
        await prefs.remove(oldRolesKey);
      }

      final oldIcon = prefs.getString(oldIconKey);
      if (oldIcon != null && oldIcon.isNotEmpty) {
        await prefs.setString(newIconKey, oldIcon);
        await prefs.remove(oldIconKey);
      }
    }
  }

  Future<void> _saveGroupIconBytes(int groupId, List<int> bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_groupIconBytesPrefix$groupId',
      base64Encode(bytes),
    );
  }

  Future<void> _removeGroupIconBytes(int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_groupIconBytesPrefix$groupId');
  }

  Future<Uint8List?> getCachedGroupIconBytes(int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_groupIconBytesPrefix$groupId');
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheGroupIconFromServer(int groupId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/groups/$groupId/icon'), headers: _headers)
        .timeout(const Duration(seconds: 6));
    if (response.statusCode == 200) {
      await _saveGroupIconBytes(groupId, response.bodyBytes);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/authorization/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 401) {
      throw Exception('Wrong credentials');
    }
    final body = jsonDecode(response.body);
    throw Exception(body['message'] ?? 'Prihlásenie zlyhalo');
  }

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/authorization/google-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Google prihlásenie zlyhalo');
    } on SocketException catch (_) {
      throw Exception('Backend nie je dostupny. Skontroluj server a baseUrl.');
    } on http.ClientException catch (_) {
      throw Exception(
        'Sietova chyba pri volani backendu. Skontroluj baseUrl a pripojenie.',
      );
    }
  }

  Future<Map<String, dynamic>> register({
    required String firstname,
    required String surname,
    required String username,
    required String password,
    required String email,
    required String birthdate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/authorization/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firstname': firstname,
        'surname': surname,
        'username': username,
        'password': password,
        'email': email,
        'birthdate': birthdate,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Registrácia zlyhala');
    }
  }

  Future<User?> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body)['user']);
    }
    return null;
  }

  Future<void> uploadMyProfilePicture({required File imageFile}) async {
    try {
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/users/me/profile-picture'),
      );
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa nahrať profilovú fotku',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueProfileOperation({
        'type': 'upload_profile_picture',
        'path': imageFile.path,
      });
    }
  }

  Future<void> deleteMyProfilePicture() async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/users/me/profile-picture'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa odstrániť profilovú fotku',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueProfileOperation({'type': 'delete_profile_picture'});
    }
  }

  Future<List<Group>> getGroups() async {
    await _applyPersistedGroupMappingToCache();
    // Dokončiť pending skupiny pred GET, inak nová skupina / join často chýba v odpovedi.
    await syncPendingActivityOperations();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/groups/'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverGroups = (data['groups'] as List)
            .map((g) => Group.fromJson(g))
            .toList();
        final cachedGroups = await _loadCachedGroups();
        final groups = _mergeServerGroupsWithLocalPending(
          serverGroups: serverGroups,
          cachedGroups: cachedGroups,
        );
        await _saveCachedGroups(groups);
        for (final group in groups) {
          if (!group.hasIcon) continue;
          try {
            await _cacheGroupIconFromServer(group.idGroup);
          } catch (_) {
            // keep stale cached icon if fetch fails
          }
        }
        return groups;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať skupiny');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      return _loadCachedGroups();
    }
  }

  Future<Group> getGroupDetails(int groupId) async {
    if (groupId < 0) {
      final groups = await _loadCachedGroups();
      return groups.firstWhere((g) => g.idGroup == groupId);
    }
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/groups/$groupId'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final group = Group.fromJson(data['group']);
        await _upsertCachedGroup(group);
        return group;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať skupinu');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final groups = await _loadCachedGroups();
      return groups.firstWhere((g) => g.idGroup == groupId);
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(int groupId) async {
    int resolvedGroupId = groupId;
    if (groupId < 0) {
      try {
        resolvedGroupId = await _resolveServerGroupId(groupId);
      } catch (_) {
        return _loadCachedGroupMembers(groupId);
      }
    }
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/groups/$resolvedGroupId/members'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final members = List<Map<String, dynamic>>.from(data['members']);
        await _saveCachedGroupMembers(resolvedGroupId, members);
        return members;
      }
      throw _buildApiException(
        response,
        'Nepodarilo sa načítať členov skupiny',
      );
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      return _loadCachedGroupMembers(resolvedGroupId);
    }
  }

  Future<void> addGroupMember({
    required int groupId,
    required String username,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/groups/$groupId/members'),
            headers: _headers,
            body: jsonEncode({'username': username}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa pridať člena');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'add_group_member',
        'group_id': groupId,
        'username': username,
      });
    }
  }

  Future<void> removeGroupMember({
    required int groupId,
    required int userId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/groups/$groupId/members/$userId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa odstrániť člena');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'remove_group_member',
        'group_id': groupId,
        'user_id': userId,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getGroupRoles(int groupId) async {
    int resolvedGroupId = groupId;
    if (groupId < 0) {
      try {
        resolvedGroupId = await _resolveServerGroupId(groupId);
      } catch (_) {
        return _loadCachedGroupRoles(groupId);
      }
    }
    await syncPendingActivityOperations();
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/roles/groups/$resolvedGroupId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final roles = List<Map<String, dynamic>>.from(data['roles']);
        await _saveCachedGroupRoles(resolvedGroupId, roles);
        return roles;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať roly');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      return _loadCachedGroupRoles(resolvedGroupId);
    }
  }

  Future<List<Role>> getGroupRolesModel(int groupId) async {
    final roles = await getGroupRoles(groupId);
    return roles.map((role) => Role.fromJson(role)).toList();
  }

  Future<Map<String, dynamic>> createGroupRole({
    required int groupId,
    required String name,
    String? color,
    List<String> permissions = const [],
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/roles/groups/$groupId'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              if (color != null && color.isNotEmpty) 'color': color,
              'permissions': permissions,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw _buildApiException(response, 'Nepodarilo sa vytvoriť rolu');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final tempRoleId = await _nextTempRoleId();
      final cachedRoles = await _loadCachedGroupRoles(groupId);
      cachedRoles.add({
        'id_role': tempRoleId,
        'name': name,
        'color': color,
        'permissions': permissions,
      });
      await _saveCachedGroupRoles(groupId, cachedRoles);
      await _queueGroupOperation({
        'type': 'create_group_role',
        'group_id': groupId,
        'temp_role_id': tempRoleId,
        'name': name,
        'color': color,
        'permissions': permissions,
      });
      return {'queued': true, 'offline': true, 'role_id': tempRoleId};
    }
  }

  Future<void> updateGroupRole({
    required int groupId,
    required int roleId,
    String? name,
    String? color,
    List<String>? permissions,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/roles/groups/$groupId/$roleId'),
            headers: _headers,
            body: jsonEncode({
              if (name != null) 'name': name,
              if (color != null) 'color': color,
              if (permissions != null) 'permissions': permissions,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa upraviť rolu');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final cachedRoles = await _loadCachedGroupRoles(groupId);
      final updated = cachedRoles.map((role) {
        if (role['id_role'] != roleId) return role;
        return {
          ...role,
          if (name != null) 'name': name,
          if (color != null) 'color': color,
          if (permissions != null) 'permissions': permissions,
        };
      }).toList();
      await _saveCachedGroupRoles(groupId, updated);
      await _queueGroupOperation({
        'type': 'update_group_role',
        'group_id': groupId,
        'role_id': roleId,
        'name': name,
        'color': color,
        'permissions': permissions,
      });
    }
  }

  Future<void> deleteGroupRole({
    required int groupId,
    required int roleId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/roles/groups/$groupId/roles/$roleId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa zmazať rolu');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final cachedRoles = await _loadCachedGroupRoles(groupId);
      cachedRoles.removeWhere((role) => role['id_role'] == roleId);
      await _saveCachedGroupRoles(groupId, cachedRoles);
      await _queueGroupOperation({
        'type': 'delete_group_role',
        'group_id': groupId,
        'role_id': roleId,
      });
    }
  }

  Future<void> assignUserRole({
    required int groupId,
    required String username,
    required int roleId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/roles/groups/$groupId/assign'),
            headers: _headers,
            body: jsonEncode({'username': username, 'role_id': roleId}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa priradiť rolu používateľovi',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'assign_user_role',
        'group_id': groupId,
        'username': username,
        'role_id': roleId,
      });
    }
  }

  Future<void> removeUserRole({
    required int groupId,
    required int userId,
    required int roleId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
              '$baseUrl/roles/groups/$groupId/users/$userId/roles/$roleId',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa odobrať rolu používateľovi',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'remove_user_role',
        'group_id': groupId,
        'user_id': userId,
        'role_id': roleId,
      });
    }
  }

  Future<bool> hasGroupActivityAccess(int groupId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/activities/groups/$groupId/access'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['has_access'] == true;
    }
    if (response.statusCode == 403) {
      return false;
    }
    throw _buildApiException(
      response,
      'Nepodarilo sa overiť prístup ku skupinovým aktivitám',
    );
  }

  Future<List<Activity>> getGroupActivities(int groupId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/activities/groups/$groupId'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['activities'] as List)
          .map((a) => Activity.fromJson(a))
          .toList();
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať aktivity skupiny');
  }

  Future<Map<String, dynamic>> createGroupActivity({
    required int groupId,
    required String name,
    String? description,
    String? deadline,
  }) async {
    final body = {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (deadline != null) 'deadline': deadline,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/activities/groups/$groupId'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 201) {
        await syncPendingActivityOperations();
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw _buildApiException(
        response,
        'Nepodarilo sa vytvoriť aktivitu skupiny',
      );
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final tempId = await _nextTempActivityId();
      final localActivity = Activity(
        idActivity: tempId,
        name: name,
        description: description,
        deadline: deadline,
        groupId: groupId,
        status: 'todo',
        isLocalOnly: true,
        hasPendingSync: true,
      );
      await _upsertCachedActivity(localActivity);
      await _queueActivityOperation({
        'type': 'create_group_activity',
        'temp_id': tempId,
        'group_id': groupId,
        'name': name,
        'description': description,
        'deadline': deadline,
      });
      return {'activity_id': tempId, 'queued': true, 'offline': true};
    }
  }

  Future<Map<String, dynamic>> createIndividualActivity({
    required String name,
    String? description,
    String? deadline,
  }) async {
    final body = {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (deadline != null) 'deadline': deadline,
    };
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/activities/individual'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 201) {
        await syncPendingActivityOperations();
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw _buildApiException(
        response,
        'Nepodarilo sa vytvoriť individuálnu aktivitu',
      );
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final tempId = await _nextTempActivityId();
      final localActivity = Activity(
        idActivity: tempId,
        name: name,
        description: description,
        deadline: deadline,
        status: 'todo',
        isLocalOnly: true,
        hasPendingSync: true,
      );
      await _upsertCachedActivity(localActivity);
      await _queueActivityOperation({
        'type': 'create_individual_activity',
        'temp_id': tempId,
        'name': name,
        'description': description,
        'deadline': deadline,
      });
      return {'activity_id': tempId, 'queued': true, 'offline': true};
    }
  }

  Future<void> assignActivityRole(int activityId, int roleId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/activities/$activityId/roles'),
      headers: _headers,
      body: jsonEncode({'role_id': roleId}),
    );
    if (response.statusCode != 200) {
      throw _buildApiException(
        response,
        'Nepodarilo sa priradiť rolu aktivite',
      );
    }
  }

  Future<Map<String, dynamic>> getConversation(int conversationId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Map<String, dynamic>.from(data['conversation']);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať chat');
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/conversations/'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final conversations = List<Map<String, dynamic>>.from(
          data['conversations'] ?? const [],
        );
        await _saveCachedConversations(conversations);
        unawaited(_prefetchLastMessagesForConversations(conversations));
        return conversations;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať konverzácie');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      return _loadCachedConversations();
    }
  }

  Future<List<Map<String, dynamic>>> getConversationMessages(
    int conversationId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/conversations/$conversationId/messages'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = List<Map<String, dynamic>>.from(
          data['messages'] ?? const [],
        );
        await saveConversationMessagesToCache(
          conversationId,
          _lastMessages(messages),
        );
        return messages;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať správy');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final cached = await _loadCachedConversationMessages(conversationId);
      return _lastMessages(cached);
    }
  }

  Future<int> createConversation({
    required String name,
    required List<String> participantUsernames,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'participant_usernames': participantUsernames,
      }),
    );
    if (response.statusCode == 201) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      return (data['conversation_id'] as num).toInt();
    }
    throw _buildApiException(response, 'Nepodarilo sa vytvoriť konverzáciu');
  }

  Future<List<Map<String, dynamic>>> getConversationParticipants(
    int conversationId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$conversationId/participants'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['participants'] ?? const []);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať účastníkov');
  }

  Future<void> addConversationParticipant({
    required int conversationId,
    required String username,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/participants'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa pridať účastníka');
    }
  }

  Future<void> deleteConversation(int conversationId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa zmazať konverzáciu');
    }
    await _removeCachedConversation(conversationId);
  }

  Future<void> deleteConversationMessage({
    required int conversationId,
    required int messageId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa zmazať správu');
    }
  }

  Future<Map<String, dynamic>> downloadConversationFile(int fileId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/files/$fileId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final disposition = response.headers['content-disposition'] ?? '';
      var filename = 'attachment_$fileId';
      final marker = 'filename=';
      final idx = disposition.indexOf(marker);
      if (idx != -1) {
        filename = disposition
            .substring(idx + marker.length)
            .replaceAll('"', '');
      }
      return {'bytes': response.bodyBytes, 'filename': filename};
    }
    throw _buildApiException(response, 'Nepodarilo sa stiahnuť súbor');
  }

  Future<void> deleteGroup(int groupId) async {
    if (groupId < 0) {
      final groupOps = await _loadPendingGroupOps();
      groupOps.removeWhere((op) {
        final opGroupId = op['group_id'];
        final opTempId = op['temp_id'];
        return opGroupId == groupId || opTempId == groupId;
      });
      await _savePendingGroupOps(groupOps);

      final groups = await _loadCachedGroups();
      groups.removeWhere((g) => g.idGroup == groupId);
      await _saveCachedGroups(groups);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_groupMembersCachePrefix$groupId');
      await prefs.remove('$_groupRolesCachePrefix$groupId');
      await prefs.remove('$_groupIconBytesPrefix$groupId');
      return;
    }
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/groups/$groupId'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa zmazať skupinu');
      }
      final groups = await _loadCachedGroups();
      groups.removeWhere((g) => g.idGroup == groupId);
      await _saveCachedGroups(groups);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_groupMembersCachePrefix$groupId');
      await prefs.remove('$_groupRolesCachePrefix$groupId');
      await prefs.remove('$_groupIconBytesPrefix$groupId');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({'type': 'delete_group', 'group_id': groupId});
      final groups = await _loadCachedGroups();
      groups.removeWhere((g) => g.idGroup == groupId);
      await _saveCachedGroups(groups);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_groupMembersCachePrefix$groupId');
      await prefs.remove('$_groupRolesCachePrefix$groupId');
      await prefs.remove('$_groupIconBytesPrefix$groupId');
    }
  }

  Future<void> updateGroup({
    required int groupId,
    String? name,
    int? capacity,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/groups/$groupId'),
            headers: _headers,
            body: jsonEncode({
              if (name != null) 'name': name,
              if (capacity != null) 'capacity': capacity,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa upraviť skupinu');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'update_group',
        'group_id': groupId,
        'name': name,
        'capacity': capacity,
      });
    }
    final groups = await _loadCachedGroups();
    final updated = groups.map((g) {
      if (g.idGroup != groupId) return g;
      return g.copyWith(
        name: name ?? g.name,
        capacity: capacity ?? g.capacity,
        hasPendingSync: true,
      );
    }).toList();
    await _saveCachedGroups(updated);
  }

  Future<void> uploadGroupIcon({
    required int groupId,
    required File imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    await _saveGroupIconBytes(groupId, bytes);
    final groups = await _loadCachedGroups();
    final updatedGroups = groups.map((g) {
      if (g.idGroup != groupId) return g;
      return g.copyWith(hasIcon: true, hasPendingSync: true);
    }).toList();
    await _saveCachedGroups(updatedGroups);
    try {
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/groups/$groupId/icon'),
      );
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa nahrať ikonu skupiny',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'upload_group_icon',
        'group_id': groupId,
        'path': imageFile.path,
      });
    }
  }

  Future<void> deleteGroupIcon(int groupId) async {
    await _removeGroupIconBytes(groupId);
    final groups = await _loadCachedGroups();
    final updatedGroups = groups.map((g) {
      if (g.idGroup != groupId) return g;
      return g.copyWith(hasIcon: false, hasPendingSync: true);
    }).toList();
    await _saveCachedGroups(updatedGroups);
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/groups/$groupId/icon'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa odstrániť ikonu skupiny',
        );
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'delete_group_icon',
        'group_id': groupId,
      });
    }
  }

  Future<List<Activity>> getMyActivities() async {
    unawaited(syncPendingActivityOperations());
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/activities/me'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final activities = (data['activities'] as List)
            .map((a) => Activity.fromJson(a))
            .toList();
        final filtered = _withoutExpiredActivities(activities);
        await _saveCachedActivities(filtered);
        return filtered;
      }
      throw _buildApiException(response, 'Nepodarilo sa načítať aktivity');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final cached = await _loadCachedActivities();
      final filtered = _withoutExpiredActivities(cached);
      if (filtered.length != cached.length) {
        await _saveCachedActivities(filtered);
      }
      return filtered;
    }
  }

  Future<Activity> getActivityDetails(int activityId) async {
    if (activityId < 0) {
      final cached = await _loadCachedActivities();
      return cached.firstWhere((a) => a.idActivity == activityId);
    }
    final response = await http.get(
      Uri.parse('$baseUrl/activities/$activityId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Activity.fromJson(Map<String, dynamic>.from(data['activity']));
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať detail aktivity');
  }

  Future<void> deleteActivity(int activityId) async {
    if (activityId < 0) {
      final ops = await _loadPendingActivityOps();
      ops.removeWhere((op) => op['temp_id'] == activityId);
      await _savePendingActivityOps(ops);
      await _removeCachedActivity(activityId);
      return;
    }
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/activities/$activityId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa zmazať aktivitu');
      }
      await _removeCachedActivity(activityId);
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueActivityOperation({
        'type': 'delete_activity',
        'activity_id': activityId,
      });
      final cached = await _loadCachedActivities();
      await _saveCachedActivities(
        cached.where((a) => a.idActivity != activityId).toList(),
      );
    }
  }

  Future<void> updateActivityStatus(int activityId, String status) async {
    try {
      if (activityId > 0) {
        final response = await http
            .put(
              Uri.parse('$baseUrl/activities/$activityId'),
              headers: _headers,
              body: jsonEncode({'status': status}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw _buildApiException(
            response,
            'Nepodarilo sa upraviť status aktivity',
          );
        }
      } else {
        throw const SocketException('Local activity - pending sync');
      }
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueActivityOperation({
        'type': 'update_activity_status',
        'activity_id': activityId,
        'status': status,
      });
    }

    final cached = await _loadCachedActivities();
    final updated = cached.map((a) {
      if (a.idActivity != activityId) return a;
      return a.copyWith(status: status, hasPendingSync: true);
    }).toList();
    await _saveCachedActivities(updated);
  }

  Future<bool> syncPendingActivityOperations() async {
    final reachable = await isServerReachable();
    if (!reachable) return false;
    await syncPendingChatOperations();
    await _syncPendingNotificationOperations();
    await _syncPendingProfileOperations();
    await _syncPendingGroupOperations();
    final pendingOps = await _loadPendingActivityOps();
    if (pendingOps.isEmpty) return false;

    final Map<int, int> idMapping = {};
    final List<Map<String, dynamic>> remaining = [];
    var syncedAny = false;

    for (final op in pendingOps) {
      final type = op['type']?.toString();
      try {
        if (type == 'create_group_activity') {
          final response = await http
              .post(
                Uri.parse('$baseUrl/activities/groups/${op['group_id']}'),
                headers: _headers,
                body: jsonEncode({
                  'name': op['name'],
                  if (op['description'] != null)
                    'description': op['description'],
                  if (op['deadline'] != null) 'deadline': op['deadline'],
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 201) {
            final serverId = jsonDecode(response.body)['activity_id'] as int;
            final tempId = op['temp_id'] as int?;
            if (tempId != null) idMapping[tempId] = serverId;
            syncedAny = true;
            continue;
          }
          if (response.statusCode == 409 || response.statusCode == 404) {
            syncedAny = true;
            continue;
          }
          remaining.add(op);
          continue;
        }

        if (type == 'create_individual_activity') {
          final response = await http
              .post(
                Uri.parse('$baseUrl/activities/individual'),
                headers: _headers,
                body: jsonEncode({
                  'name': op['name'],
                  if (op['description'] != null)
                    'description': op['description'],
                  if (op['deadline'] != null) 'deadline': op['deadline'],
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 201) {
            final serverId = jsonDecode(response.body)['activity_id'] as int;
            final tempId = op['temp_id'] as int?;
            if (tempId != null) idMapping[tempId] = serverId;
            syncedAny = true;
            continue;
          }
          if (response.statusCode == 409 || response.statusCode == 404) {
            syncedAny = true;
            continue;
          }
          remaining.add(op);
          continue;
        }

        if (type == 'update_activity_status') {
          final rawId = op['activity_id'] as int;
          final resolvedId = idMapping[rawId] ?? rawId;
          if (resolvedId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .put(
                Uri.parse('$baseUrl/activities/$resolvedId'),
                headers: _headers,
                body: jsonEncode({'status': op['status']}),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            syncedAny = true;
            continue;
          }
          if (response.statusCode == 404) {
            syncedAny = true;
            continue;
          }
          remaining.add(op);
          continue;
        }

        if (type == 'delete_activity') {
          final rawId = op['activity_id'] as int;
          final resolvedId = idMapping[rawId] ?? rawId;
          if (resolvedId < 0) {
            syncedAny = true;
            continue;
          }
          final response = await http
              .delete(
                Uri.parse('$baseUrl/activities/$resolvedId'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            syncedAny = true;
            continue;
          }
          remaining.add(op);
          continue;
        }

        remaining.add(op);
      } catch (e) {
        if (_isConnectivityError(e)) {
          remaining.add(op);
          remaining.addAll(
            pendingOps
                .skipWhile((existing) => !identical(existing, op))
                .skip(1),
          );
          break;
        }
        remaining.add(op);
      }
    }

    await _savePendingActivityOps(remaining);

    final cached = await _loadCachedActivities();
    final rebuilt = cached.map((a) {
      final mapped = idMapping[a.idActivity];
      if (mapped != null) {
        return a.copyWith(
          idActivity: mapped,
          isLocalOnly: false,
          hasPendingSync: false,
        );
      }
      return a;
    }).toList();
    await _saveCachedActivities(rebuilt);

    if (syncedAny) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/activities/me'),
          headers: _headers,
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final activities = (data['activities'] as List)
              .map((a) => Activity.fromJson(a))
              .toList();
          await _saveCachedActivities(activities);
        }
      } catch (_) {}
    }

    return syncedAny;
  }

  Future<void> _syncPendingProfileOperations() async {
    final ops = await _loadPendingProfileOps();
    if (ops.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final op in ops) {
      try {
        final type = op['type']?.toString();
        if (type == 'upload_profile_picture') {
          final path = op['path']?.toString();
          if (path == null || path.isEmpty || !File(path).existsSync()) {
            continue;
          }
          final request = http.MultipartRequest(
            'PUT',
            Uri.parse('$baseUrl/users/me/profile-picture'),
          );
          if (_token != null) {
            request.headers['Authorization'] = 'Bearer $_token';
          }
          request.files.add(await http.MultipartFile.fromPath('image', path));
          final streamedResponse = await request.send().timeout(
            const Duration(seconds: 10),
          );
          final response = await http.Response.fromStream(streamedResponse);
          if (response.statusCode == 200) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'delete_profile_picture') {
          final response = await http
              .delete(
                Uri.parse('$baseUrl/users/me/profile-picture'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        remaining.add(op);
      } catch (e) {
        if (_isConnectivityError(e)) {
          remaining.add(op);
          remaining.addAll(
            ops.skipWhile((existing) => !identical(existing, op)).skip(1),
          );
          break;
        }
        remaining.add(op);
      }
    }
    await _savePendingProfileOps(remaining);
  }

  Future<void> _syncPendingGroupOperations() async {
    final ops = await _loadPendingGroupOps();
    if (ops.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    final idMapping = await _loadGroupIdMapping();
    final roleIdMapping = <int, int>{};
    for (final op in ops) {
      try {
        final type = op['type']?.toString();
        if (type == 'create_group') {
          final response = await http
              .post(
                Uri.parse('$baseUrl/groups/'),
                headers: _headers,
                body: jsonEncode({
                  'name': op['name'],
                  'capacity': op['capacity'] ?? 10,
                  'generate_qr': op['generate_qr'] == true,
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 201) {
            final parsedBody = Map<String, dynamic>.from(
              jsonDecode(response.body),
            );
            int? serverId;
            final directGroupId = parsedBody['group_id'];
            final directIdGroup = parsedBody['id_group'];
            if (directGroupId is int) {
              serverId = directGroupId;
            } else if (directIdGroup is int) {
              serverId = directIdGroup;
            } else {
              final groupObj = parsedBody['group'];
              if (groupObj is Map<String, dynamic>) {
                final nestedGroupId = groupObj['group_id'];
                final nestedIdGroup = groupObj['id_group'];
                if (nestedGroupId is int) {
                  serverId = nestedGroupId;
                } else if (nestedIdGroup is int) {
                  serverId = nestedIdGroup;
                }
              }
            }
            final tempId = op['temp_id'] as int?;
            if (serverId != null && tempId != null && serverId > 0) {
              idMapping[tempId] = serverId;
              continue;
            }
            remaining.add(op);
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'join_group_by_invite') {
          final response = await http
              .post(
                Uri.parse('$baseUrl/groups/join'),
                headers: _headers,
                body: jsonEncode({'invite_code': op['invite_code']}),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 409) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'update_group') {
          final rawId = op['group_id'] as int;
          final groupId = idMapping[rawId] ?? rawId;
          if (groupId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .put(
                Uri.parse('$baseUrl/groups/$groupId'),
                headers: _headers,
                body: jsonEncode({
                  if (op['name'] != null) 'name': op['name'],
                  if (op['capacity'] != null) 'capacity': op['capacity'],
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'delete_group') {
          final rawId = op['group_id'] as int;
          final groupId = idMapping[rawId] ?? rawId;
          if (groupId < 0) {
            continue;
          }
          final response = await http
              .delete(Uri.parse('$baseUrl/groups/$groupId'), headers: _headers)
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'add_group_member') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          if (groupId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .post(
                Uri.parse('$baseUrl/groups/$groupId/members'),
                headers: _headers,
                body: jsonEncode({'username': op['username']}),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 409) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'remove_group_member') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          if (groupId < 0) {
            continue;
          }
          final response = await http
              .delete(
                Uri.parse('$baseUrl/groups/$groupId/members/${op['user_id']}'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'create_group_role') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          if (groupId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .post(
                Uri.parse('$baseUrl/roles/groups/$groupId'),
                headers: _headers,
                body: jsonEncode({
                  'name': op['name'],
                  if (op['color'] != null) 'color': op['color'],
                  'permissions': op['permissions'] ?? [],
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 201 || response.statusCode == 409) {
            if (response.statusCode == 201) {
              final body = Map<String, dynamic>.from(jsonDecode(response.body));
              final newRoleId = body['role_id'] as int?;
              final tempRoleId = op['temp_role_id'] as int?;
              if (newRoleId != null && tempRoleId != null) {
                roleIdMapping[tempRoleId] = newRoleId;
              }
            }
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'update_group_role') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          final rawRoleId = op['role_id'] as int;
          final roleId = roleIdMapping[rawRoleId] ?? rawRoleId;
          if (groupId < 0) {
            remaining.add(op);
            continue;
          }
          if (roleId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .put(
                Uri.parse('$baseUrl/roles/groups/$groupId/$roleId'),
                headers: _headers,
                body: jsonEncode({
                  if (op['name'] != null) 'name': op['name'],
                  if (op['color'] != null) 'color': op['color'],
                  if (op['permissions'] != null)
                    'permissions': op['permissions'],
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'delete_group_role') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          final rawRoleId = op['role_id'] as int;
          final roleId = roleIdMapping[rawRoleId] ?? rawRoleId;
          if (groupId < 0) {
            continue;
          }
          if (roleId < 0) {
            continue;
          }
          final response = await http
              .delete(
                Uri.parse('$baseUrl/roles/groups/$groupId/roles/$roleId'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'assign_user_role') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          final rawRoleId = op['role_id'] as int;
          final roleId = roleIdMapping[rawRoleId] ?? rawRoleId;
          if (groupId < 0) {
            remaining.add(op);
            continue;
          }
          if (roleId < 0) {
            remaining.add(op);
            continue;
          }
          final response = await http
              .post(
                Uri.parse('$baseUrl/roles/groups/$groupId/assign'),
                headers: _headers,
                body: jsonEncode({
                  'username': op['username'],
                  'role_id': roleId,
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 409) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'remove_user_role') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          final rawRoleId = op['role_id'] as int;
          final roleId = roleIdMapping[rawRoleId] ?? rawRoleId;
          if (groupId < 0) {
            continue;
          }
          if (roleId < 0) {
            continue;
          }
          final response = await http
              .delete(
                Uri.parse(
                  '$baseUrl/roles/groups/$groupId/users/${op['user_id']}/roles/$roleId',
                ),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'upload_group_icon') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          final path = op['path']?.toString();
          if (groupId < 0 ||
              path == null ||
              path.isEmpty ||
              !File(path).existsSync()) {
            remaining.add(op);
            continue;
          }
          final request = http.MultipartRequest(
            'PUT',
            Uri.parse('$baseUrl/groups/$groupId/icon'),
          );
          if (_token != null) {
            request.headers['Authorization'] = 'Bearer $_token';
          }
          request.files.add(await http.MultipartFile.fromPath('image', path));
          final streamedResponse = await request.send().timeout(
            const Duration(seconds: 10),
          );
          final response = await http.Response.fromStream(streamedResponse);
          if (response.statusCode == 200) {
            await _saveGroupIconBytes(groupId, await File(path).readAsBytes());
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'delete_group_icon') {
          final groupId =
              (idMapping[op['group_id'] as int] ?? op['group_id']) as int;
          if (groupId < 0) {
            continue;
          }
          final response = await http
              .delete(
                Uri.parse('$baseUrl/groups/$groupId/icon'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            await _removeGroupIconBytes(groupId);
            continue;
          }
          remaining.add(op);
          continue;
        }
        remaining.add(op);
      } catch (e) {
        if (_isConnectivityError(e)) {
          remaining.add(op);
          remaining.addAll(
            ops.skipWhile((existing) => !identical(existing, op)).skip(1),
          );
          break;
        }
        remaining.add(op);
      }
    }
    await _savePendingGroupOps(remaining);
    if (roleIdMapping.isNotEmpty) {
      final groups = await _loadCachedGroups();
      for (final group in groups) {
        final roles = await _loadCachedGroupRoles(group.idGroup);
        if (roles.isEmpty) continue;
        final remapped = roles.map((role) {
          final mapped = roleIdMapping[role['id_role']];
          if (mapped != null) {
            return {...role, 'id_role': mapped};
          }
          return role;
        }).toList();
        await _saveCachedGroupRoles(group.idGroup, remapped);
      }
    }
    if (idMapping.isNotEmpty) {
      final existingMapping = await _loadGroupIdMapping();
      await _saveGroupIdMapping({...existingMapping, ...idMapping});
      final groups = await _loadCachedGroups();
      final migrated = groups.map((g) {
        final mapped = idMapping[g.idGroup];
        if (mapped != null) {
          return g.copyWith(
            idGroup: mapped,
            isLocalOnly: false,
            hasPendingSync: false,
          );
        }
        return g;
      }).toList();
      await _saveCachedGroups(migrated);
      await _migrateGroupScopedCaches(idMapping);
    }
  }

  Future<void> _syncPendingNotificationOperations() async {
    final ops = await _loadPendingNotificationOps();
    if (ops.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final op in ops) {
      try {
        final type = op['type']?.toString();
        if (type == 'delete_notification') {
          final notificationId = op['notification_id'] as int?;
          if (notificationId == null) continue;
          final response = await http
              .delete(
                Uri.parse('$baseUrl/notifications/$notificationId'),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        if (type == 'respond_membership_notification') {
          final notificationId = op['notification_id'] as int?;
          final decision = op['decision']?.toString();
          if (notificationId == null ||
              decision == null ||
              (decision != 'accept' && decision != 'reject')) {
            continue;
          }
          final response = await http
              .post(
                Uri.parse('$baseUrl/notifications/$notificationId/respond'),
                headers: _headers,
                body: jsonEncode({'decision': decision}),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 || response.statusCode == 404) {
            continue;
          }
          remaining.add(op);
          continue;
        }
        remaining.add(op);
      } catch (e) {
        if (_isConnectivityError(e)) {
          remaining.add(op);
          remaining.addAll(
            ops.skipWhile((existing) => !identical(existing, op)).skip(1),
          );
          break;
        }
        remaining.add(op);
      }
    }
    await _savePendingNotificationOps(remaining);
  }

  Future<int> getPendingActivityOperationsCount() async {
    final ops = await _loadPendingActivityOps();
    return ops.length;
  }

  Future<int> getPendingOfflineChangesCount() async {
    final activityOps = await _loadPendingActivityOps();
    final groupOps = await _loadPendingGroupOps();
    final profileOps = await _loadPendingProfileOps();
    final chatOps = await _loadPendingChatOps();
    final notificationOps = await _loadPendingNotificationOps();
    return activityOps.length +
        groupOps.length +
        profileOps.length +
        chatOps.length +
        notificationOps.length;
  }

  Future<Map<String, dynamic>> createGroup(
    String name, {
    int capacity = 10,
    bool generateQr = false,
    int? creatorUserId,
    String? creatorUsername,
    String? creatorName,
    String? creatorSurname,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/groups/'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'capacity': capacity,
              'generate_qr': generateQr,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 201) {
        final parsed = Map<String, dynamic>.from(jsonDecode(response.body));
        await syncPendingActivityOperations();
        return parsed;
      }
      throw _buildApiException(response, 'Nepodarilo sa vytvoriť skupinu');
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      final tempId = await _nextTempGroupId();
      await _upsertCachedGroup(
        Group(
          idGroup: tempId,
          name: name,
          capacity: capacity,
          hasPendingSync: true,
          isLocalOnly: true,
        ),
      );
      await _queueGroupOperation({
        'type': 'create_group',
        'temp_id': tempId,
        'name': name,
        'capacity': capacity,
        'generate_qr': generateQr,
      });
      await _seedDefaultOfflineGroupRoles(tempId);
      if (creatorUsername != null && creatorUsername.trim().isNotEmpty) {
        await _saveCachedGroupMembers(tempId, [
          {
            'id_registration': creatorUserId ?? -1,
            'username': creatorUsername.trim(),
            if (creatorName != null) 'name': creatorName,
            if (creatorSurname != null) 'surname': creatorSurname,
          },
        ]);
      }
      return {'group_id': tempId, 'queued': true, 'offline': true};
    }
  }

  Future<bool> joinGroupByInviteCode(String inviteCode) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/groups/join'),
            headers: _headers,
            body: jsonEncode({'invite_code': inviteCode}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa pripojiť do skupiny');
      }
      return false;
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueGroupOperation({
        'type': 'join_group_by_invite',
        'invite_code': inviteCode,
      });
      return true;
    }
  }

  Future<String?> getGroupInviteCode(int groupId) async {
    final resolvedGroupId = await _resolveServerGroupId(groupId);
    final response = await http.get(
      Uri.parse('$baseUrl/groups/$resolvedGroupId/invite'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      return data['qr_code']?.toString();
    }
    if (response.statusCode == 404) {
      throw Exception('Invite API is not available. Restart backend server.');
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať invite kód');
  }

  Future<String> enableGroupInviteCode(int groupId) async {
    final resolvedGroupId = await _resolveServerGroupId(groupId);
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$resolvedGroupId/invite'),
      headers: _headers,
      body: jsonEncode({}),
    );
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final code = data['qr_code']?.toString();
      if (code == null || code.isEmpty) {
        throw Exception('Invite code was not returned by server');
      }
      return code;
    }
    if (response.statusCode == 404) {
      throw Exception('Invite API is not available. Restart backend server.');
    }
    throw _buildApiException(response, 'Nepodarilo sa zapnúť invite kód');
  }

  Future<void> disableGroupInviteCode(int groupId) async {
    final resolvedGroupId = await _resolveServerGroupId(groupId);
    final response = await http.delete(
      Uri.parse('$baseUrl/groups/$resolvedGroupId/invite'),
      headers: _headers,
    );
    if (response.statusCode == 404) {
      throw Exception('Invite API is not available. Restart backend server.');
    }
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa vypnúť invite kód');
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/notifications'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};
        final raw = data['notifications'];
        final list = raw is List ? raw : <dynamic>[];
        final notifications = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            notifications.add(item);
          } else if (item is Map) {
            notifications.add(Map<String, dynamic>.from(item));
          }
        }
        await _saveCachedNotifications(notifications);
        return notifications;
      }
      throw _buildApiException(
        response,
        'Nepodarilo sa načítať notifikácie',
      );
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      return _loadCachedNotifications();
    }
  }

  Future<void> deleteNotification(int notificationId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/notifications/$notificationId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(response, 'Nepodarilo sa zmazať notifikáciu');
      }
      await _removeCachedNotification(notificationId);
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueNotificationOperation({
        'type': 'delete_notification',
        'notification_id': notificationId,
      });
      await _removeCachedNotification(notificationId);
    }
  }

  Future<void> respondToMembershipNotification({
    required int notificationId,
    required bool accept,
  }) async {
    final decision = accept ? 'accept' : 'reject';
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/notifications/$notificationId/respond'),
            headers: _headers,
            body: jsonEncode({'decision': decision}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw _buildApiException(
          response,
          'Nepodarilo sa spracovať požiadavku notifikácie',
        );
      }
      await _updateCachedMembershipNotificationStatus(
        notificationId: notificationId,
        accept: accept,
      );
    } catch (e) {
      if (!_isConnectivityError(e)) rethrow;
      await _queueNotificationOperation({
        'type': 'respond_membership_notification',
        'notification_id': notificationId,
        'decision': decision,
      });
      await _updateCachedMembershipNotificationStatus(
        notificationId: notificationId,
        accept: accept,
      );
    }
  }

  Future<void> registerPushToken({
    required String token,
    String platform = 'flutter',
  }) async {
    if (token.trim().isEmpty) return;
    final response = await http
        .post(
          Uri.parse('$baseUrl/notifications/push-token'),
          headers: _headers,
          body: jsonEncode({'token': token.trim(), 'platform': platform}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw _buildApiException(
        response,
        'Nepodarilo sa zaregistrovat push token',
      );
    }
  }

  Future<void> unregisterPushToken({String? token}) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/notifications/push-token'),
          headers: _headers,
          body: token == null || token.trim().isEmpty
              ? null
              : jsonEncode({'token': token.trim()}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa odhlasit push token');
    }
  }
}
