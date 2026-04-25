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
}
