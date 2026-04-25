class Group {
  final int idGroup;
  final String name;
  final String? createDate;
  final bool hasIcon;
  final int? conversationId;

  Group({
    required this.idGroup,
    required this.name,
    this.createDate,
    this.hasIcon = false,
    this.conversationId,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      idGroup: json['id_group'],
      name: json['name'],
      createDate: json['create_date']?.toString(),
      hasIcon: json['has_icon'] ?? false,
      conversationId: json['conversation_id'],
    );
  }
}
