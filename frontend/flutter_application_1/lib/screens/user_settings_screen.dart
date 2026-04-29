import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/permission_service.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;
  bool _isDeleting = false;

  Future<void> _changeProfilePhoto() async {
    final hasPermission = await PermissionService.ensureGalleryPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Povoľ prístup ku galérii v nastaveniach aplikácie.'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (pickedFile == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.apiService.uploadMyProfilePicture(
        imageFile: File(pickedFile.path),
      );
      await authProvider.refreshCurrentUser();

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.dialogBackground(context),
          title: Text(
            'Hotovo',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          content: Text(
            'Profilová fotka bola úspešne zmenená.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteProfilePhoto() async {
    setState(() => _isDeleting = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.apiService.deleteMyProfilePicture();
      await authProvider.refreshCurrentUser();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profilová fotka bola odstránená.'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Widget _buildProfileAvatar(AuthProvider authProvider) {
    final user = authProvider.user;
    final token = authProvider.token;
    final hasPicture = user?.hasProfilePicture ?? false;
    final fallbackLetter = user?.initials ?? 'U';

    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF8B1A2C), width: 2),
        color: const Color(0xFF2D1515),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPicture && token != null
          ? Image.network(
              '${ApiService.baseUrl}/users/me/profile-picture',
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer $token'},
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  fallbackLetter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 30,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                fallbackLetter,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 30,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final isDarkMode = AppColors.isDark(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.dialogBackground(context),
        title: const Text('Upraviť vzhľad profilu'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(child: _buildProfileAvatar(authProvider)),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? user?.username ?? 'Používateľ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (isDarkMode ? const Color(0xFF1A0A0A) : Colors.white)
                        .withAlpha(204),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vzhľad profilu',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isUploading || _isDeleting)
                              ? null
                              : _changeProfilePhoto,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _isUploading
                                ? 'Nahrávam...'
                                : 'Zmeniť profilovú fotku',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B1A2C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: (_isUploading || _isDeleting)
                              ? null
                              : _deleteProfilePhoto,
                          icon: _isDeleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: Text(
                            _isDeleting
                                ? 'Odstraňujem...'
                                : 'Odstrániť profilovú fotku',
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isDarkMode
                                  ? Colors.white.withAlpha(80)
                                  : Colors.black.withAlpha(80),
                            ),
                            foregroundColor:
                                isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Nastavenia sa aplikujú okamžite.',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
