import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/activity.dart';
import '../providers/auth_provider.dart';

class ActivityDetailDialog extends StatefulWidget {
  final Activity activity;
  final VoidCallback? onDeleted;

  const ActivityDetailDialog({
    super.key,
    required this.activity,
    this.onDeleted,
  });

  @override
  State<ActivityDetailDialog> createState() => _ActivityDetailDialogState();
}

class _ActivityDetailDialogState extends State<ActivityDetailDialog> {
  late Activity _activity;
  bool _isLoading = true;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _activity = widget.activity;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final details = await api.getActivityDetails(widget.activity.idActivity);
      if (mounted) {
        setState(() => _activity = details);
      }
    } catch (_) {
      // Fallback to basic data passed from list/calendar.
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteActivity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        title: const Text(
          'Delete activity',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Naozaj chcete túto aktivitu vymazať?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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

    setState(() => _isDeleting = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteActivity(_activity.idActivity);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDeleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktivita bola zmazaná'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B1A2C)),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _activity.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Termín', _activity.formattedDeadline.isEmpty
                      ? 'Bez termínu'
                      : _activity.formattedDeadline),
                  _detailRow('Typ', _activity.groupId == null ? 'Individuálna' : 'Skupinová'),
                  _detailRow('Skupina', _activity.groupName ?? '-'),
                  _detailRow('Vytvoril', _activity.creatorUsername ?? '-'),
                  _detailRow('Popis',
                      (_activity.description?.trim().isNotEmpty ?? false) ? _activity.description! : '-'),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withAlpha(60)),
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
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
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
