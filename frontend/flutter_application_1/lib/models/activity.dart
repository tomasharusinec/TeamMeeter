// Dátová trieda aktivity tímu používaná v kalendári aj v skupinových zoznamoch úloh.
// Drží číselný identifikátor, názov, stav, termín aj príznaky offline synchronizácie.
// This file was generated using AI (Gemini)




import 'dart:io';

class Activity {
  final int idActivity;
  final String name;
  final String? description;
  final String? creationDate;
  final String? deadline;
  final String status;
  final int? groupId;
  final String? groupName;
  final String? creatorUsername;
  final bool isLocalOnly;
  final bool hasPendingSync;

  Activity({
    required this.idActivity,
    required this.name,
    this.description,
    this.creationDate,
    this.deadline,
    this.status = 'todo',
    this.groupId,
    this.groupName,
    this.creatorUsername,
    this.isLocalOnly = false,
    this.hasPendingSync = false,
  });

  // Tato funkcia nacita objekt z JSON dat.
  // Prevedie prijaty format na interny model.
  factory Activity.fromJson(Map<String, dynamic> json) {
    final raw = (json['status']?.toString() ?? '').toLowerCase().trim();
    final normalizedStatus = switch (raw) {
      'in_progress' => 'in_progress',
      'completed' => 'completed',
      'todo' => 'todo',
      _ => 'todo',
    };
    return Activity(
      idActivity: json['id_activity'],
      name: json['name'],
      description: json['description'],
      creationDate: json['creation_date']?.toString(),
      deadline: json['deadline']?.toString(),
      status: normalizedStatus,
      groupId: json['group_id'],
      groupName: json['group_name'],
      creatorUsername: json['creator_username'],
    );
  }

  factory Activity.fromCacheJson(Map<String, dynamic> json) {
    return Activity(
      idActivity: json['id_activity'] as int,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      creationDate: json['creation_date']?.toString(),
      deadline: json['deadline']?.toString(),
      status: (json['status']?.toString() ?? 'todo'),
      groupId: json['group_id'] as int?,
      groupName: json['group_name']?.toString(),
      creatorUsername: json['creator_username']?.toString(),
      isLocalOnly: json['is_local_only'] == true,
      hasPendingSync: json['has_pending_sync'] == true,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'id_activity': idActivity,
      'name': name,
      'description': description,
      'creation_date': creationDate,
      'deadline': deadline,
      'status': status,
      'group_id': groupId,
      'group_name': groupName,
      'creator_username': creatorUsername,
      'is_local_only': isLocalOnly,
      'has_pending_sync': hasPendingSync,
    };
  }

  Activity copyWith({
    int? idActivity,
    String? name,
    String? description,
    String? creationDate,
    String? deadline,
    String? status,
    int? groupId,
    String? groupName,
    String? creatorUsername,
    bool? isLocalOnly,
    bool? hasPendingSync,
  }) {
    return Activity(
      idActivity: idActivity ?? this.idActivity,
      name: name ?? this.name,
      description: description ?? this.description,
      creationDate: creationDate ?? this.creationDate,
      deadline: deadline ?? this.deadline,
      status: status ?? this.status,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
      hasPendingSync: hasPendingSync ?? this.hasPendingSync,
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
