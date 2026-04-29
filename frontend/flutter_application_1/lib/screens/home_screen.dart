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
import '../models/activity.dart';
import '../models/group.dart';
import 'activity_detail_dialog.dart';
import 'calendar_screen.dart';
import 'group_detail_screen.dart';
import 'user_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 1; // Home is center/default
  List<Activity> _activities = [];
  List<Group> _groups = [];
  bool _isLoading = true;
  bool _isGroupsLoading = false;
  bool _isUpdatingActivityStatus = false;
  bool _isCreatingGroup = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.ensureCurrentUserLoaded();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadActivities(showError: false),
      _loadGroups(showError: false),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadActivities({bool showError = true}) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      final activities = await api.getMyActivities();
      if (mounted) setState(() => _activities = activities);
    } catch (e) {
      if (!mounted || !showError) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  Future<void> _loadGroups({bool showError = true}) async {
    if (mounted) setState(() => _isGroupsLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      final groups = await api.getGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (!mounted || !showError) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGroupsLoading = false);
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
              Expanded(
                child: _currentNavIndex == 3
                    ? _buildGroupsView()
                    : _currentNavIndex == 2
                        ? _buildChatView()
                        : _currentNavIndex == 0
                            ? _buildCalendarView()
                            : _buildTasksView(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
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
            onPressed: () {},
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined,
                    color: Colors.white, size: 28),
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
            tooltip: isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
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
          child: CircularProgressIndicator(color: Colors.white));
    }

    final todoActivities =
        _activities.where((a) => a.status == 'todo').toList();
    final inProgressActivities =
        _activities.where((a) => a.status == 'in_progress').toList();
    final completedActivities =
        _activities.where((a) => a.status == 'completed').toList();

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
              child: const Text('View completed tasks',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                              color: Colors.white38, fontSize: 12),
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
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTaskCard(activity),
      ),
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
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showActivityDetail(Activity activity) {
    showDialog(
      context: context,
      builder: (context) => ActivityDetailDialog(
        activity: activity,
        onDeleted: _loadData,
      ),
    );
  }

  Future<void> _setActivityStatus(int activityId, String newStatus) async {
    setState(() => _isUpdatingActivityStatus = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.updateActivityStatus(activityId, newStatus);
      await _loadActivities(showError: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    return CalendarScreen(
      groups: _groups,
      onDataChanged: _loadData,
    );
  }

  Widget _buildChatView() {
    return const Center(
      child: Text(
        'Chat coming soon',
        style: TextStyle(color: Colors.white70, fontSize: 16),
      ),
    );
  }

  Widget _buildGroupsView() {
    if (_isLoading || _isGroupsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadGroups,
          color: const Color(0xFF8B1A2C),
          child: _groups.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 120),
                    Icon(Icons.group_outlined,
                        size: 64, color: Colors.white.withAlpha(77)),
                    const SizedBox(height: 16),
                    const Text('No groups yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38)),
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
          backgroundColor:
              isPrimary ? const Color(0xFF8B1A2C) : const Color(0xFF2A1111),
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
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(group: group),
            ),
          );
          if (mounted) {
            _loadData();
          }
        },
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _GroupListAvatar(
          groupId: group.idGroup,
          hasIcon: group.hasIcon,
          fallbackLetter: group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
        ),
        title: Text(group.name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500)),
        subtitle: Text(
          group.createDate ?? '',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing:
            const Icon(Icons.chevron_right, color: Colors.white38),
      ),
    );
  }

  Widget _GroupListAvatar({
    required int groupId,
    required bool hasIcon,
    required String fallbackLetter,
  }) {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final imageUrl = '${ApiService.baseUrl}/groups/$groupId/icon';

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF2D1515),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasIcon && token != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer $token'},
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
            )
          : Center(
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

  Widget _buildUserAvatarContent({
    required double userSize,
    required String fallbackText,
  }) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final token = authProvider.token;
    final hasPicture = user?.hasProfilePicture ?? false;
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
                border:
                    Border.all(color: const Color(0xFF8B1A2C), width: 2),
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
            Text(
              authProvider.user?.email ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
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
                  await Provider.of<AuthProvider>(this.context, listen: false)
                      .refreshCurrentUser();
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
                      borderRadius: BorderRadius.circular(16)),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                  MaterialPageRoute(
                    builder: (_) => const _QrScannerScreen(),
                  ),
                );
                if (!context.mounted || scannedCode == null || scannedCode.isEmpty) {
                  return;
                }
                codeController.text = scannedCode;
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
              await _joinGroupByInviteCode(inviteCode, dialogContext: context);
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
    );
  }

  Future<void> _joinGroupByInviteCode(
    String inviteCode, {
    BuildContext? dialogContext,
  }) async {
    final code = inviteCode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an invite code'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.joinGroupByInviteCode(code);
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      await _loadGroups();
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('Joined group successfully'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
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
              borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Create Group',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    borderSide:
                        BorderSide(color: Colors.white.withAlpha(51)),
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
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    borderSide:
                        BorderSide(color: Colors.white.withAlpha(51)),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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

                if (groupName.isNotEmpty && capacity != null && capacity > 0) {
                  try {
                    if (mounted) setState(() => _isCreatingGroup = true);
                    final api = Provider.of<AuthProvider>(
                      parentContext,
                      listen: false,
                    ).apiService;
                    final response = await api.createGroup(
                      groupName,
                      capacity: capacity,
                      generateQr: generateQr,
                    );
                    FocusScope.of(context).unfocus();
                    if (context.mounted) Navigator.of(context).pop();
                    final qrCode = response['qr_code']?.toString();
                    if (!mounted) return;
                    if (generateQr && qrCode != null && qrCode.isNotEmpty) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: const Text('Group created. QR code is ready.'),
                          backgroundColor: const Color(0xFF8B1A2C),
                          action: SnackBarAction(
                            label: 'Show QR',
                            textColor: Colors.white,
                            onPressed: () => _showCreatedGroupQrDialog(qrCode),
                          ),
                        ),
                      );
                    }
                    _loadGroups();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
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
                  ScaffoldMessenger.of(parentContext).showSnackBar(
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
                    borderRadius: BorderRadius.circular(12)),
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
      MaterialPageRoute(
        builder: (_) => _GroupQrCodeScreen(qrCode: qrCode),
      ),
    );
  }

  // ── Bottom Navigation Bar matching Figma ─────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(26)),
        ),
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

  Widget _buildNavItem(IconData icon, int index,
      {bool isCenter = false}) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentNavIndex = index);
        if (index == 3 || index == 0) {
          _loadGroups();
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
                ScaffoldMessenger.of(context).showSnackBar(
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
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
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
