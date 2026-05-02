import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/teammeeter_analytics.dart';
import '../utils/snackbar_utils.dart';
import '../models/activity.dart';
import '../models/group.dart';
import 'activity_detail_dialog.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'group_detail_screen.dart';
import 'notifications_screen.dart';
import 'user_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentNavIndex = 1; // Home is center/default
  final GlobalKey<ConversationsScreenState> _conversationsScreenKey =
      GlobalKey<ConversationsScreenState>();
  List<Activity> _activities = [];
  List<Group> _groups = [];
  bool _isLoading = true;
  bool _isGroupsLoading = false;
  bool _isUpdatingActivityStatus = false;
  bool _isCreatingGroup = false;
  bool _showOfflineBanner = false;
  bool _hasPendingSync = false;
  bool _hasAnyNotifications = false;
  int _activitiesLoadRequestId = 0;
  int _groupsLoadRequestId = 0;
  Timer? _offlineSyncTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;

  bool _isExpiredActivity(Activity activity) {
    final deadline = activity.parsedDeadline;
    if (deadline == null) return false;
    return !deadline.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _initPushNotifications();
    _refreshOfflineBannerState();
    _offlineSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _runOfflineSyncInBackground();
      await _refreshOfflineBannerState();
      await _refreshNotificationIndicator();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.ensureCurrentUserLoaded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineSyncTimer?.cancel();
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runOfflineSyncInBackground();
      _refreshNotificationIndicator();
      _syncPushTokenSilently();
    }
  }

  Future<void> _initPushNotifications() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      await PushNotificationService.instance.syncPushTokenWithBackend(api);
      _notificationTapSubscription?.cancel();
      _notificationTapSubscription = PushNotificationService
          .instance
          .onNotificationTap
          .listen(_handlePushTapData);
      final initialData = PushNotificationService.instance.takeInitialTapData();
      if (initialData != null) {
        _handlePushTapData(initialData);
      }
    } catch (_) {
      // App remains functional even without push setup.
    }
  }

  Future<void> _syncPushTokenSilently() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await PushNotificationService.instance.syncPushTokenWithBackend(
        authProvider.apiService,
      );
    } catch (_) {}
  }

  Future<void> _handlePushTapData(Map<String, dynamic> data) async {
    if (!mounted) return;

    final rawType = data['notification_type']?.toString();
    final type = int.tryParse(rawType ?? '');
    final conversationIdRaw = data['conversation_id']?.toString();
    final conversationId = int.tryParse(conversationIdRaw ?? '');
    final activityIdRaw = data['activity_id']?.toString();
    final activityId = int.tryParse(activityIdRaw ?? '');

    if (conversationId != null && conversationId > 0) {
      unawaited(
        TeamMeeterAnalytics.instance.logPushNotificationOpen(
          notificationType: 'chat',
          conversationId: conversationId,
        ),
      );
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      String title = 'Conversation #$conversationId';
      final titleFromPush = data['conversation_name']?.toString().trim();
      if (titleFromPush != null && titleFromPush.isNotEmpty) {
        title = titleFromPush;
      }
      try {
        final conversation = await api.getConversation(conversationId);
        final resolvedTitle = conversation['name']?.toString().trim();
        if (resolvedTitle != null && resolvedTitle.isNotEmpty) {
          title = resolvedTitle;
        }
      } catch (_) {}

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversationId: conversationId, title: title),
        ),
      );
      if (!mounted) return;
      unawaited(
        _conversationsScreenKey.currentState?.reloadConversations() ??
            Future.value(),
      );
      await _refreshNotificationIndicator();
      return;
    }

    if (type == 1) {
      unawaited(
        TeamMeeterAnalytics.instance.logPushNotificationOpen(
          notificationType: 'message_generic',
        ),
      );
      // For message notifications, fallback to notifications list when payload
      // misses conversation id (older push payloads).
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      if (!mounted) return;
      await _refreshNotificationIndicator();
      return;
    }

    if ((type == 2 || type == 5) && activityId != null && activityId > 0) {
      unawaited(
        TeamMeeterAnalytics.instance.logPushNotificationOpen(
          notificationType: type == 2 ? 'activity_new' : 'activity_completed',
          activityId: activityId,
        ),
      );
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      try {
        final activity = await api.getActivityDetails(activityId);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) =>
              ActivityDetailDialog(activity: activity, onDeleted: _loadData),
        );
        if (!mounted) return;
        await _loadData();
        return;
      } catch (_) {
        // If detail cannot be fetched, fallback to notifications list below.
      }
    }

    unawaited(
      TeamMeeterAnalytics.instance.logPushNotificationOpen(
        notificationType: 'notifications_fallback',
      ),
    );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    if (!mounted) return;
    await _refreshNotificationIndicator();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadActivities(showError: false),
        _loadGroups(showError: false, preservePreviousOnEmpty: true),
        _refreshNotificationIndicator(),
      ]);
      await _refreshOfflineBannerState();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshNotificationIndicator() async {
    try {
      if (!mounted) return;
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final hasUnread = await api.hasUnreadNotifications();
      if (!mounted) return;
      setState(() => _hasAnyNotifications = hasUnread);
    } catch (_) {
      // Keep previous indicator state if refresh fails.
    }
  }

  Future<void> _refreshOfflineBannerState() async {
    if (!mounted) return;
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final pending = await api.getPendingOfflineChangesCount();
    final reachable = await api.isServerReachable();
    if (!mounted) return;
    setState(() {
      _hasPendingSync = pending > 0;
      _showOfflineBanner = !reachable;
    });
  }

  Future<void> _runOfflineSyncInBackground() async {
    try {
      if (!mounted) return;
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final pendingBefore = await api.getPendingOfflineChangesCount();
      await api.syncPendingActivityOperations();
      final pendingAfter = await api.getPendingOfflineChangesCount();
      final reachable = await api.isServerReachable();
      final syncedSomething = pendingAfter < pendingBefore;
      // Keep My Tasks continuously fresh in background (server when online,
      // cache when offline) without blocking UI.
      await _loadActivities(showError: false);
      if (reachable && syncedSomething && mounted) {
        await _loadGroups(
          showError: false,
          silent: true,
          preservePreviousOnEmpty: true,
        );
      }
      await _refreshOfflineBannerState();
    } catch (_) {}
  }

  Future<void> _loadActivities({bool showError = true}) async {
    final requestId = ++_activitiesLoadRequestId;
    try {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      final activities = await api.getMyActivities();
      if (!mounted || requestId != _activitiesLoadRequestId) return;
      setState(() => _activities = activities);
    } catch (e) {
      if (!mounted || requestId != _activitiesLoadRequestId || !showError) {
        return;
      }
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  Future<void> _loadGroups({
    bool showError = true,
    bool silent = false,
    bool preservePreviousOnEmpty = true,
  }) async {
    final requestId = ++_groupsLoadRequestId;
    if (!silent && mounted) setState(() => _isGroupsLoading = true);
    try {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      final groups = await api.getGroups();
      if (!mounted) return;
      if (requestId != _groupsLoadRequestId) {
        // Novší _loadGroups už dobehol skôr; ak zobrazil prázdny zoznam a my máme dáta, oprav to.
        if (groups.isNotEmpty && _groups.isEmpty) {
          setState(() => _groups = groups);
          await _refreshOfflineBannerState();
        }
        return;
      }
      if (preservePreviousOnEmpty && groups.isEmpty && _groups.isNotEmpty) {
        return;
      }
      setState(() => _groups = groups);
      await _refreshOfflineBannerState();
    } catch (e) {
      if (!mounted || requestId != _groupsLoadRequestId || !showError) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (!silent && mounted && requestId == _groupsLoadRequestId) {
        setState(() => _isGroupsLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? const [
                    Color(0xFF8B1A2C),
                    Color(0xFF3D0C0C),
                    Color(0xFF1A0A0A),
                    Color(0xFF0D0D0D),
                  ]
                : const [
                    Color(0xFF8B1A2C),
                    Color(0xFFE8DFDF),
                    Color(0xFFE3DDDD),
                    Color(0xFFD8D2D2),
                  ],
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              if (_showOfflineBanner) _buildOfflineSyncBanner(),
              Expanded(
                child: IndexedStack(
                  index: _currentNavIndex,
                  children: [
                    _buildCalendarView(),
                    _buildTasksView(),
                    _buildChatView(),
                    _buildGroupsView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildOfflineSyncBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF6C00).withAlpha(220),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _hasPendingSync
            ? 'Offline režim: čaká sa na synchronizáciu'
            : 'Offline režim',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Top App Bar ──────────────────────────────────────────
  Widget _buildTopBar() {
    final user = Provider.of<AuthProvider>(context).user;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Notification bell
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              if (!mounted) return;
              await _refreshNotificationIndicator();
            },
            icon: Stack(
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: Colors.white,
                  size: 28,
                ),
                if (_hasAnyNotifications)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE57373),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              _currentNavIndex == 3
                  ? 'My groups'
                  : _currentNavIndex == 2
                  ? 'Chat'
                  : _currentNavIndex == 0
                  ? 'Calendar'
                  : 'My tasks',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: themeProvider.toggleTheme,
            tooltip: isDarkMode
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          // Profile avatar
          GestureDetector(
            onTap: _showProfileMenu,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 2),
                color: const Color(0xFF2D1515),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildUserAvatarContent(
                userSize: 14,
                fallbackText: user?.initials ?? 'U',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks / Activities View ──────────────────────────────
  Widget _buildTasksView() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final visibleActivities = _activities
        .where((a) => !_isExpiredActivity(a))
        .toList();

    final todoActivities = visibleActivities
        .where((a) => a.status == 'todo')
        .toList();
    final inProgressActivities = visibleActivities
        .where((a) => a.status == 'in_progress')
        .toList();
    final completedActivities = visibleActivities
        .where((a) => a.status == 'completed')
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildTaskColumn(
                    title: 'To-do',
                    columnStatus: 'todo',
                    activities: todoActivities,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTaskColumn(
                    title: 'In progress',
                    columnStatus: 'in_progress',
                    activities: inProgressActivities,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: completedActivities.isEmpty
                  ? null
                  : () => _showCompletedTasksDialog(completedActivities),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D1515),
                foregroundColor: Colors.white70,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withAlpha(26)),
                ),
              ),
              child: const Text(
                'View completed tasks',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskColumn({
    required String title,
    required String columnStatus,
    required List<Activity> activities,
  }) {
    return DragTarget<Activity>(
      onWillAccept: (data) {
        if (data == null) return false;
        return data.status != columnStatus;
      },
      onAccept: (activity) async {
        if (_isUpdatingActivityStatus) return;
        await _setActivityStatus(activity.idActivity, columnStatus);
      },
      builder: (context, candidateData, rejectedData) {
        final isActiveDrop = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A0A0A).withAlpha(204),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActiveDrop
                  ? const Color(0xFFE57373).withAlpha(120)
                  : Colors.white.withAlpha(13),
              width: isActiveDrop ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              // Column header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D1515),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border.all(color: Colors.white.withAlpha(13)),
                ),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Task items
              Padding(
                padding: const EdgeInsets.all(8),
                child: activities.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          title == 'To-do'
                              ? 'No tasks yet'
                              : 'No tasks in progress',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: activities
                            .map((a) => _buildTaskItem(a))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskItem(Activity activity) {
    return LongPressDraggable<Activity>(
      data: activity,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 160,
          child: Opacity(
            opacity: 0.95,
            child: _buildTaskCard(activity, isDragging: true),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildTaskCard(activity)),
      child: GestureDetector(
        onTap: () => _showActivityDetail(activity),
        child: _buildTaskCard(activity),
      ),
    );
  }

  Widget _buildTaskCard(Activity activity, {bool isDragging = false}) {
    return Container(
      width: isDragging ? null : double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0F0),
        borderRadius: BorderRadius.circular(20),
        border: isDragging
            ? Border.all(color: const Color(0xFF8B1A2C), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDragging ? 80 : 38),
            blurRadius: isDragging ? 10 : 4,
            offset: Offset(0, isDragging ? 4 : 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activity.name,
            style: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (activity.deadline != null) ...[
            const SizedBox(height: 2),
            Text(
              activity.formattedDeadline,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  void _showActivityDetail(Activity activity) {
    showDialog(
      context: context,
      builder: (context) =>
          ActivityDetailDialog(activity: activity, onDeleted: _loadData),
    );
  }

  Future<void> _setActivityStatus(int activityId, String newStatus) async {
    setState(() => _isUpdatingActivityStatus = true);
    final previousActivities = List<Activity>.from(_activities);
    setState(() {
      _activities = _activities.map((activity) {
        if (activity.idActivity != activityId) return activity;
        return activity.copyWith(status: newStatus, hasPendingSync: true);
      }).toList();
    });
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.updateActivityStatus(activityId, newStatus);
    } catch (e) {
      if (!mounted) return;
      setState(() => _activities = previousActivities);
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingActivityStatus = false);
    }
  }

  void _showCompletedTasksDialog(List<Activity> completedActivities) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.dialogBackground(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: double.infinity,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Completed tasks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: completedActivities.isEmpty
                        ? const Center(
                            child: Text(
                              'No completed tasks',
                              style: TextStyle(color: Colors.white60),
                            ),
                          )
                        : ListView.builder(
                            itemCount: completedActivities.length,
                            itemBuilder: (context, index) {
                              final activity = completedActivities[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _showActivityDetail(activity);
                                },
                                child: _buildTaskCard(activity),
                              );
                            },
                          ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withAlpha(60)),
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Groups View ──────────────────────────────────────────
  Widget _buildCalendarView() {
    return CalendarScreen(groups: _groups, onDataChanged: _loadData);
  }

  Widget _buildChatView() {
    return ConversationsScreen(key: _conversationsScreenKey);
  }

  Widget _buildGroupsView() {
    final showBlockingLoader =
        (_isLoading || _isGroupsLoading) && _groups.isEmpty;

    if (showBlockingLoader) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      children: [
        if (_isGroupsLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: Color(0xFF8B1A2C),
              backgroundColor: Colors.white24,
            ),
          ),
        RefreshIndicator(
          onRefresh: () => _loadGroups(
            showError: false,
            preservePreviousOnEmpty: false,
          ),
          color: const Color(0xFF8B1A2C),
          child: _groups.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 120),
                    Icon(
                      Icons.group_outlined,
                      size: 64,
                      color: Colors.white.withAlpha(77),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No groups yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return _buildGroupCard(group);
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A0A).withAlpha(210),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildGroupActionButton(
                  label: 'Join',
                  icon: Icons.group_add_outlined,
                  onPressed: _showJoinGroupDialog,
                  isPrimary: false,
                ),
                const SizedBox(height: 8),
                _buildGroupActionButton(
                  label: 'Create',
                  icon: Icons.add,
                  onPressed: _showCreateGroupDialog,
                  isPrimary: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      width: 170,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: isPrimary
              ? const Color(0xFF8B1A2C)
              : const Color(0xFF2A1111),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withAlpha(isPrimary ? 0 : 38)),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildGroupCard(Group group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A).withAlpha(204),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: ListTile(
        onTap: () async {
          final didMutateGroups = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
          );
          if (mounted) {
            _loadGroups(
              showError: false,
              preservePreviousOnEmpty: didMutateGroups != true,
            );
            _loadActivities(showError: false);
            _refreshNotificationIndicator();
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _GroupListAvatar(
          groupId: group.idGroup,
          hasIcon: group.hasIcon,
          fallbackLetter: group.name.isNotEmpty
              ? group.name[0].toUpperCase()
              : '?',
        ),
        title: Text(
          group.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          group.createDate ?? '',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      ),
    );
  }

  Widget _GroupListAvatar({
    required int groupId,
    required bool hasIcon,
    required String fallbackLetter,
  }) {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final imageUrl = '${ApiService.baseUrl}/groups/$groupId/icon';
    final canLoadNetworkIcon = groupId > 0 && hasIcon && token != null;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF2D1515),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder(
        future: api.getCachedGroupIconBytes(groupId),
        builder: (context, snapshot) {
          final cachedBytes = snapshot.data;
          if (cachedBytes != null && cachedBytes.isNotEmpty) {
            return Image.memory(cachedBytes, fit: BoxFit.cover);
          }
          if (canLoadNetworkIcon) {
            return Image.network(
              imageUrl,
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer $token'},
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: Text(
                    fallbackLetter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  fallbackLetter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }
          return Center(
            child: Text(
              fallbackLetter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserAvatarContent({
    required double userSize,
    required String fallbackText,
  }) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final token = authProvider.token;
    final localPath = authProvider.localProfilePhotoPath;
    final hasLocalImage = localPath != null && File(localPath).existsSync();
    final hasPicture =
        !authProvider.localProfilePhotoRemoved &&
        (user?.hasProfilePicture ?? false);
    if (hasLocalImage) {
      return Image.file(File(localPath), fit: BoxFit.cover);
    }
    if (hasPicture && token != null) {
      return Image.network(
        '${ApiService.baseUrl}/users/me/profile-picture',
        fit: BoxFit.cover,
        headers: {'Authorization': 'Bearer $token'},
        errorBuilder: (context, error, stackTrace) => Center(
          child: Text(
            fallbackText,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: userSize,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Text(
        fallbackText,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: userSize,
        ),
      ),
    );
  }

  // ── Profile Bottom Sheet ─────────────────────────────────
  void _showProfileMenu() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dialogBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8B1A2C), width: 2),
                color: const Color(0xFF2D1515),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildUserAvatarContent(
                userSize: 24,
                fallbackText: authProvider.user?.initials ?? 'U',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              authProvider.user?.displayName ??
                  (authProvider.token != null ? 'Loading profile...' : 'User'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (authProvider.user != null &&
                authProvider.user!.username.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '@${authProvider.user!.username}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if ((authProvider.user?.email ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                authProvider.user!.email!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Navigator.of(this.context).push(
                    MaterialPageRoute(
                      builder: (_) => const UserSettingsScreen(),
                    ),
                  );
                  if (!mounted) return;
                  await Provider.of<AuthProvider>(
                    this.context,
                    listen: false,
                  ).refreshCurrentUser();
                },
                icon: const Icon(Icons.tune),
                label: const Text('Upraviť vzhľad profilu'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withAlpha(70)),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  authProvider.logout();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Odhlásiť sa'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B1A2C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Create Group Dialog ──────────────────────────────────
  void _showJoinGroupDialog() {
    final codeController = TextEditingController();
    var inviteCodeAssistedByQr = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Join Group',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              onChanged: (_) =>
                  setDialogState(() => inviteCodeAssistedByQr = false),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Invite code',
                hintStyle: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white38
                      : Colors.black45,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withAlpha(51)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B1A2C)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final scannedCode = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
                );
                if (!context.mounted ||
                    scannedCode == null ||
                    scannedCode.isEmpty) {
                  return;
                }
                setDialogState(() {
                  inviteCodeAssistedByQr = true;
                  codeController.text = scannedCode;
                });
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(color: Colors.white.withAlpha(70)),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black54,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final inviteCode = codeController.text.trim();
              await _joinGroupByInviteCode(
                inviteCode,
                dialogContext: context,
                entryMethod:
                    inviteCodeAssistedByQr ? 'qr_assisted' : 'typed_submit',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Join'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _joinGroupByInviteCode(
    String inviteCode, {
    BuildContext? dialogContext,
    String entryMethod = 'typed_submit',
  }) async {
    final code = inviteCode.trim();
    if (code.isEmpty) {
      this.context.showLatestSnackBar(
        const SnackBar(
          content: Text('Please enter an invite code'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final queued = await api.joinGroupByInviteCode(code);
      unawaited(
        TeamMeeterAnalytics.instance.logGroupJoin(
          queuedOffline: queued,
          entryMethod: entryMethod,
        ),
      );
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      await _loadGroups();
      if (!mounted) return;
      this.context.showLatestSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Požiadavka na pripojenie je uložená offline a odošle sa po pripojení.'
                : 'Joined group successfully',
          ),
          backgroundColor: queued
              ? const Color(0xFFEF6C00)
              : const Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      this.context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  void _showCreateGroupDialog() {
    final parentContext = this.context;
    final nameController = TextEditingController();
    final capacityController = TextEditingController(text: '10');
    bool generateQr = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.dialogBackground(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Create Group',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Group name',
                  hintText: 'Enter group name',
                  labelStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                  hintStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white38
                        : Colors.black45,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withAlpha(51)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8B1A2C)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capacityController,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Group capacity',
                  hintText: 'Max number of members',
                  labelStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                  hintStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white38
                        : Colors.black45,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withAlpha(51)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8B1A2C)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: generateQr,
                activeColor: const Color(0xFF8B1A2C),
                checkColor: Colors.white,
                title: Text(
                  'Generate invite QR code',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Other users can join using this code.',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white60
                        : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                onChanged: (value) {
                  setDialogState(() => generateQr = value ?? false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isCreatingGroup
                  ? null
                  : () async {
                      final groupName = nameController.text.trim();
                      final capacityText = capacityController.text.trim();
                      final capacity = int.tryParse(capacityText);

                      if (groupName.isNotEmpty &&
                          capacity != null &&
                          capacity > 0) {
                        try {
                          if (mounted) setState(() => _isCreatingGroup = true);
                          final api = Provider.of<AuthProvider>(
                            parentContext,
                            listen: false,
                          ).apiService;
                          final currentUser = Provider.of<AuthProvider>(
                            parentContext,
                            listen: false,
                          ).user;
                          final response = await api.createGroup(
                            groupName,
                            capacity: capacity,
                            generateQr: generateQr,
                            creatorUserId: currentUser?.idRegistration,
                            creatorUsername: currentUser?.username,
                            creatorName: currentUser?.name,
                            creatorSurname: currentUser?.surname,
                          );
                          FocusScope.of(context).unfocus();
                          if (context.mounted) Navigator.of(context).pop();
                          final qrCode = response['qr_code']?.toString();
                          final queued = response['queued'] == true;
                          unawaited(
                            TeamMeeterAnalytics.instance.logGroupCreate(
                              queuedOffline: queued,
                              inviteQrEnabled: generateQr,
                            ),
                          );
                          if (!mounted) return;
                          if (generateQr &&
                              qrCode != null &&
                              qrCode.isNotEmpty &&
                              !queued) {
                            parentContext.showLatestSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Group created. QR code is ready.',
                                ),
                                backgroundColor: const Color(0xFF8B1A2C),
                                action: SnackBarAction(
                                  label: 'Show QR',
                                  textColor: Colors.white,
                                  onPressed: () =>
                                      _showCreatedGroupQrDialog(qrCode),
                                ),
                              ),
                            );
                          }
                          if (queued) {
                            parentContext.showLatestSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Skupina bola uložená offline. Po pripojení sa zosynchronizuje.',
                                ),
                                backgroundColor: Color(0xFFEF6C00),
                              ),
                            );
                          }
                          await _loadGroups(showError: false);
                        } catch (e) {
                          if (mounted) {
                            parentContext.showLatestSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceAll('Exception: ', ''),
                                ),
                                backgroundColor: const Color(0xFF8B1A2C),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isCreatingGroup = false);
                        }
                      } else {
                        parentContext.showLatestSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter a group name and valid capacity (> 0)',
                            ),
                            backgroundColor: Color(0xFF8B1A2C),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B1A2C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreatingGroup
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatedGroupQrDialog(String qrCode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _GroupQrCodeScreen(qrCode: qrCode)),
    );
  }

  // ── Bottom Navigation Bar matching Figma ─────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(26))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildNavItem(Icons.calendar_month_outlined, 0),
            _buildNavItem(Icons.home_rounded, 1, isCenter: true),
            _buildNavItem(Icons.chat_bubble_outline, 2),
            _buildNavItem(Icons.people_outline, 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index, {bool isCenter = false}) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentNavIndex = index);
        if (index == 2) {
          unawaited(
            _conversationsScreenKey.currentState?.reloadConversations() ??
                Future.value(),
          );
        }
        if (index == 3) {
          unawaited(
            _loadGroups(
              showError: false,
              silent: true,
              preservePreviousOnEmpty: true,
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(isCenter ? 14 : 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF8B1A2C).withAlpha(77)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFFE57373) : Colors.white54,
          size: isCenter ? 30 : 26,
        ),
      ),
    );
  }
}

class _GroupQrCodeScreen extends StatelessWidget {
  final String qrCode;

  const _GroupQrCodeScreen({required this.qrCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group invite QR'),
        backgroundColor: AppColors.dialogBackground(context),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
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
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: qrCode,
                size: 240,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share this QR or invite code with users.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(
              qrCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: qrCode));
                if (!context.mounted) return;
                context.showLatestSnackBar(
                  const SnackBar(
                    content: Text('Invite code copied'),
                    backgroundColor: Color(0xFF8B1A2C),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handledScan = false;
  bool _scannerReady = false;
  String? _scannerError;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    try {
      final hasPermission = await PermissionService.ensureCameraPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _scannerError =
              'Camera permission is required for QR scanning. Allow it in app settings.';
        });
        return;
      }

      await _controller.start();
      if (!mounted) return;
      setState(() => _scannerReady = true);
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _scannerError =
            'QR scanner plugin is not initialized yet. Please do a full app restart.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scannerError =
            'Unable to start camera scanner on this device right now.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan group QR'),
        backgroundColor: AppColors.dialogBackground(context),
      ),
      body: _scannerError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_outlined,
                      size: 56,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _scannerError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            )
          : !_scannerReady
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    if (_handledScan) return;
                    final value = capture.barcodes.first.rawValue;
                    if (value == null || value.trim().isEmpty) return;
                    _handledScan = true;
                    Navigator.of(context).pop(value.trim());
                  },
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black.withAlpha(120),
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      'Align the QR code inside camera view',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
