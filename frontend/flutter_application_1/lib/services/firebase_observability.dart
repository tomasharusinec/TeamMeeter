import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show FlutterError, PlatformDispatcher, kDebugMode;

/// Firebase Analytics + Crashlytics (PVP5). Call once after [WidgetsFlutterBinding.ensureInitialized].
Future<void> configureFirebaseObservability() async {
  await Firebase.initializeApp();

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
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
