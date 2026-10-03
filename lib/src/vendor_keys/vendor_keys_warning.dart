import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/libre3/libre3_crypto.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:insulink/src/vendor_keys/vendor_keys.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Wraps the app's home and, on every launch whose build lacks vendor keys,
/// raises an [Alert] naming the devices that cannot pair. It comes back on each
/// start on purpose: a build without the keys looks healthy until a pairing
/// fails, and that must not be the first sign of it.
class VendorKeysWarning extends StatefulWidget {
  const VendorKeysWarning({super.key, required this.child});

  final Widget child;

  @override
  State<VendorKeysWarning> createState() => _VendorKeysWarningState();
}

class _VendorKeysWarningState extends State<VendorKeysWarning> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warnIfMissing());
  }

  /// [VendorKeys.ensureLoaded] already ran in `main`, so the Dart-side keys are
  /// only read. Libre 3's live on the Android side, which is asked separately.
  Future<void> _warnIfMissing() async {
    final missing = [
      ...VendorKeys.current.missingDevices,
      if (!await Libre3NativeCrypto().vendorKeysComplete()) 'FreeStyle Libre 3',
    ];
    if (!mounted || missing.isEmpty) {
      return;
    }
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: LocaleText(
        'vendor_keys.missing',
        params: [missing.join(', ')],
        textAlign: TextAlign.center,
      ),
    ).show(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
