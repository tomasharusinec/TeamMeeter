// Nastavuje Crashlytics a Firebase Analytics aby sa zbierali pády aj základné udalosti používania.
// Vystavuje firebaseAnalyticsObserver použiteľný v koreňovom MaterialApp ako pozorovateľ navigácie.
// AI generated with manual refinements




import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show FlutterError, PlatformDispatcher, kDebugMode;

import '../dev/crashlytics_debug.dart' show kCrashlyticsInDebugDefine;





Future<void> configureFirebaseObservability() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode || kCrashlyticsInDebugDefine,
  );

  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

FirebaseAnalytics get firebaseAnalytics => FirebaseAnalytics.instance;

FirebaseAnalyticsObserver get firebaseAnalyticsObserver =>
    FirebaseAnalyticsObserver(analytics: firebaseAnalytics);
