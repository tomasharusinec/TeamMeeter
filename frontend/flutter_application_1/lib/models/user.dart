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

  factory User.fromCacheJson(Map<String, dynamic> json) {
    return User(
      idRegistration: json['id_registration'] as int?,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      surname: json['surname']?.toString(),
      email: json['email']?.toString(),
      birthdate: json['birthdate']?.toString(),
      registrationDate: json['registration_date']?.toString(),
      hasProfilePicture: json['has_profile_picture'] == true,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'id_registration': idRegistration,
      'username': username,
      'name': name,
      'surname': surname,
      'email': email,
      'birthdate': birthdate,
      'registration_date': registrationDate,
      'has_profile_picture': hasProfilePicture,
    };
  }

  String get displayName {
    if (name != null && surname != null) {
      return '$name $surname';
    }
    return username;
  }

  String get initials {
    if (name != null &&
        surname != null &&
        name!.isNotEmpty &&
        surname!.isNotEmpty) {
      return '${name![0]}${surname![0]}'.toUpperCase();
    }
    return username.isNotEmpty ? username[0].toUpperCase() : 'U';
  }
}
