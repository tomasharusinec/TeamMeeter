import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show FlutterError, PlatformDispatcher, kDebugMode;

import '../dev/crashlytics_debug.dart' show kCrashlyticsInDebugDefine;

/// Firebase Analytics + Crashlytics (PVP5). Call once after [WidgetsFlutterBinding.ensureInitialized].
///
/// Crashlytics je v debug móde defaultne vypnutý. Na test: spusti s
/// `--dart-define=CRASHLYTICS_IN_DEBUG=true` a použij panel v nastaveniach profilu.
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
