import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/group.dart';
import '../models/activity.dart';

class ApiService {
  static const String baseUrl = 'http://10.229.79.149:5000';

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Exception _buildApiException(http.Response response, String fallbackMessage) {
    try {
      final body = jsonDecode(response.body);
      return Exception(body['message'] ?? fallbackMessage);
    } catch (_) {
      return Exception(fallbackMessage);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/authorization/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 401) {
      throw Exception('Wrong credentials');
    }
    final body = jsonDecode(response.body);
    throw Exception(body['message'] ?? 'Prihlásenie zlyhalo');
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
    throw _buildApiException(response, 'Nepodarilo sa načítať skupiny');
  }

  Future<Group> getGroupDetails(int groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/groups/$groupId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Group.fromJson(data['group']);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať skupinu');
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(int groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/groups/$groupId/members'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['members']);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať členov skupiny');
  }

  Future<void> addGroupMember({
    required int groupId,
    required String username,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$groupId/members'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa pridať člena');
    }
  }

  Future<void> removeGroupMember({
    required int groupId,
    required int userId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/groups/$groupId/members/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa odstrániť člena');
    }
  }

  Future<List<Map<String, dynamic>>> getGroupRoles(int groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/roles/groups/$groupId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['roles']);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať roly');
  }

  Future<Map<String, dynamic>> getConversation(int conversationId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Map<String, dynamic>.from(data['conversation']);
    }
    throw _buildApiException(response, 'Nepodarilo sa načítať chat');
  }

  Future<void> deleteGroup(int groupId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/groups/$groupId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa zmazať skupinu');
    }
  }

  Future<void> updateGroup({
    required int groupId,
    String? name,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/groups/$groupId'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
      }),
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa upraviť skupinu');
    }
  }

  Future<void> uploadGroupIcon({
    required int groupId,
    required File imageFile,
  }) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/groups/$groupId/icon'),
    );
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa nahrať ikonu skupiny');
    }
  }

  Future<void> deleteGroupIcon(int groupId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/groups/$groupId/icon'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw _buildApiException(response, 'Nepodarilo sa odstrániť ikonu skupiny');
    }
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
    }
    throw _buildApiException(response, 'Nepodarilo sa vytvoriť skupinu');
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
