// Malá dátová trieda pre používateľskú rolu vo vnútri konkrétnej skupiny.
// Obsahuje názov, farbu vizuálnu ako aj zoznam reťazcov oprávnení pre správu skupiny.
// This file was generated using AI (Gemini)




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

  // Tato funkcia nacita objekt z JSON dat.
  // Prevedie prijaty format na interny model.
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
