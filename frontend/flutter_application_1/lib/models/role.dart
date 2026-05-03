class Role {
  final int idRole;
  final String name;
  final String? color;
  final List<String> permissions;

  Role({
    required this.idRole,
    required this.name,
    this.color,
    this.permissions = const [],
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    final rawId = json['id_role'];
    final idRole = rawId is int
        ? rawId
        : rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final nameRaw = json['name'];
    final name = nameRaw?.toString() ?? '';
    final colorRaw = json['color'];
    final List<String> perms;
    final plist = json['permissions'];
    if (plist is List) {
      perms = plist.map((p) => p.toString()).toList();
    } else {
      perms = const [];
    }
    return Role(
      idRole: idRole,
      name: name,
      color: colorRaw?.toString(),
      permissions: perms,
    );
  }
}
