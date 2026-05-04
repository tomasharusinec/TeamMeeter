// Pomocné funkcie na zobrazenie spodných hlášok SnackBar v konzistentnom štýle.
// Pred novou hláškou skryje snackbar ktorý práve prebieha.
// AI generated with manual refinements




import 'package:flutter/material.dart';

extension LatestSnackBarContext on BuildContext {
  // Tato funkcia zobrazi dialogove okno.
  // Spracuje vstupy pouzivatela a vrati vysledok.
  void showLatestSnackBar(SnackBar snackBar) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }
}
