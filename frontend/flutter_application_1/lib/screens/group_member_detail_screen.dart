import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/role.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

/// Detail člena skupiny — priradenie rolí cez **Add role** (oprávnenie `add_role` alebo Manager).
class GroupMemberDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final Map<String, dynamic> member;

  const GroupMemberDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.member,
  });

  @override
  State<GroupMemberDetailScreen> createState() => _GroupMemberDetailScreenState();
}

class _GroupMemberDetailScreenState extends State<GroupMemberDetailScreen> {
  bool _isLoading = true;
  bool _isAssigning = false;
  List<Map<String, dynamic>> _memberRoles = [];
  List<Role> _allGroupRoles = [];
  bool _canAddRole = false;
  /// Zaistenie proti tomu, aby starší async `_load` prepísal novší výsledok (prepínanie tam/späť, viac paralelných loadov).
  int _loadGeneration = 0;

  int? get _memberUserId {
    final raw = widget.member['id_registration'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String _displayName() {
    final name = widget.member['name']?.toString();
    final surname = widget.member['surname']?.toString();
    final full = '${name ?? ''} ${surname ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    return widget.member['username']?.toString() ?? 'Neznámy';
  }

  String _initials() {
    final name = widget.member['name']?.toString();
    final surname = widget.member['surname']?.toString();
    if (name != null &&
        name.isNotEmpty &&
        surname != null &&
        surname.isNotEmpty) {
      return '${name[0]}${surname[0]}'.toUpperCase();
    }
    final username = widget.member['username']?.toString() ?? '';
    return username.isNotEmpty ? username[0].toUpperCase() : 'U';
  }

  int? _parseRoleId(Map<String, dynamic> r) {
    final raw = r['id_role'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  List<Map<String, dynamic>> _dedupeRolesById(List<Map<String, dynamic>> raw) {
    final byId = <int, Map<String, dynamic>>{};
    for (final r in raw) {
      final id = _parseRoleId(r);
      if (id != null) byId[id] = r;
    }
    return byId.values.toList();
  }

  /// Po úspešnom assigne: doplní / opraví riadok, aby UI nezmizlo pri oneskorenom GET.
  void _mergeAssignedRoleLocally(Role role) {
    if (!mounted) return;
    setState(() {
      final next = List<Map<String, dynamic>>.from(_memberRoles);
      final idx = next.indexWhere((r) => _parseRoleId(r) == role.idRole);
      if (idx >= 0) {
        final row = Map<String, dynamic>.from(next[idx]);
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty && role.name.isNotEmpty) {
          row['name'] = role.name;
        }
        final colorStr = row['color']?.toString().trim();
        if ((colorStr == null || colorStr.isEmpty) &&
            role.color != null &&
            role.color!.trim().isNotEmpty) {
          row['color'] = role.color;
        }
        next[idx] = row;
        _memberRoles = _dedupeRolesById(next);
      } else {
        next.add({
          'id_role': role.idRole,
          'name': role.name,
          'color': role.color,
        });
        _memberRoles = _dedupeRolesById(next);
      }
    });
  }

  bool _currentUserMayAssignRoles(
    int? myUserId,
    List<Role> allRoles,
    List<Map<String, dynamic>> myRoleRows,
  ) {
    if (myUserId == null) return false;
    final myRoleIds = myRoleRows
        .map(_parseRoleId)
        .whereType<int>()
        .toSet();
    for (final role in allRoles) {
      if (!myRoleIds.contains(role.idRole)) continue;
      if (role.name == 'Manager') return true;
      if (role.permissions.contains('add_role')) return true;
    }
    return false;
  }

  Future<void> _load({bool showBlockingLoader = true}) async {
    final generation = ++_loadGeneration;
    if (showBlockingLoader && mounted) {
      setState(() => _isLoading = true);
    }
    final userId = _memberUserId;
    if (userId == null) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
      return;
    }
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final myId = auth.user?.idRegistration;

      final memberRolesF = api.getUserRolesInGroup(
        groupId: widget.groupId,
        userId: userId,
      );
      final allRolesF = api.getGroupRolesModel(widget.groupId);
      final myRolesF = myId != null
          ? api.getUserRolesInGroup(groupId: widget.groupId, userId: myId)
          : Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[]);
      final results = await Future.wait([memberRolesF, allRolesF, myRolesF]);
      if (!mounted || generation != _loadGeneration) return;

      final memberRoles = results[0] as List<Map<String, dynamic>>;
      final allRoles = results[1] as List<Role>;

      /// Po await môže byť používateľ už v AuthProvider, hoci tesne pred tým bol null — inak by ostalo `_canAddRole == false`.
      final authResolved =
          Provider.of<AuthProvider>(context, listen: false);
      final resolvedMyId = authResolved.user?.idRegistration;
      late List<Map<String, dynamic>> myRoles;
      if (resolvedMyId == null) {
        myRoles = <Map<String, dynamic>>[];
      } else if (myId != null && myId == resolvedMyId) {
        myRoles = results[2] as List<Map<String, dynamic>>;
      } else {
        myRoles = await api.getUserRolesInGroup(
          groupId: widget.groupId,
          userId: resolvedMyId,
        );
        if (!mounted || generation != _loadGeneration) return;
      }

      final canAdd =
          _currentUserMayAssignRoles(resolvedMyId, allRoles, myRoles);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _memberRoles = _dedupeRolesById(memberRoles);
        _allGroupRoles = allRoles;
        _canAddRole = canAdd;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showAssignRoleSheet() async {
    final username = widget.member['username']?.toString();
    if (username == null || username.isEmpty) return;

    final assignedIds =
        _memberRoles.map(_parseRoleId).whereType<int>().toSet();
    final choices =
        _allGroupRoles.where((r) => !assignedIds.contains(r.idRole)).toList();
    if (choices.isEmpty) {
      if (!mounted) return;
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Člen už má všetky dostupné roly v tejto skupine.'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.dialogBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final maxH = MediaQuery.sizeOf(sheetContext).height * 0.5;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add role',
                      style: TextStyle(
                        color: AppColors.textPrimary(sheetContext),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vyber jednu z rolí definovaných v tejto skupine.',
                      style: TextStyle(
                        color: AppColors.textMuted(sheetContext),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: choices.length,
                  itemBuilder: (_, index) {
                    final role = choices[index];
                    final color = _parseColor(role.color);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color ?? const Color(0xFF8B1A2C),
                        child: Text(
                          role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        role.name,
                        style: TextStyle(
                          color: AppColors.textPrimary(sheetContext),
                        ),
                      ),
                      onTap: _isAssigning
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              await _assignRole(username, role);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Len roly so zobrazeným menom — bez placeholder textu pri prázdnom zozname.
  List<Widget> _roleChips(BuildContext context) {
    final out = <Widget>[];
    for (final r in _memberRoles) {
      final id = _parseRoleId(r);
      final name = r['name']?.toString().trim() ?? '';
      final label =
          name.isNotEmpty ? name : (id != null ? 'Rola $id' : 'Rola');
      out.add(
        Chip(
          label: Text(label),
          backgroundColor: AppColors.surfaceSecondary(context),
          labelStyle: TextStyle(
            color: AppColors.textPrimary(context),
          ),
          side: BorderSide(
            color: AppColors.listCardBorderMedium(context),
          ),
        ),
      );
    }
    return out;
  }

  Color? _parseColor(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var s = raw.trim();
    if (!s.startsWith('#')) s = '#$s';
    try {
      return Color(int.parse(s.replaceFirst('#', '0xff')));
    } catch (_) {
      return null;
    }
  }

  Future<void> _assignRole(String username, Role role) async {
    setState(() => _isAssigning = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.assignUserRole(
        groupId: widget.groupId,
        username: username,
        roleId: role.idRole,
      );
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      _mergeAssignedRoleLocally(role);
      await _load(showBlockingLoader: false);
      _mergeAssignedRoleLocally(role);
      if (!mounted) return;
      for (var i = 0; i < 2; i++) {
        await Future<void>.delayed(Duration(milliseconds: 220 * (i + 1)));
        if (!mounted) return;
        await _load(showBlockingLoader: false);
        _mergeAssignedRoleLocally(role);
      }
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Priradenie roly je uložené offline.'
                : 'Rola bola úspešne priradená.',
          ),
          backgroundColor: afterQueue > beforeQueue
              ? const Color(0xFFEF6C00)
              : const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
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
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final roleChips = _roleChips(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName()),
        backgroundColor: AppColors.dialogBackground(context),
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
            stops: const [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.circularProgressOnBackground(context),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF8B1A2C),
                      child: Text(
                        _initials(),
                        style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _displayName(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '@${widget.member['username'] ?? '-'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted(context),
                        fontSize: 15,
                      ),
                    ),
                    if (widget.member['email'] != null &&
                        widget.member['email'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.member['email'].toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Skupina: ${widget.groupName}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textDisabled(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Priradené roly',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (roleChips.isEmpty)
                      Text(
                        _canAddRole
                            ? 'Zatiaľ žiadna. Použi tlačidlo Add role nižšie.'
                            : 'Tento člen zatiaľ nemá priradené žiadne roly.',
                        style: TextStyle(
                          color: AppColors.textMuted(context),
                          fontSize: 14,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: roleChips,
                      ),
                    if (_canAddRole) ...[
                      const SizedBox(height: 24),
                      Tooltip(
                        message: 'Pridať rolu zo zoznamu rolí skupiny',
                        child: ElevatedButton(
                          onPressed: _isAssigning ? null : _showAssignRoleSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B1A2C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isAssigning
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Ukladám…'),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.badge_outlined),
                                    SizedBox(width: 8),
                                    Text('Add role'),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
