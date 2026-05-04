// Pomôcky na testovanie hlásení Firebase Crashlytics počas vývoja.
// Umožní zámerne spustiť pád alebo neštandardnú výnimku kvôli overeniu nastavení.
// This file was generated using AI (Gemini)




import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';


const bool kCrashlyticsInDebugDefine = bool.fromEnvironment(
  'CRASHLYTICS_IN_DEBUG',
  defaultValue: false,
);



bool get kCrashlyticsDevTestUiVisible => kDebugMode && kCrashlyticsInDebugDefine;


class CrashlyticsTestToolsCard extends StatelessWidget {
  const CrashlyticsTestToolsCard({super.key});

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    if (!kCrashlyticsDevTestUiVisible) {
      return const SizedBox.shrink();
    }
    final textPrimary = AppColors.textPrimary(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C).withAlpha(40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B1A2C).withAlpha(180)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => _recordNonFatal(context),
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            label: const Text('Non-fatal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: textPrimary,
              side: BorderSide(color: AppColors.outlineStrong(context)),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _confirmFatalCrash(context),
            icon: const Icon(Icons.warning_amber_rounded, size: 20),
            label: const Text('Fatal crash'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordNonFatal(BuildContext context) async {
    if (!kCrashlyticsDevTestUiVisible) return;
    await FirebaseCrashlytics.instance.recordError(
      Exception('Crashlytics test (non-fatal)'),
      StackTrace.current,
      fatal: false,
    );
    await FirebaseCrashlytics.instance.sendUnsentReports();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Úspešne odoslaný non-fatal.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _confirmFatalCrash(BuildContext context) async {
    if (!kCrashlyticsDevTestUiVisible) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(ctx),
        content: Text(
          'Crashed?',
          style: TextStyle(
            color: AppColors.textPrimary(ctx),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Zrušiť',
              style: TextStyle(color: AppColors.textMuted(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'OK',
              style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    if (!kCrashlyticsDevTestUiVisible) return;
    FirebaseCrashlytics.instance.crash();
  }
}
