import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/activity.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

class ActivityDetailDialog extends StatefulWidget {
  final Activity activity;
  final VoidCallback? onDeleted;
  final VoidCallback? onUpdated;

  const ActivityDetailDialog({
    super.key,
    required this.activity,
    this.onDeleted,
    this.onUpdated,
  });

  @override
  State<ActivityDetailDialog> createState() => _ActivityDetailDialogState();
}

class _ActivityDetailDialogState extends State<ActivityDetailDialog> {
  late Activity _activity;
  bool _isLoading = true;
  bool _canEditFull = false;
  bool _resolvingEditPermission = true;

  bool _isEditing = false;
  bool _isDeleting = false;
  bool _isMarkingCompleted = false;
  bool _isSaving = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _editStatus = 'todo';
  DateTime? _editDeadline;

  @override
  void initState() {
    super.initState();
    _activity = widget.activity;
    _loadDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final details = await api.getActivityDetails(widget.activity.idActivity);
      if (mounted) setState(() => _activity = details);
    } catch (_) {}
    finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    if (mounted) await _refreshEditPermission();
  }

  Future<void> _refreshEditPermission() async {
    setState(() => _resolvingEditPermission = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final api = auth.apiService;
      final user = auth.user;
      if (user == null || user.idRegistration == null) {
        if (mounted) {
          setState(() {
            _canEditFull = false;
            _resolvingEditPermission = false;
          });
        }
        return;
      }
      final uid = user.idRegistration!;
      final ok = await api.canUserFullyEditActivity(
        activity: _activity,
        userId: uid,
        username: user.username,
      );
      if (mounted) {
        setState(() {
          _canEditFull = ok;
          _resolvingEditPermission = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _canEditFull = false;
          _resolvingEditPermission = false;
        });
      }
    }
  }

  void _enterEditMode() {
    _nameController.text = _activity.name;
    _descriptionController.text = _activity.description ?? '';
    _editStatus = _activity.status;
    _editDeadline = _activity.parsedDeadline;
    setState(() => _isEditing = true);
  }

  void _leaveEditMode() {
    setState(() => _isEditing = false);
  }

  String _editDeadlineLabel() {
    final dt = _editDeadline;
    if (dt == null) return 'Nastaviť termín';
    return Activity(
      idActivity: _activity.idActivity,
      name: _activity.name,
      deadline: dt.toUtc().toIso8601String(),
    ).formattedDeadline;
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _editDeadline ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 6),
      builder: (pickerCtx, child) =>
          Theme(data: Theme.of(pickerCtx), child: child!),
    );
    if (!mounted || pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _editDeadline != null
          ? TimeOfDay.fromDateTime(_editDeadline!)
          : TimeOfDay.now(),
    );
    if (!mounted || pickedTime == null) return;
    setState(() {
      _editDeadline = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _saveEdits() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: const Text('Zadaj názov aktivity'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final synced = await api.updateActivity(
        activityId: _activity.idActivity,
        name: name,
        description: _descriptionController.text,
        deadline: _editDeadline?.toUtc().toIso8601String(),
        status: _editStatus,
      );
      if (!mounted) return;
      await _loadDetails();
      if (!mounted) return;
      setState(() => _isEditing = false);
      widget.onUpdated?.call();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Aktivita bola uložená'
                : 'Uložené offline. Po pripojení sa zmeny odošlú.',
          ),
          backgroundColor:
              synced ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteActivity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(context),
        title: Text(
          'Delete activity',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Naozaj chcete túto aktivitu vymazať?',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isDeleting = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final confirmedOnServer = await api.deleteActivity(_activity.idActivity);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDeleted?.call();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            confirmedOnServer
                ? 'Aktivita bola zmazaná'
                : 'Aktivita odstránená lokálne. Po pripojení sa zmazanie dokonči na serveri.',
          ),
          backgroundColor:
              confirmedOnServer ? Color(0xFF2E7D32) : Color(0xFFEF6C00),
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
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _markAsCompleted() async {
    setState(() => _isMarkingCompleted = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.updateActivityStatus(_activity.idActivity, 'completed');
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDeleted?.call();
      widget.onUpdated?.call();
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Aktivita bola označená ako vybavená'),
          backgroundColor: Color(0xFF2E7D32),
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
      if (mounted) setState(() => _isMarkingCompleted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    return Dialog(
      backgroundColor: AppColors.dialogBackground(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _isLoading
              ? const SizedBox(
                  height: 120,
                  child: Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF8B1A2C)),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isEditing) ...[
                        Text(
                          'Upraviť aktivitu',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Názov',
                            border: OutlineInputBorder(),
                          ),
                          style: TextStyle(color: textPrimary),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Popis (voliteľné)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 4,
                          style: TextStyle(color: textPrimary),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Stav',
                            border: OutlineInputBorder(),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _editStatus,
                              isExpanded: true,
                              dropdownColor:
                                  AppColors.dialogBackground(context),
                              style: TextStyle(color: textPrimary),
                              items: [
                                DropdownMenuItem(
                                  value: 'todo',
                                  child: Text(
                                    'To-do',
                                    style: TextStyle(color: textPrimary),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'in_progress',
                                  child: Text(
                                    'In progress',
                                    style: TextStyle(color: textPrimary),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'completed',
                                  child: Text(
                                    'Vybavené',
                                    style: TextStyle(color: textPrimary),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _editStatus = v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickDeadline,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(_editDeadlineLabel()),
                        ),
                      ] else ...[
                        Text(
                          _activity.name,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _detailRow(
                          'Termín',
                          _activity.formattedDeadline.isEmpty
                              ? 'Bez termínu'
                              : _activity.formattedDeadline,
                        ),
                        _detailRow('Stav', () {
                          final s = _activity.status;
                          if (s == 'todo') return 'To-do';
                          if (s == 'in_progress') return 'In progress';
                          if (s == 'completed') return 'Vybavené';
                          return s;
                        }()),
                        _detailRow(
                          'Typ',
                          _activity.groupId == null
                              ? 'Individuálna'
                              : 'Skupinová',
                        ),
                        _detailRow('Skupina', _activity.groupName ?? '-'),
                        _detailRow('Vytvoril', _activity.creatorUsername ?? '-'),
                        _detailRow(
                          'Popis',
                          (_activity.description?.trim().isNotEmpty ?? false)
                              ? _activity.description!
                              : '-',
                        ),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton(
                            onPressed: _isEditing
                                ? (_isSaving ? null : _leaveEditMode)
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppColors.outlineStrong(context),
                              ),
                              foregroundColor: AppColors.textMuted(context),
                            ),
                            child: Text(_isEditing ? 'Zrušiť úpravu' : 'Close'),
                          ),
                          if (_isEditing) ...[
                            ElevatedButton(
                              onPressed: _isSaving ? null : _saveEdits,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B1A2C),
                                foregroundColor: Colors.white,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Uložiť'),
                            ),
                          ] else ...[
                            if (!_resolvingEditPermission && _canEditFull)
                              ElevatedButton.icon(
                                onPressed: _enterEditMode,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Upraviť'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3949AB),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            if (_activity.status != 'completed')
                              ElevatedButton(
                                onPressed: _isMarkingCompleted
                                    ? null
                                    : _markAsCompleted,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  foregroundColor: Colors.white,
                                ),
                                child: _isMarkingCompleted
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Mark as done'),
                              ),
                            ElevatedButton(
                              onPressed: _isDeleting ? null : _deleteActivity,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B1A2C),
                                foregroundColor: Colors.white,
                              ),
                              child: _isDeleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Delete'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: textSecondary, fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style:
                  TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
