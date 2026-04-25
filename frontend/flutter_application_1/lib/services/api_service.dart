import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/group.dart';
import '../models/activity.dart';

class ApiService {
  static const String baseUrl = 'http://147.175.160.232:5000';

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/authorization/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Prihlásenie zlyhalo');
    }
  }

  Future<Map<String, dynamic>> register({
    required String firstname,
    required String surname,
    required String username,
    required String password,
    required String email,
    required String birthdate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/authorization/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firstname': firstname,
        'surname': surname,
        'username': username,
        'password': password,
        'email': email,
        'birthdate': birthdate,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Registrácia zlyhala');
    }
  }

  Future<User?> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body)['user']);
    }
    return null;
  }

  Future<List<Group>> getGroups() async {
    final response = await http.get(
      Uri.parse('$baseUrl/groups/'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['groups'] as List).map((g) => Group.fromJson(g)).toList();
    }
    return [];
  }

  Future<List<Activity>> getMyActivities() async {
    final response = await http.get(
      Uri.parse('$baseUrl/activities/me'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['activities'] as List)
          .map((a) => Activity.fromJson(a))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createGroup(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Nepodarilo sa vytvoriť skupinu');
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['notifications']);
    }
    return [];
  }
}
