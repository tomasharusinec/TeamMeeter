import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../models/activity.dart';
import '../models/group.dart';
import 'activity_detail_dialog.dart';
import 'create_activity_dialog.dart';

class CalendarScreen extends StatefulWidget {
  final List<Group> groups;
  final VoidCallback? onDataChanged;

  const CalendarScreen({super.key, required this.groups, this.onDataChanged});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Activity> _activities = [];
  bool _isLoading = true;
  late DateTime _displayedMonth;
  int _weekIndex = 0;
  Timer? _clockRefreshTimer;

  static const _dayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month, 1);
    _weekIndex = _findWeekIndexForDate(now, _getWeeksForMonth(_displayedMonth));
    _loadActivities();
    _clockRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    final shouldShowBlockingLoader = _activities.isEmpty;
    if (shouldShowBlockingLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final activities = await api.getMyActivities();
      if (mounted) {
        setState(() => _activities = activities);
      }
    } catch (e) {
      // show empty state
    } finally {
      if (mounted && shouldShowBlockingLoader) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<DateTime> _getWeeksForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstMonday = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    final nextMonthFirst = DateTime(month.year, month.month + 1, 1);
    final lastDay = nextMonthFirst.subtract(const Duration(days: 1));
    final lastSunday = lastDay.add(Duration(days: 7 - lastDay.weekday));

    final weeks = <DateTime>[];
    var weekStart = DateTime(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day,
    );
    while (!weekStart.isAfter(lastSunday)) {
      final weekEnd = weekStart.add(const Duration(days: 6));
      final hasDayInMonth =
          !(weekEnd.isBefore(firstDay) || weekStart.isAfter(lastDay));
      if (hasDayInMonth) {
        weeks.add(weekStart);
      }
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return weeks;
  }

  int _findWeekIndexForDate(DateTime date, List<DateTime> weeks) {
    for (var i = 0; i < weeks.length; i++) {
      final start = weeks[i];
      final end = start.add(const Duration(days: 6));
      if (!date.isBefore(start) && !date.isAfter(end)) {
        return i;
      }
    }
    return 0;
  }

  DateTime _currentWeekStart(List<DateTime> weeks) {
    final safeIndex = _weekIndex.clamp(0, weeks.length - 1);
    return weeks[safeIndex];
  }

  void _changeMonth(int delta) {
    final candidate = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + delta,
      1,
    );
    final weeks = _getWeeksForMonth(candidate);
    final now = DateTime.now();
    final targetWeekIndex =
        now.year == candidate.year && now.month == candidate.month
        ? _findWeekIndexForDate(now, weeks)
        : 0;

    setState(() {
      _displayedMonth = candidate;
      _weekIndex = targetWeekIndex;
    });
  }

  void _changeWeek(int delta) {
    final weeks = _getWeeksForMonth(_displayedMonth);
    final nextIndex = _weekIndex + delta;

    if (nextIndex < 0) {
      final prevMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
        1,
      );
      final prevWeeks = _getWeeksForMonth(prevMonth);
      setState(() {
        _displayedMonth = prevMonth;
        _weekIndex = prevWeeks.length - 1;
      });
      return;
    }

    if (nextIndex >= weeks.length) {
      final nextMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      );
      setState(() {
        _displayedMonth = nextMonth;
        _weekIndex = 0;
      });
      return;
    }

    setState(() => _weekIndex = nextIndex);
  }

  /// Compute the ISO week number
  int _getWeekNumber(DateTime date) {
    // ISO 8601: week starts Monday, week 1 contains Jan 4
    final jan4 = DateTime(date.year, 1, 4);
    final jan4Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final diff = date.difference(jan4Monday).inDays;
    return (diff / 7).floor() + 1;
  }

  /// Get activities for a specific day
  List<Activity> _getActivitiesForDay(DateTime day) {
    final now = DateTime.now();
    return _activities.where((a) {
      if (a.status == 'completed') return false;
      final deadline = a.parsedDeadline;
      if (deadline == null) return false;
      if (!deadline.isAfter(now)) return false;
      return deadline.year == day.year &&
          deadline.month == day.month &&
          deadline.day == day.day;
    }).toList();
  }

  void _showCreateActivityDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateActivityDialog(
        groups: widget.groups,
        onActivityCreated: () {
          _loadActivities();
          widget.onDataChanged?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthWeeks = _getWeeksForMonth(_displayedMonth);
    final weekStart = _currentWeekStart(monthWeeks);
    final weekNumber = _getWeekNumber(weekStart);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadActivities,
          color: const Color(0xFF8B1A2C),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),

                // Week navigation
                _buildWeekNavigation(
                  weekNumber: weekNumber,
                  monthLabel: _formatMonthYear(_displayedMonth),
                ),

                const SizedBox(height: 16),

                // Day rows
                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: CircularProgressIndicator(
                      color: AppColors.circularProgressOnBackground(context),
                    ),
                  )
                else
                  ...List.generate(7, (i) {
                    final day = weekStart.add(Duration(days: i));
                    final dayActivities = _getActivitiesForDay(day);
                    final isToday = _isToday(day);
                    return _buildDayRow(
                      _dayLabels[i],
                      day,
                      dayActivities,
                      isToday,
                    );
                  }),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),

        // FAB
        Positioned(right: 20, bottom: 20, child: _buildFab()),
      ],
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  String _formatMonthYear(DateTime month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }

  String _formatDayDate(DateTime day) {
    return '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
  }

  Widget _buildWeekNavigation({
    required int weekNumber,
    required String monthLabel,
  }) {
    final isDarkMode = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.calendarWeekNavBackground(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.calendarWeekNavBorder(context)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: Icon(
                  Icons.keyboard_double_arrow_left,
                  color: AppColors.calendarNavIcon(context),
                ),
                splashRadius: 20,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF2D1515)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.calendarDayBadgeNonTodayBorder(context),
                  ),
                ),
                child: Text(
                  monthLabel,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: Icon(
                  Icons.keyboard_double_arrow_right,
                  color: AppColors.calendarNavIcon(context),
                ),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _changeWeek(-1),
                icon: Icon(
                  Icons.chevron_left,
                  color: AppColors.calendarNavIcon(context),
                ),
                splashRadius: 20,
              ),
              GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  final month = DateTime(now.year, now.month, 1);
                  final weeks = _getWeeksForMonth(month);
                  setState(() {
                    _displayedMonth = month;
                    _weekIndex = _findWeekIndexForDate(now, weeks);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF2D1515)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.calendarDayBadgeNonTodayBorder(context),
                    ),
                  ),
                  child: Text(
                    'Week: $weekNumber',
                    style: TextStyle(
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1A1A1A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeWeek(1),
                icon: Icon(
                  Icons.chevron_right,
                  color: AppColors.calendarNavIcon(context),
                ),
                splashRadius: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow(
    String label,
    DateTime day,
    List<Activity> activities,
    bool isToday,
  ) {
    final isDark = AppColors.isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Day label badge
          Container(
            width: 56,
            height: 38,
            decoration: BoxDecoration(
              color: isToday
                  ? const Color(0xFF8B1A2C)
                  : AppColors.calendarDayBadgeNonToday(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isToday
                    ? const Color(0xFFE57373)
                    : AppColors.calendarDayBadgeNonTodayBorder(context),
              ),
              boxShadow: isToday
                  ? [
                      BoxShadow(
                        color: const Color(0xFF8B1A2C).withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isToday
                          ? Colors.white
                          : (isDark
                              ? Colors.white70
                              : const Color(0xFF424242)),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _formatDayDate(day),
                    style: TextStyle(
                      color: isToday
                          ? Colors.white
                          : (isDark
                              ? Colors.white54
                              : const Color(0xFF616161)),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Activity area
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0F0),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(30),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: activities.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: activities.map((a) {
                        final formattedTime = _formatTime(a);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: GestureDetector(
                            onTap: () => _showActivityDetail(a),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF8B1A2C),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    a.name,
                                    style: const TextStyle(
                                      color: Color(0xFF333333),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (formattedTime.isNotEmpty)
                                  Text(
                                    formattedTime,
                                    style: const TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(Activity activity) {
    final dt = activity.parsedDeadline;
    if (dt == null || (dt.hour == 0 && dt.minute == 0)) {
      return '';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildFab() {
    return GestureDetector(
      onTap: _showCreateActivityDialog,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFF5F0F0),
          border: Border.all(
            color: AppColors.calendarFabBorder(context),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Color(0xFF333333), size: 30),
      ),
    );
  }

  void _showActivityDetail(Activity activity) {
    showDialog(
      context: context,
      builder: (context) => ActivityDetailDialog(
        activity: activity,
        onDeleted: () {
          _loadActivities();
          widget.onDataChanged?.call();
        },
      ),
    );
  }
}
