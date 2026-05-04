// Pomocné volania okolo oprávnení galérie a súborov na mobilnom zariadení používateľa.
// Najprv overí či je prístup k médiám povolený a ak treba použije štandardný systémový dialóg.
// AI generated with manual refinements




import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';












class PermissionService {
  PermissionService._();

  
  static Future<bool> hasGalleryReadAccess() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    if (Platform.isIOS) {
      final s = await Permission.photos.status;
      return s.isGranted || s.isLimited;
    }
    final photos = await Permission.photos.status;
    if (photos.isGranted || photos.isLimited) return true;
    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  
  // Tato funkcia vyziada alebo overi opravnenia.
  // Vrati stav opravnenia pre dalsiu logiku.
  static Future<bool> requestGalleryPermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    final photosStatus = await Permission.photos.request();
    if (photosStatus.isGranted || photosStatus.isLimited) return true;
    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  static Future<bool> hasCameraAccess() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    final s = await Permission.camera.status;
    return s.isGranted;
  }

  // Tato funkcia vyziada alebo overi opravnenia.
  // Vrati stav opravnenia pre dalsiu logiku.
  static Future<bool> requestCameraPermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    final status = await Permission.camera.request();
    return status.isGranted;
  }
}
