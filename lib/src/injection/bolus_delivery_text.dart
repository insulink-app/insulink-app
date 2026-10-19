import 'package:flutter/widgets.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/localization/locales.dart';

/// The reason a bolus did not go out, as the user reads it.
extension BolusDeliveryText on BolusDeliveryResult {
  /// The localized reason when there is one, else the raw [detail].
  String? detailText(BuildContext context) {
    final key = detailKey;
    if (key == null) {
      return detail;
    }
    return Locales.string(context, key).replaceFirst('#', detailParam ?? '');
  }
}
