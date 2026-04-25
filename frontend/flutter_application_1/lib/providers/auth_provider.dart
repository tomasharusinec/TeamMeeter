import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  String? _token;
  User? _user;
  bool _isLoading = true;

  String? get token => _token;
  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _user != null;
  ApiService get apiService => _apiService;

  Future<void> loadSavedToken() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    if (_token != null) {
      _apiService.setToken(_token);
      try {
        _user = await _apiService.getCurrentUser();
        if (_user == null) {
          _token = null;
          _apiService.setToken(null);
          await prefs.remove('auth_token');
        }
      } catch (e) {
        _token = null;
        _apiService.setToken(null);
        await prefs.remove('auth_token');
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.login(username, password);
      _token = response['token'];
      _apiService.setToken(_token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);

      _user = await _apiService.getCurrentUser();
      _user ??= User(username: username);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String firstname,
    required String surname,
    required String username,
    required String password,
    required String email,
    required String birthdate,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.register(
        firstname: firstname,
        surname: surname,
        username: username,
        password: password,
        email: email,
        birthdate: birthdate,
      );

      _token = response['token'];
      _apiService.setToken(_token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);

      _user = await _apiService.getCurrentUser();
      _user ??= User(
        username: username,
        name: firstname,
        surname: surname,
        email: email,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _apiService.setToken(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');

    notifyListeners();
  }
}
