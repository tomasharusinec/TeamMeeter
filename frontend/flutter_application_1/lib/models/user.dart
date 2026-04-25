class User {
  final int? idRegistration;
  final String username;
  final String? name;
  final String? surname;
  final String? email;
  final String? birthdate;
  final String? registrationDate;
  final bool hasProfilePicture;

  User({
    this.idRegistration,
    required this.username,
    this.name,
    this.surname,
    this.email,
    this.birthdate,
    this.registrationDate,
    this.hasProfilePicture = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      idRegistration: json['id_registration'],
      username: json['username'],
      name: json['name'],
      surname: json['surname'],
      email: json['email'],
      birthdate: json['birthdate']?.toString(),
      registrationDate: json['registration_date']?.toString(),
      hasProfilePicture: json['has_profile_picture'] ?? false,
    );
  }

  String get displayName {
    if (name != null && surname != null) {
      return '$name $surname';
    }
    return username;
  }

  String get initials {
    if (name != null && surname != null && name!.isNotEmpty && surname!.isNotEmpty) {
      return '${name![0]}${surname![0]}'.toUpperCase();
    }
    return username.isNotEmpty ? username[0].toUpperCase() : 'U';
  }
}
