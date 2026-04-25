import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/activity.dart';
import '../models/group.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final api = authProvider.apiService;
      final results = await Future.wait([
        api.getMyActivities(),
        api.getGroups(),
      ]);
      if (mounted) {
        setState(() {
          _activities = results[0] as List<Activity>;
          _groups = results[1] as List<Group>;
        });
      }
    } catch (e) {
      // Show empty state on error
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                child: _currentNavIndex == 1
                    ? _buildTasksView()
                    : _buildGroupsView(),
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
              _currentNavIndex == 1 ? 'My tasks' : 'My groups',
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

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF8B1A2C),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Two task columns
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _buildTaskColumn('To-do', _activities)),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildTaskColumn('In progress', <Activity>[])),
              ],
            ),
            const SizedBox(height: 16),
            // Pagination dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Container(
                  width: i == 0 ? 10 : 8,
                  height: i == 0 ? 10 : 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 0 ? Colors.white : Colors.white30,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // View completed tasks button
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
                    side: BorderSide(
                        color: Colors.white.withAlpha(26)),
                  ),
                ),
                child: const Text('View completed tasks',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w400)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskColumn(String title, List<Activity> activities) {
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
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
    return Container(
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
              activity.deadline!,
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

  // ── Groups View ──────────────────────────────────────────
  Widget _buildGroupsView() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF8B1A2C),
      child: _groups.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(Icons.group_outlined,
                    size: 64, color: Colors.white.withAlpha(77)),
                const SizedBox(height: 16),
                const Text('No groups yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38)),
                const SizedBox(height: 12),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _showCreateGroupDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Group'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B1A2C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _groups.length + 1,
              itemBuilder: (context, index) {
                if (index == _groups.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _showCreateGroupDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create Group'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B1A2C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  );
                }
                final group = _groups[index];
                return _buildGroupCard(group);
              },
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2D1515),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
              authProvider.user?.displayName ?? 'User',
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
              if (nameController.text.isNotEmpty) {
                try {
                  final api =
                      Provider.of<AuthProvider>(context, listen: false)
                          .apiService;
                  await api.createGroup(nameController.text);
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
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
            _buildNavItem(Icons.people_outline, 2),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index,
      {bool isCenter = false}) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
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
