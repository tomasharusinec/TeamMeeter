import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

class GroupRolesScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupRolesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupRolesScreen> createState() => _GroupRolesScreenState();
}

class _GroupRolesScreenState extends State<GroupRolesScreen> {
  static const List<String> _permissionOptions = [
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
    'delete_messages',
    'create_role',
    'edit_role',
    'delete_role',
    'add_role',
    'manage_roles',
  ];

  List<Role> _roles = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final roles = await api.getGroupRolesModel(widget.groupId);
      final members = await api.getGroupMembers(widget.groupId);
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _members = members;
      });
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showRoleDialog({Role? role}) async {
    final nameController = TextEditingController(text: role?.name ?? '');
    final colorController = TextEditingController(text: role?.color ?? '');
    final selectedPermissions = {...role?.permissions ?? <String>[]};
    Color selectedColor = _parseRoleColor(role?.color);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.dialogBackground(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            role == null ? 'Create role' : 'Edit role',
            style: TextStyle(color: AppColors.textPrimary(dialogContext)),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                    decoration: InputDecoration(
                      labelText: 'Role name',
                      labelStyle: TextStyle(
                        color: AppColors.textMuted(dialogContext),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.outlineMuted(dialogContext),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF8B1A2C)),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: colorController,
                    style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedColor = _parseRoleColor(value);
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Color hex (optional)',
                      hintText: '#8B1A2C',
                      labelStyle: TextStyle(
                        color: AppColors.textMuted(dialogContext),
                      ),
                      hintStyle: TextStyle(
                        color: AppColors.textDisabled(dialogContext),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.outlineMuted(dialogContext),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF8B1A2C)),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: selectedColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.outlineStrong(dialogContext),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Color pickerColor = selectedColor;
                        final picked = await showDialog<Color>(
                          context: context,
                          builder: (pickerContext) => AlertDialog(
                            backgroundColor:
                                AppColors.dialogBackground(pickerContext),
                            title: Text(
                              'Pick role color',
                              style: TextStyle(
                                color: AppColors.textPrimary(pickerContext),
                              ),
                            ),
                            content: SingleChildScrollView(
                              child: ColorPicker(
                                pickerColor: pickerColor,
                                onColorChanged: (color) => pickerColor = color,
                                enableAlpha: false,
                                hexInputBar: true,
                                labelTypes: const [],
                                pickerAreaHeightPercent: 0.7,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(pickerContext),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: AppColors.textSecondary(pickerContext),
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(pickerContext, pickerColor),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B1A2C),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Use color'),
                              ),
                            ],
                          ),
                        );

                        if (picked == null) return;
                        setDialogState(() {
                          selectedColor = picked;
                          colorController.text = _toHexColor(picked);
                        });
                      },
                      icon: const Icon(Icons.color_lens_outlined),
                      label: const Text('Pick color'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary(dialogContext),
                        side: BorderSide(
                          color: AppColors.outlineStrong(dialogContext),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Permissions',
                      style: TextStyle(
                        color: AppColors.textPrimary(dialogContext),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._permissionOptions.map(
                    (permission) => CheckboxListTile(
                      value: selectedPermissions.contains(permission),
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selectedPermissions.add(permission);
                          } else {
                            selectedPermissions.remove(permission);
                          }
                        });
                      },
                      dense: true,
                      activeColor: const Color(0xFF8B1A2C),
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        permission,
                        style: TextStyle(
                          color: AppColors.textMuted(dialogContext),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary(dialogContext),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final color = colorController.text.trim();
                if (name.isEmpty) {
                  this.context.showLatestSnackBar(
                    const SnackBar(content: Text('Role name is required')),
                  );
                  return;
                }
                try {
                  final api = Provider.of<AuthProvider>(
                    this.context,
                    listen: false,
                  ).apiService;
                  final beforeQueue = await api.getPendingOfflineChangesCount();
                  if (role == null) {
                    await api.createGroupRole(
                      groupId: widget.groupId,
                      name: name,
                      color: color.isEmpty ? null : color,
                      permissions: selectedPermissions.toList(),
                    );
                  } else {
                    await api.updateGroupRole(
                      groupId: widget.groupId,
                      roleId: role.idRole,
                      name: name,
                      color: color.isEmpty ? null : color,
                      permissions: selectedPermissions.toList(),
                    );
                  }
                  final afterQueue = await api.getPendingOfflineChangesCount();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _loadRoles();
                  if (!mounted) return;
                  if (afterQueue > beforeQueue) {
                    this.context.showLatestSnackBar(
                      const SnackBar(
                        content: Text('Zmena rolí je uložená offline.'),
                        backgroundColor: Color(0xFFEF6C00),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
                    this.context.showLatestSnackBar(
                      SnackBar(
                        content: Text(
                          role == null
                              ? 'Rola bola úspešne vytvorená.'
                              : 'Úpravy roly boli uložené.',
                        ),
                        backgroundColor: const Color(0xFF2E7D32),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  this.context.showLatestSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: const Color(0xFF8B1A2C),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B1A2C),
                foregroundColor: Colors.white,
              ),
              child: Text(role == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRole(Role role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(dialogContext),
        title: Text(
          'Delete role',
          style: TextStyle(color: AppColors.textPrimary(dialogContext)),
        ),
        content: Text(
          'Delete role "${role.name}"?',
          style: TextStyle(color: AppColors.textMuted(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary(dialogContext),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.deleteGroupRole(groupId: widget.groupId, roleId: role.idRole);
      final afterQueue = await api.getPendingOfflineChangesCount();
      await _loadRoles();
      if (afterQueue > beforeQueue && mounted) {
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Vymazanie roly je uložené offline.'),
            backgroundColor: Color(0xFFEF6C00),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Rola bola odstránená.'),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  Future<void> _showRemoveRoleDialog() async {
    if (_roles.isEmpty || _members.isEmpty) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Nie sú načítané role alebo členovia skupiny'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    String? selectedUsername = _members.first['username']?.toString();
    Role? selectedRole = _roles.first;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.dialogBackground(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Remove role from user',
            style: TextStyle(color: AppColors.textPrimary(dialogContext)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedUsername,
                isExpanded: true,
                dropdownColor: AppColors.dialogBackground(dialogContext),
                decoration: InputDecoration(
                  labelText: 'User',
                  labelStyle: TextStyle(
                    color: AppColors.textMuted(dialogContext),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outlineMuted(dialogContext),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFF8B1A2C)),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                items: _members
                    .map(
                      (m) => DropdownMenuItem<String>(
                        value: m['username']?.toString(),
                        child: Text(
                          '@${m['username'] ?? '-'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedUsername = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedRole?.idRole,
                isExpanded: true,
                dropdownColor: AppColors.dialogBackground(dialogContext),
                decoration: InputDecoration(
                  labelText: 'Role',
                  labelStyle: TextStyle(
                    color: AppColors.textMuted(dialogContext),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outlineMuted(dialogContext),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFF8B1A2C)),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                items: _roles
                    .map(
                      (r) => DropdownMenuItem<int>(
                        value: r.idRole,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(
                  () => selectedRole = _roles.firstWhere(
                    (r) => r.idRole == value,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary(dialogContext),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedUsername == null || selectedRole == null) return;

                final member = _members.firstWhere(
                  (m) => m['username']?.toString() == selectedUsername,
                  orElse: () => <String, dynamic>{},
                );
                final userId = member['id_registration'] as int?;
                if (userId == null) return;

                try {
                  final api = Provider.of<AuthProvider>(
                    this.context,
                    listen: false,
                  ).apiService;
                  final beforeQueue = await api.getPendingOfflineChangesCount();
                  await api.removeUserRole(
                    groupId: widget.groupId,
                    userId: userId,
                    roleId: selectedRole!.idRole,
                  );
                  final afterQueue = await api.getPendingOfflineChangesCount();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  this.context.showLatestSnackBar(
                    SnackBar(
                      content: Text(
                        afterQueue > beforeQueue
                            ? 'Odobratie roly je uložené offline.'
                            : 'Rola bola odobratá používateľovi',
                      ),
                      backgroundColor: afterQueue > beforeQueue
                          ? const Color(0xFFEF6C00)
                          : const Color(0xFF2E7D32),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  this.context.showLatestSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: const Color(0xFF8B1A2C),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B1A2C),
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseRoleColor(String? color) {
    if (color == null || color.isEmpty) return const Color(0xFF8B1A2C);
    final normalized = color.replaceAll('#', '');
    if (normalized.length == 6) {
      try {
        return Color(int.parse('FF$normalized', radix: 16));
      } catch (_) {
        return const Color(0xFF8B1A2C);
      }
    }
    return const Color(0xFF8B1A2C);
  }

  String _toHexColor(Color color) {
    final hex = color.toARGB32().toRadixString(16).toUpperCase();
    return '#${hex.substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Roles - ${widget.groupName}'),
        backgroundColor: AppColors.dialogBackground(context),
        foregroundColor: AppColors.textPrimary(context),
        actions: [
          IconButton(
            onPressed: _showRemoveRoleDialog,
            tooltip: 'Remove role from user',
            icon: const Icon(Icons.person_remove_alt_1),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
          ),
        ),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.circularProgressOnBackground(context),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadRoles,
                color: const Color(0xFF8B1A2C),
                child: _roles.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 160),
                          Center(
                            child: Text(
                              'No roles yet',
                              style: TextStyle(
                                color: AppColors.textMuted(context),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _roles.length,
                        itemBuilder: (context, index) {
                          final role = _roles[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppColors.listCardBackground(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.listCardBorderMedium(context),
                              ),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _parseRoleColor(role.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Text(
                                role.name,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              subtitle: Text(
                                role.color ?? 'No color',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                color: AppColors.dialogBackground(context),
                                icon: Icon(
                                  Icons.more_vert,
                                  color: AppColors.textMuted(context),
                                ),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showRoleDialog(role: role);
                                  } else if (value == 'delete') {
                                    _deleteRole(role);
                                  }
                                },
                                itemBuilder: (menuContext) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: AppColors.textPrimary(
                                          menuContext,
                                        ),
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: AppColors.textPrimary(
                                          menuContext,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRoleDialog(),
        backgroundColor: const Color(0xFF8B1A2C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
