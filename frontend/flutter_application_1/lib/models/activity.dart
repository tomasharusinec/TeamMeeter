import 'dart:io';

class Activity {
  final int idActivity;
  final String name;
  final String? description;
  final String? creationDate;
  final String? deadline;
  final int? groupId;
  final String? groupName;
  final String? creatorUsername;

  Activity({
    required this.idActivity,
    required this.name,
    this.description,
    this.creationDate,
    this.deadline,
    this.groupId,
    this.groupName,
    this.creatorUsername,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      idActivity: json['id_activity'],
      name: json['name'],
      description: json['description'],
      creationDate: json['creation_date']?.toString(),
      deadline: json['deadline']?.toString(),
      groupId: json['group_id'],
      groupName: json['group_name'],
      creatorUsername: json['creator_username'],
    );
  }

  DateTime? get parsedDeadline => parseFlexibleDate(deadline);

  String get formattedDeadline {
    final dt = parsedDeadline;
    if (dt == null) return deadline ?? '';
    final datePart =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final hasTime = dt.hour != 0 || dt.minute != 0;
    if (!hasTime) return datePart;
    final timePart =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$datePart $timePart';
  }

  static DateTime? parseFlexibleDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return null;
    try {
      return DateTime.parse(rawDate).toLocal();
    } catch (_) {
      try {
        return HttpDate.parse(rawDate).toLocal();
      } catch (_) {
        return null;
      }
    }
  }
}
