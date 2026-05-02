import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/teammeeter_analytics.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  static const String _tokenKey = 'auth_token';
  static const String _userCacheKey = 'auth_user_cache_v1';
  static const String _localProfilePhotoPathKey = 'local_profile_photo_path_v1';
  static const String _localProfilePhotoRemovedKey =
      'local_profile_photo_removed_v1';
  String? _token;
  User? _user;
  String? _localProfilePhotoPath;
  bool _localProfilePhotoRemoved = false;
  bool _isLoading = false;
  bool _isInitializing = true;

  String? get token => _token;
  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _token != null && _user != null;
  String? get localProfilePhotoPath => _localProfilePhotoPath;
  bool get localProfilePhotoRemoved => _localProfilePhotoRemoved;
  ApiService get apiService => _apiService;

  User _copyUserWithPicture(User source, bool hasProfilePicture) {
    return User(
      idRegistration: source.idRegistration,
      username: source.username,
      name: source.name,
      surname: source.surname,
      email: source.email,
      birthdate: source.birthdate,
      registrationDate: source.registrationDate,
      hasProfilePicture: hasProfilePicture,
    );
  }

  bool _isConnectivityError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('cannot reach') ||
        msg.contains('connection refused') ||
        msg.contains('timed out');
  }

  Future<User?> _loadCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromCacheJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userCacheKey, jsonEncode(user.toCacheJson()));
  }

  Future<void> loadSavedToken() async {
    _isInitializing = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _localProfilePhotoPath = prefs.getString(_localProfilePhotoPathKey);
    _localProfilePhotoRemoved =
        prefs.getBool(_localProfilePhotoRemovedKey) ?? false;
    if (_token != null) {
      _apiService.setToken(_token);
      _user = await _loadCachedUser();
      _apiService.setCacheNamespace(
        _user?.idRegistration.toString() ?? _user?.username,
      );
      try {
        final remoteUser = await _apiService.getCurrentUser();
        if (remoteUser != null) {
          _user = remoteUser;
          _apiService.setCacheNamespace(
            remoteUser.idRegistration.toString(),
          );
          await _saveCachedUser(remoteUser);
          _localProfilePhotoPath = null;
          _localProfilePhotoRemoved = false;
          await prefs.remove(_localProfilePhotoPathKey);
          await prefs.remove(_localProfilePhotoRemovedKey);
        } else if (_user == null) {
          _token = null;
          _apiService.setToken(null);
          await prefs.remove(_tokenKey);
          await prefs.remove(_userCacheKey);
          await prefs.remove(_localProfilePhotoPathKey);
          await prefs.remove(_localProfilePhotoRemovedKey);
        }
      } catch (e) {
        if (!_isConnectivityError(e) && _user == null) {
          _token = null;
          _apiService.setToken(null);
          await prefs.remove(_tokenKey);
          await prefs.remove(_userCacheKey);
          await prefs.remove(_localProfilePhotoPathKey);
          await prefs.remove(_localProfilePhotoRemovedKey);
        }
      }
    }
    if (_user != null) {
      final id = _user!.idRegistration.toString();
      await TeamMeeterAnalytics.instance.setUserId(id);
    }
    _isInitializing = false;
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
      await prefs.setString(_tokenKey, _token!);

      _user = await _apiService.getCurrentUser();
      _user ??= User(username: username);
      if (_user != null) {
        _apiService.setCacheNamespace(
          _user!.idRegistration.toString(),
        );
        await _saveCachedUser(_user!);
      }
      await TeamMeeterAnalytics.instance.setUserId(
        _user?.idRegistration.toString(),
      );
      await TeamMeeterAnalytics.instance.logLogin(method: 'email');
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
      await prefs.setString(_tokenKey, _token!);

      _user = await _apiService.getCurrentUser();
      _user ??= User(
        username: username,
        name: firstname,
        surname: surname,
        email: email,
      );
      if (_user != null) {
        _apiService.setCacheNamespace(
          _user!.idRegistration.toString(),
        );
        await _saveCachedUser(_user!);
      }
      await TeamMeeterAnalytics.instance.setUserId(
        _user?.idRegistration.toString(),
      );
      await TeamMeeterAnalytics.instance.logSignUp(method: 'email');
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loginWithGoogleIdToken(String idToken) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.loginWithGoogle(idToken);
      _token = response['token'];
      _apiService.setToken(_token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);

      _user = await _apiService.getCurrentUser();
      if (_user != null) {
        _apiService.setCacheNamespace(_user!.idRegistration.toString());
        await _saveCachedUser(_user!);
      }
      await TeamMeeterAnalytics.instance.setUserId(
        _user?.idRegistration.toString(),
      );
      await TeamMeeterAnalytics.instance.logLogin(method: 'google');
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
    _apiService.setCacheNamespace(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userCacheKey);
    await prefs.remove(_localProfilePhotoPathKey);
    await prefs.remove(_localProfilePhotoRemovedKey);
    _localProfilePhotoPath = null;
    _localProfilePhotoRemoved = false;

    await TeamMeeterAnalytics.instance.clearUser();
    await TeamMeeterAnalytics.instance.logLogout();

    notifyListeners();
  }

  Future<void> ensureCurrentUserLoaded() async {
    if (_token == null || _user != null) return;
    try {
      final loadedUser = await _apiService.getCurrentUser();
      if (loadedUser != null) {
        _user = loadedUser;
        _apiService.setCacheNamespace(
          loadedUser.idRegistration.toString(),
        );
        await _saveCachedUser(loadedUser);
        final prefs = await SharedPreferences.getInstance();
        _localProfilePhotoPath = null;
        _localProfilePhotoRemoved = false;
        await prefs.remove(_localProfilePhotoPathKey);
        await prefs.remove(_localProfilePhotoRemovedKey);
        notifyListeners();
      }
    } catch (e) {
      if (_isConnectivityError(e) && _user == null) {
        _user = await _loadCachedUser();
        if (_user != null) {
          notifyListeners();
        }
      }
    }
  }

  Future<void> refreshCurrentUser() async {
    if (_token == null) return;
    try {
      final loadedUser = await _apiService.getCurrentUser();
      if (loadedUser != null) {
        _user = loadedUser;
        _apiService.setCacheNamespace(
          loadedUser.idRegistration.toString(),
        );
        await _saveCachedUser(loadedUser);
        final prefs = await SharedPreferences.getInstance();
        _localProfilePhotoPath = null;
        _localProfilePhotoRemoved = false;
        await prefs.remove(_localProfilePhotoPathKey);
        await prefs.remove(_localProfilePhotoRemovedKey);
        notifyListeners();
      }
    } catch (e) {
      if (_isConnectivityError(e)) {
        final cached = await _loadCachedUser();
        if (cached != null) {
          _user = cached;
          notifyListeners();
        }
        return;
      }
      rethrow;
    }
  }

  Future<void> setLocalProfilePhotoPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    _localProfilePhotoPath = path;
    _localProfilePhotoRemoved = false;
    await prefs.setString(_localProfilePhotoPathKey, path);
    await prefs.setBool(_localProfilePhotoRemovedKey, false);
    if (_user != null && !_user!.hasProfilePicture) {
      _user = _copyUserWithPicture(_user!, true);
      await _saveCachedUser(_user!);
    }
    notifyListeners();
  }

  Future<void> markLocalProfilePhotoRemoved() async {
    final prefs = await SharedPreferences.getInstance();
    _localProfilePhotoPath = null;
    _localProfilePhotoRemoved = true;
    await prefs.remove(_localProfilePhotoPathKey);
    await prefs.setBool(_localProfilePhotoRemovedKey, true);
    if (_user != null && _user!.hasProfilePicture) {
      _user = _copyUserWithPicture(_user!, false);
      await _saveCachedUser(_user!);
    }
    notifyListeners();
  }
}
