import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/group.dart';
import '../models/role.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';
import '../services/teammeeter_analytics.dart';

class CreateActivityDialog extends StatefulWidget {
  final List<Group> groups;
  final VoidCallback? onActivityCreated;

  const CreateActivityDialog({
    super.key,
    required this.groups,
    this.onActivityCreated,
  });

  @override
  State<CreateActivityDialog> createState() => _CreateActivityDialogState();
}

class _CreateActivityDialogState extends State<CreateActivityDialog> {
  static const String _roleNone = '__none__';
  static const String _roleAll = '__all__';
  static const String _rolePick = '__pick__';

  final _nameController = TextEditingController();
  DateTime? _selectedDeadline;
  Group? _selectedGroup;
  /// `__none__` | `__all__` | `__pick__` | `'${idRole}'` pre jednu rolu
  String _roleChoice = _roleNone;
  final Set<int> _pickedRoleIds = {};
  List<Role> _roles = [];
  bool _isLoadingRoles = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles(int groupId) async {
    setState(() => _isLoadingRoles = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final roles = await api.getGroupRolesModel(groupId);
      if (mounted) {
        setState(() {
          _roles = roles;
          _roleChoice = _roleNone;
          _pickedRoleIds.clear();
        });
      }
    } catch (e) {
      // silently fail – roles dropdown will just be empty
    } finally {
      if (mounted) setState(() => _isLoadingRoles = false);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (pickerCtx, child) {
        final dark = AppColors.isDark(pickerCtx);
        return Theme(
          data: Theme.of(pickerCtx).copyWith(
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: Color(0xFF8B1A2C),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1A0A0A),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Color(0xFF8B1A2C),
                    onPrimary: Colors.white,
                    surface: Color(0xFFF2ECEC),
                    onSurface: Color(0xFF1A1A1A),
                  ),
            dialogTheme: DialogThemeData(
              backgroundColor: dark
                  ? const Color(0xFF1A0A0A)
                  : const Color(0xFFF2ECEC),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (pickerCtx, child) {
          final dark = AppColors.isDark(pickerCtx);
          return Theme(
            data: Theme.of(pickerCtx).copyWith(
              colorScheme: dark
                  ? const ColorScheme.dark(
                      primary: Color(0xFF8B1A2C),
                      onPrimary: Colors.white,
                      surface: Color(0xFF1A0A0A),
                      onSurface: Colors.white,
                    )
                  : const ColorScheme.light(
                      primary: Color(0xFF8B1A2C),
                      onPrimary: Colors.white,
                      surface: Color(0xFFF2ECEC),
                      onSurface: Color(0xFF1A1A1A),
                    ),
              dialogTheme: DialogThemeData(
                backgroundColor: dark
                    ? const Color(0xFF1A0A0A)
                    : const Color(0xFFF2ECEC),
              ),
            ),
            child: child!,
          );
        },
      );
      if (time != null && mounted) {
        setState(() {
          _selectedDeadline = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      } else {
        setState(() {
          _selectedDeadline = picked;
        });
      }
    }
  }

  Future<void> _createActivity() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Zadajte názov aktivity')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      if (_selectedGroup != null &&
          _roleChoice == _rolePick &&
          _pickedRoleIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pri „Vybrať roly“ označ aspoň jednu rolu, alebo zmeň typ priradenia.',
              ),
            ),
          );
        }
        return;
      }

      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final deadlineStr = _selectedDeadline?.toUtc().toIso8601String();

      if (_selectedGroup != null) {
        // Group activity
        final result = await api.createGroupActivity(
          groupId: _selectedGroup!.idGroup,
          name: name,
          deadline: deadlineStr,
        );
        // Priradenie rolí (žiadna / jedna / všetky) — voliteľné, chyby priradenia nechajú aktivitu vytvorenú
        var roleAssigned = false;
        final rawId = result['activity_id'];
        final activityId = rawId is int
            ? rawId
            : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
        if (activityId != null && activityId > 0) {
          if (_roleChoice == _roleAll) {
            for (final r in _roles) {
              try {
                await api.assignActivityRole(activityId, r.idRole);
                roleAssigned = true;
              } catch (_) {}
            }
          } else if (_roleChoice == _rolePick) {
            final ids = _pickedRoleIds.toList()..sort();
            for (final roleId in ids) {
              try {
                await api.assignActivityRole(activityId, roleId);
                roleAssigned = true;
              } catch (_) {}
            }
          } else if (_roleChoice != _roleNone) {
            final roleId = int.tryParse(_roleChoice);
            if (roleId != null) {
              try {
                await api.assignActivityRole(activityId, roleId);
                roleAssigned = true;
              } catch (_) {}
            }
          }
        }
        final queued = result['queued'] == true;
        unawaited(
          TeamMeeterAnalytics.instance.logActivityCreate(
            isGroupActivity: true,
            queuedOffline: queued,
            roleAssigned: roleAssigned,
          ),
        );
        if (mounted) {
          Navigator.pop(context);
          widget.onActivityCreated?.call();
          context.showLatestSnackBar(
            SnackBar(
              content: Text(
                queued
                    ? 'Aktivita uložená offline. Po pripojení sa zosynchronizuje.'
                    : 'Aktivita bola vytvorená',
              ),
              backgroundColor: queued
                  ? const Color(0xFFEF6C00)
                  : const Color(0xFF2E7D32),
            ),
          );
        }
      } else {
        // Individual activity
        final result = await api.createIndividualActivity(
          name: name,
          deadline: deadlineStr,
        );
        final queued = result['queued'] == true;
        unawaited(
          TeamMeeterAnalytics.instance.logActivityCreate(
            isGroupActivity: false,
            queuedOffline: queued,
            roleAssigned: false,
          ),
        );
        if (mounted) {
          Navigator.pop(context);
          widget.onActivityCreated?.call();
          context.showLatestSnackBar(
            SnackBar(
              content: Text(
                queued
                    ? 'Aktivita uložená offline. Po pripojení sa zosynchronizuje.'
                    : 'Aktivita bola vytvorená',
              ),
              backgroundColor: queued
                  ? const Color(0xFFEF6C00)
                  : const Color(0xFF2E7D32),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  String _formatDeadline(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppColors.isDark(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? const [
                    Color(0xFF1A0A0A),
                    Color(0xFF3D0C0C),
                    Color(0xFF6B1520),
                  ]
                : const [
                    Color(0xFFF2ECEC),
                    Color(0xFFE8DFDF),
                    Color(0xFFD8D2D2),
                  ],
          ),
          border: Border.all(color: AppColors.outlineMuted(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(128),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  'Create activity',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // Name field
                _buildLabel('Name:'),
                const SizedBox(height: 6),
                _buildTextField(_nameController, 'Názov aktivity'),
                const SizedBox(height: 16),

                // Time field
                _buildLabel('Time:'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickDeadline,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                    child: Text(
                      _selectedDeadline != null
                          ? _formatDeadline(_selectedDeadline!)
                          : 'Vyberte termín',
                      style: TextStyle(
                        color: _selectedDeadline != null
                            ? const Color(0xFF333333)
                            : const Color(0xFF999999),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Group selector (optional)
                _buildLabel('Group (optional):'),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Group?>(
                      value: _selectedGroup,
                      isExpanded: true,
                      hint: const Text(
                        'Individuálna',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 14,
                        ),
                      ),
                      dropdownColor: const Color(0xFFF5F0F0),
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFF666666),
                      ),
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 14,
                      ),
                      items: [
                        const DropdownMenuItem<Group?>(
                          value: null,
                          child: Text('Individuálna'),
                        ),
                        ...widget.groups.map(
                          (g) => DropdownMenuItem<Group?>(
                            value: g,
                            child: Text(g.name),
                          ),
                        ),
                      ],
                      onChanged: (group) {
                        setState(() {
                          _selectedGroup = group;
                          _roleChoice = _roleNone;
                          _roles = [];
                          _pickedRoleIds.clear();
                        });
                        if (group != null) {
                          _loadRoles(group.idGroup);
                        }
                      },
                    ),
                  ),
                ),

                // Assign to roles (only when group selected)
                if (_selectedGroup != null) ...[
                  const SizedBox(height: 16),
                  _buildLabel('Assign to roles:'),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    child: _isLoadingRoles
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF8B1A2C),
                              ),
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _roleChoice,
                              isExpanded: true,
                              dropdownColor: const Color(0xFFF5F0F0),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Color(0xFF666666),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 14,
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: _roleNone,
                                  child: Text('Žiadna rola'),
                                ),
                                DropdownMenuItem<String>(
                                  value: _roleAll,
                                  enabled: _roles.isNotEmpty,
                                  child: Text(
                                    'Všetky roly v skupine',
                                    style: TextStyle(
                                      color: _roles.isEmpty
                                          ? const Color(0xFFBBBBBB)
                                          : const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: _rolePick,
                                  enabled: _roles.isNotEmpty,
                                  child: Text(
                                    'Vybrať roly na pridelenie',
                                    style: TextStyle(
                                      color: _roles.isEmpty
                                          ? const Color(0xFFBBBBBB)
                                          : const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                                ..._roles.map(
                                  (r) => DropdownMenuItem<String>(
                                    value: '${r.idRole}',
                                    child: Row(
                                      children: [
                                        if (r.color != null)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            margin: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _parseColor(r.color!),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            r.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  if (_roleChoice == _rolePick &&
                                      value != _rolePick) {
                                    _pickedRoleIds.clear();
                                  }
                                  _roleChoice = value;
                                });
                              },
                            ),
                          ),
                  ),
                  if (_selectedGroup != null &&
                      !_isLoadingRoles &&
                      _roleChoice == _rolePick &&
                      _roles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Označ roly (${_pickedRoleIds.length} vybratých):',
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 200,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F0F0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withAlpha(20)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ListView(
                            primary: false,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: _roles.map((r) {
                            final checked = _pickedRoleIds.contains(r.idRole);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _pickedRoleIds.add(r.idRole);
                                  } else {
                                    _pickedRoleIds.remove(r.idRole);
                                  }
                                });
                              },
                              dense: true,
                              fillColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? const Color(0xFF8B1A2C)
                                    : null,
                              ),
                              checkColor: Colors.white,
                              title: Row(
                                children: [
                                  if (r.color != null)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: _parseColor(r.color!),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      r.name,
                                      style: const TextStyle(
                                        color: Color(0xFF333333),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            );
                          }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 28),

                // Create button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createActivity,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5F0F0),
                      foregroundColor: const Color(0xFF333333),
                      disabledBackgroundColor: const Color(0xFFCCCCCC),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF8B1A2C),
                            ),
                          )
                        : const Text(
                            'Create',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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

  Widget _buildLabel(String text) {
    final textColor = AppColors.textPrimary(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF999999)),
        filled: true,
        fillColor: const Color(0xFFF5F0F0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Color _parseColor(String colorStr) {
    try {
      final hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF8B1A2C);
  }
}
