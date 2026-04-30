import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/group.dart';
import '../models/role.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

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
  final _nameController = TextEditingController();
  DateTime? _selectedDeadline;
  Group? _selectedGroup;
  Role? _selectedRole;
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
          _selectedRole = null;
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF8B1A2C),
              onPrimary: Colors.white,
              surface: Color(0xFF1A0A0A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1A0A0A),
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
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF8B1A2C),
                onPrimary: Colors.white,
                surface: Color(0xFF1A0A0A),
                onSurface: Colors.white,
              ),
              dialogTheme: const DialogThemeData(
                backgroundColor: Color(0xFF1A0A0A),
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
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final deadlineStr = _selectedDeadline?.toUtc().toIso8601String();

      if (_selectedGroup != null) {
        // Group activity
        final result = await api.createGroupActivity(
          groupId: _selectedGroup!.idGroup,
          name: name,
          deadline: deadlineStr,
        );
        // Assign role if selected
        if (_selectedRole != null && result['activity_id'] != null) {
          try {
            await api.assignActivityRole(
              result['activity_id'],
              _selectedRole!.idRole,
            );
          } catch (_) {
            // Role assignment is optional, don't fail the whole creation
          }
        }
        final queued = result['queued'] == true;
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
          border: Border.all(color: Colors.white.withAlpha(26)),
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
                          _selectedRole = null;
                          _roles = [];
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
                            child: DropdownButton<Role?>(
                              value: _selectedRole,
                              isExpanded: true,
                              hint: const Text(
                                'Žiadna rola',
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
                                const DropdownMenuItem<Role?>(
                                  value: null,
                                  child: Text('Žiadna rola'),
                                ),
                                ..._roles.map(
                                  (r) => DropdownMenuItem<Role?>(
                                    value: r,
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
                                        Text(r.name),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (role) =>
                                  setState(() => _selectedRole = role),
                            ),
                          ),
                  ),
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
