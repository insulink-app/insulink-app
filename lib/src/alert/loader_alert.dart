import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_dialog.dart';

/// A spinner card while a request runs, as an [InkDialog]; the caller pops it
/// when the request is done.
class LoaderAlert {
  const LoaderAlert();

  void show(BuildContext context) {
    const InkDialog.loading().show(context);
  }
}
