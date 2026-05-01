import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';
import 'group_basic_information_screen.dart';
import 'chat_screen.dart';
import 'group_activities_screen.dart';
import 'group_invites_screen.dart';
import 'group_members_screen.dart';
import 'group_roles_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final Group group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  bool _isDeleting = false;
  bool _isLeaving = false;
  bool _canAccessGroupActivities = false;
  Group? _fullGroup;

  @override
  void initState() {
    super.initState();
    _loadGroupDetails();
  }

  Future<void> _loadGroupDetails() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final group = await api.getGroupDetails(widget.group.idGroup);
      final hasActivityAccess = await api.hasGroupActivityAccess(widget.group.idGroup);
      if (mounted) setState(() => _fullGroup = group);
      if (mounted) {
        setState(() => _canAccessGroupActivities = hasActivityAccess);
      }
    } catch (_) {
      // Ignore for now; option checks handle permission/errors.
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(context),
        title: Text(
          'Delete group',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.group.name}"?',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isDeleting = true);

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteGroup(widget.group.idGroup);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = auth.user?.idRegistration;
    if (currentUserId == null) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Unable to identify current user'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(context),
        title: Text(
          'Leave group',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Are you sure you want to leave "${widget.group.name}"?',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLeaving = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.removeGroupMember(
        groupId: widget.group.idGroup,
        userId: currentUserId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLeaving = false);
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final shownGroup = _fullGroup ?? widget.group;
    final token = authProvider.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group'),
        centerTitle: true,
        backgroundColor: AppColors.dialogBackground(context),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0A0A).withAlpha(190),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(18)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Selected group',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _GroupAvatar(
                        groupId: shownGroup.idGroup,
                        hasIcon: shownGroup.hasIcon,
                        token: token,
                        size: 64,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        shownGroup.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _OptionButton(
                  text: 'Basic information',
                  icon: Icons.info_outline,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupBasicInformationScreen(
                          groupId: shownGroup.idGroup,
                        ),
                      ),
                    );
                    if (mounted) {
                      _loadGroupDetails();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _OptionButton(
                  text: 'Members',
                  icon: Icons.group_outlined,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupMembersScreen(
                          groupId: shownGroup.idGroup,
                          groupName: shownGroup.name,
                        ),
                      ),
                    );
                    if (mounted) {
                      _loadGroupDetails();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _OptionButton(
                  text: 'Roles',
                  icon: Icons.security_outlined,
                  onPressed: () async {
                    try {
                      await api.getGroupRoles(shownGroup.idGroup);
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupRolesScreen(
                            groupId: shownGroup.idGroup,
                            groupName: shownGroup.name,
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      context.showLatestSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceAll('Exception: ', ''),
                          ),
                          backgroundColor: const Color(0xFF8B1A2C),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (_canAccessGroupActivities)
                  _OptionButton(
                    text: 'Group activities',
                    icon: Icons.playlist_add_check_circle_outlined,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupActivitiesScreen(
                            groupId: shownGroup.idGroup,
                            groupName: shownGroup.name,
                          ),
                        ),
                      );
                      if (mounted) {
                        _loadGroupDetails();
                      }
                    }
                  ),
                if (_canAccessGroupActivities) const SizedBox(height: 10),
                _OptionButton(
                  text: 'Chat',
                  icon: Icons.chat_bubble_outline,
                  onPressed: () async {
                    try {
                      final details =
                          _fullGroup ??
                          await api.getGroupDetails(shownGroup.idGroup);
                      final conversationId = details.conversationId;
                      if (conversationId == null) {
                        throw Exception(
                          'Chat pre túto skupinu nie je dostupný',
                        );
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversationId: conversationId,
                            title: details.name,
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      context.showLatestSnackBar(
                        SnackBar(
                          content: Text(e.toString().replaceAll('Exception: ', '')),
                          backgroundColor: const Color(0xFF8B1A2C),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                _OptionButton(
                  text: 'Invites',
                  icon: Icons.qr_code_2_outlined,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInvitesScreen(
                          groupId: shownGroup.idGroup,
                          groupName: shownGroup.name,
                          initialInviteCode: shownGroup.qrCode,
                        ),
                      ),
                    );
                    if (mounted) {
                      _loadGroupDetails();
                    }
                  },
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLeaving ? null : _leaveGroup,
                    icon: _isLeaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFFB3B3),
                            ),
                          )
                        : const Icon(Icons.exit_to_app_rounded, size: 18),
                    label: Text(
                      _isLeaving ? 'Leaving...' : 'Leave Group',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFB3B3),
                      side: BorderSide(color: Colors.white.withAlpha(40)),
                      backgroundColor: const Color(0xFF1A0A0A).withAlpha(90),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isDeleting ? null : _deleteGroup,
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE57373),
                            ),
                          )
                        : const Icon(Icons.delete_forever_outlined, size: 22),
                    label: Text(
                      _isDeleting ? 'Deleting...' : 'Delete Group',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE57373),
                      side: const BorderSide(
                        color: Color(0xFFE57373),
                        width: 1.4,
                      ),
                      backgroundColor: const Color(0xFF1A0A0A).withAlpha(120),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  const _OptionButton({
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white60),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2A1111),
          foregroundColor: Colors.white,
          elevation: 0,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: Colors.white.withAlpha(20)),
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  final int groupId;
  final bool hasIcon;
  final String? token;
  final double size;

  const _GroupAvatar({
    required this.groupId,
    required this.hasIcon,
    required this.token,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final imageUrl = '${ApiService.baseUrl}/groups/$groupId/icon';
    final canLoadNetworkIcon = groupId > 0 && hasIcon && token != null;
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0A0A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder(
                      future: api.getCachedGroupIconBytes(groupId),
                      builder: (context, snapshot) {
                        final cachedBytes = snapshot.data;
                        if (cachedBytes != null && cachedBytes.isNotEmpty) {
                          return Image.memory(cachedBytes, fit: BoxFit.contain);
                        }
                        if (canLoadNetworkIcon) {
                          return Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            headers: {'Authorization': 'Bearer $token'},
                            errorBuilder: (_, error, stackTrace) =>
                                const SizedBox(
                                  height: 220,
                                  child: Center(
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: Colors.white70,
                                      size: 72,
                                    ),
                                  ),
                                ),
                          );
                        }
                        return const SizedBox(
                          height: 220,
                          child: Center(
                            child: Icon(
                              Icons.groups_rounded,
                              color: Colors.white70,
                              size: 72,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withAlpha(80), width: 1.5),
          color: const Color(0xFF2A1111),
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
                errorBuilder: (_, error, stackTrace) => const Icon(
                  Icons.groups_rounded,
                  color: Colors.white70,
                  size: 28,
                ),
              );
            }
            return const Icon(
              Icons.groups_rounded,
              color: Colors.white70,
              size: 28,
            );
          },
        ),
      ),
    );
  }
}
