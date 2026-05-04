// Zoznam členov konkrétnej skupiny používateľa s vyhľadávaním a rýchlym prehľadom účtov.
// Odtiaľ sa dá vstúpiť do detailu člena alebo vykonať skupinové úpravy kde to oprávnenia dovolujú.
// AI generated with manual refinements




import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';
import 'group_member_detail_screen.dart';

class GroupMembersScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupMembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  final _usernameController = TextEditingController();
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isAdding = false;
  int? _removingUserId;

  @override
  // Tato funkcia pripravi uvodny stav obrazovky.
  // Spusta prve nacitanie dat a potrebne inicializacie.
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  // Tato funkcia uprace zdroje pred zatvorenim obrazovky.
  // Zastavi listenery, timery alebo controllery.
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // Tato funkcia nacita alebo obnovi data.
  // Pouziva API volania a potom aktualizuje stav.
  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final members = await api.getGroupMembers(widget.groupId);
      if (!mounted) return;
      setState(() => _members = members);
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Tato funkcia vytvori novu polozku.
  // Po uspesnom vytvoreni obnovi zoznam alebo UI.
  Future<void> _addMember() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    setState(() => _isAdding = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.addGroupMember(groupId: widget.groupId, username: username);
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      _usernameController.clear();
      await _loadMembers();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Pridanie člena bolo uložené offline.'
                : 'Member added successfully',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
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
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  // Tato funkcia odstrani vybranu polozku.
  // Po vymazani synchronizuje stav obrazovky.
  Future<void> _removeMember(Map<String, dynamic> member) async {
    final userId = member['id_registration'] as int?;
    if (userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(context),
        title: Text(
          'Remove member',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Remove ${_memberDisplayName(member)} from group?',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _removingUserId = userId);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.removeGroupMember(groupId: widget.groupId, userId: userId);
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      await _loadMembers();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Odstránenie člena bolo uložené offline.'
                : 'Member removed successfully',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
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
    } finally {
      if (mounted) setState(() => _removingUserId = null);
    }
  }

  String _memberDisplayName(Map<String, dynamic> member) {
    final name = member['name']?.toString();
    final surname = member['surname']?.toString();
    final full = '${name ?? ''} ${surname ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    return member['username']?.toString() ?? 'Unknown';
  }

  String _memberInitials(Map<String, dynamic> member) {
    final name = member['name']?.toString();
    final surname = member['surname']?.toString();
    if (name != null &&
        name.isNotEmpty &&
        surname != null &&
        surname.isNotEmpty) {
      return '${name[0]}${surname[0]}'.toUpperCase();
    }
    final username = member['username']?.toString() ?? '';
    return username.isNotEmpty ? username[0].toUpperCase() : 'U';
  }

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).user?.idRegistration;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        backgroundColor: AppColors.dialogBackground(context),
        foregroundColor: AppColors.textPrimary(context),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSecondary(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.listCardBorderMedium(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          style: TextStyle(color: AppColors.textPrimary(context)),
                          decoration: InputDecoration(
                            hintText: 'Username to add',
                            hintStyle: TextStyle(
                              color: AppColors.textDisabled(context),
                            ),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.outlineMuted(context),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF8B1A2C),
                              ),
                            ),
                            filled: true,
                            fillColor: AppColors.isDark(context)
                                ? const Color(0xFF1A0A0A)
                                : const Color(0xFFF8F5F5),
                          ),
                          onSubmitted: (_) => _isAdding ? null : _addMember(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isAdding ? null : _addMember,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B1A2C),
                          foregroundColor: Colors.white,
                        ),
                        child: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.circularProgressOnBackground(
                              context,
                            ),
                          ),
                        )
                      : _members.isEmpty
                      ? Center(
                          child: Text(
                            'No members found',
                            style: TextStyle(
                              color: AppColors.textMuted(context),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMembers,
                          color: const Color(0xFF8B1A2C),
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: _members.length,
                            itemBuilder: (context, index) {
                              final member = _members[index];
                              final userId = member['id_registration'] as int?;
                              final isRemoving = _removingUserId == userId;
                              final isCurrentUser =
                                  currentUserId != null &&
                                  userId == currentUserId;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.listCardBackground(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.listCardBorder(context),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF8B1A2C),
                                    child: Text(
                                      _memberInitials(member),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    _memberDisplayName(member),
                                    style: TextStyle(
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '@${member['username'] ?? '-'}',
                                        style: TextStyle(
                                          color: AppColors.textMuted(context),
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Klikni pre detaily a pridanie roly',
                                        style: TextStyle(
                                          color: AppColors.textDisabled(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: isRemoving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFFE57373),
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!isCurrentUser)
                                              IconButton(
                                                onPressed: userId == null
                                                    ? null
                                                    : () =>
                                                        _removeMember(member),
                                                icon: const Icon(
                                                  Icons
                                                      .person_remove_outlined,
                                                  color: Color(0xFFE57373),
                                                ),
                                                tooltip: 'Remove member',
                                              ),
                                            Icon(
                                              Icons.chevron_right,
                                              color: AppColors.textDisabled(
                                                context,
                                              ),
                                            ),
                                          ],
                                        ),
                                  onTap: userId == null
                                      ? null
                                      : () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  GroupMemberDetailScreen(
                                                groupId: widget.groupId,
                                                groupName: widget.groupName,
                                                member: member,
                                              ),
                                            ),
                                          );
                                          if (mounted) {
                                            await _loadMembers();
                                          }
                                        },
                                ),
                              );
                            },
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
