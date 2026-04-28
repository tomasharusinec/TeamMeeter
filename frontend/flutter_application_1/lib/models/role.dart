class Role {
  final int idRole;
  final String name;
  final String? color;

  Role({
    required this.idRole,
    required this.name,
    this.color,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      idRole: json['id_role'],
      name: json['name'],
      color: json['color'],
    );
  }
}
