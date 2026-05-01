import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';
import 'activity_detail_dialog.dart';

class GroupActivitiesScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupActivitiesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupActivitiesScreen> createState() => _GroupActivitiesScreenState();
}

class _GroupActivitiesScreenState extends State<GroupActivitiesScreen> {
  List<Activity> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final activities = await api.getGroupActivities(widget.groupId);
      if (!mounted) return;
      setState(() => _activities = activities);
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

  String _statusLabel(String status) {
    if (status == 'in_progress') return 'In progress';
    if (status == 'completed') return 'Completed';
    return 'To-do';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} activities'),
        centerTitle: true,
        backgroundColor: AppColors.dialogBackground(context),
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
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : RefreshIndicator(
                onRefresh: _loadActivities,
                color: const Color(0xFF8B1A2C),
                child: _activities.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          SizedBox(height: 120),
                          Icon(
                            Icons.playlist_add_check_circle_outlined,
                            size: 64,
                            color: Colors.white38,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'V tejto skupine zatiaľ nie sú žiadne aktivity',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _activities.length,
                        itemBuilder: (context, index) {
                          final activity = _activities[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A0A0A).withAlpha(200),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withAlpha(16)),
                            ),
                            child: ListTile(
                              onTap: () async {
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => ActivityDetailDialog(
                                    activity: activity,
                                    onDeleted: _loadActivities,
                                  ),
                                );
                                if (!mounted) return;
                                await _loadActivities();
                              },
                              title: Text(
                                activity.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'Stav: ${_statusLabel(activity.status)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    activity.formattedDeadline.isEmpty
                                        ? 'Bez termínu'
                                        : activity.formattedDeadline,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white38,
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
