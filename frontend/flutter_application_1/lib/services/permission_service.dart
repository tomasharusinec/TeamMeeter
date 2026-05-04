import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Len systémové žiadosti o oprávnenia (žiadne vlastné vysvetľovacie popupy v appke).
///
/// **Povinný systémový dialóg** – pred výberom z galérie (profil, ikona skupiny) a
/// pred výberom prílohy v chate sa vždy volá [requestGalleryPermission] (ak ešte
/// nie je udelené príslušné oprávnenie), aby sa zobrazil oficiálny dialóg OS.
///
/// **„Povoliť iba raz“ / „Len tentokrát“** – ak ich zariadenie ponúka, sú súčasťou
/// systémového dialógu; aplikácia nemôže pridať vlastnú štvrtú voľbu.
///
/// **Poznámka:** Po udelení širokého prístupu ku médiám môže ten istý grant platiť
/// pre viac obrazoviek (jedna aplikácia, jeden proces).
class PermissionService {
  PermissionService._();

  /// Či je už udelený prístup ku galérii / médiám (bez nového requestu).
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

  /// Zobrazí systémový dialóg (fotky / úložisko podľa verzie Androidu).
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

  static Future<bool> requestCameraPermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    final status = await Permission.camera.request();
    return status.isGranted;
  }
}
