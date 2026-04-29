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
    return Role(
      idRole: json['id_role'],
      name: json['name'],
      color: json['color'],
      permissions: (json['permissions'] as List?)
              ?.map((p) => p.toString())
              .toList() ??
          const [],
    );
  }
}
