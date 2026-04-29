class Group {
  final int idGroup;
  final String name;
  final int capacity;
  final String? createDate;
  final bool hasIcon;
  final int? conversationId;
  final String? qrCode;

  Group({
    required this.idGroup,
    required this.name,
    required this.capacity,
    this.createDate,
    this.hasIcon = false,
    this.conversationId,
    this.qrCode,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      idGroup: json['id_group'],
      name: json['name'],
      capacity: json['capacity'] ?? 10,
      createDate: json['create_date']?.toString(),
      hasIcon: json['has_icon'] ?? false,
      conversationId: json['conversation_id'],
      qrCode: json['qr_code']?.toString(),
    );
  }
}
