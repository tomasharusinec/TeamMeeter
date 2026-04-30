import 'package:flutter/material.dart';

extension LatestSnackBarContext on BuildContext {
  void showLatestSnackBar(SnackBar snackBar) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }
}
