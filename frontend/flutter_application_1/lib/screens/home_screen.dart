import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/activity.dart';
import '../models/group.dart';
import 'activity_detail_dialog.dart';
import 'calendar_screen.dart';
import 'group_detail_screen.dart';

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
    return Scaffold(
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
              child: Center(
                child: Text(
                  user?.initials ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTaskColumn('To-do', _activities)),
                const SizedBox(width: 12),
                Expanded(child: _buildTaskColumn('In progress', <Activity>[])),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {},
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

  Widget _buildTaskColumn(String title, List<Activity> activities) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A).withAlpha(204),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(13)),
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
  }

  Widget _buildTaskItem(Activity activity) {
    return GestureDetector(
      onTap: () => _showActivityDetail(activity),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0F0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(38),
              blurRadius: 4,
              offset: const Offset(0, 1),
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

  // ── Profile Bottom Sheet ─────────────────────────────────
  void _showProfileMenu() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0A0A),
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
              child: Center(
                child: Text(
                  authProvider.user?.initials ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
        backgroundColor: const Color(0xFF1A0A0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('Join Group', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: codeController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Invite code or group ID',
            hintStyle: const TextStyle(color: Colors.white38),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Join group coming soon'),
                  backgroundColor: Color(0xFF8B1A2C),
                ),
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
    );
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Create Group',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: const TextStyle(color: Colors.white38),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final groupName = nameController.text.trim();
              if (groupName.isNotEmpty) {
                try {
                  final api =
                      Provider.of<AuthProvider>(context, listen: false)
                          .apiService;
                  await api.createGroup(groupName);
                  if (context.mounted) Navigator.pop(context);
                  await _loadGroups();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Create'),
          ),
        ],
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
