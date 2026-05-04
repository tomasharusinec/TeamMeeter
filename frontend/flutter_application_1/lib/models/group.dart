// Jednoduchý model skupiny tímu používaný pri zobrazení a volaniach rozhrania.
// Väčšinu polí mapuje zo servera aby sa dala skupina prehliadať a upravovať.
// This file was generated using AI (Gemini)




class Group {
  final int idGroup;
  final String name;
  final int capacity;
  final String? createDate;
  final bool hasIcon;
  final int? conversationId;
  final String? qrCode;
  final bool isLocalOnly;
  final bool hasPendingSync;

  Group({
    required this.idGroup,
    required this.name,
    required this.capacity,
    this.createDate,
    this.hasIcon = false,
    this.conversationId,
    this.qrCode,
    this.isLocalOnly = false,
    this.hasPendingSync = false,
  });

  // Tato funkcia nacita objekt z JSON dat.
  // Prevedie prijaty format na interny model.
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

  factory Group.fromCacheJson(Map<String, dynamic> json) {
    return Group(
      idGroup: json['id_group'] as int,
      name: json['name']?.toString() ?? '',
      capacity: json['capacity'] as int? ?? 10,
      createDate: json['create_date']?.toString(),
      hasIcon: json['has_icon'] == true,
      conversationId: json['conversation_id'] as int?,
      qrCode: json['qr_code']?.toString(),
      isLocalOnly: json['is_local_only'] == true,
      hasPendingSync: json['has_pending_sync'] == true,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'id_group': idGroup,
      'name': name,
      'capacity': capacity,
      'create_date': createDate,
      'has_icon': hasIcon,
      'conversation_id': conversationId,
      'qr_code': qrCode,
      'is_local_only': isLocalOnly,
      'has_pending_sync': hasPendingSync,
    };
  }

  Group copyWith({
    int? idGroup,
    String? name,
    int? capacity,
    String? createDate,
    bool? hasIcon,
    int? conversationId,
    String? qrCode,
    bool? isLocalOnly,
    bool? hasPendingSync,
  }) {
    return Group(
      idGroup: idGroup ?? this.idGroup,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      createDate: createDate ?? this.createDate,
      hasIcon: hasIcon ?? this.hasIcon,
      conversationId: conversationId ?? this.conversationId,
      qrCode: qrCode ?? this.qrCode,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
      hasPendingSync: hasPendingSync ?? this.hasPendingSync,
    );
  }
}
