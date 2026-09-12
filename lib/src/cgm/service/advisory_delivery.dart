import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Insulin the SERVICE gave on the user's behalf, after they tapped the button
/// on a pre-warning or a high alarm.
///
/// It is written down because the app was not involved: the delivery happened in
/// the service isolate, possibly with the phone locked and the app not running
/// at all. The notification that reported it may be long swiped away by the time
/// the app is opened, and insulin that went out unseen is the one thing that
/// must not be left to a notification the user might have missed.
class AdvisoryDelivery {
  const AdvisoryDelivery({required this.units, required this.at});

  final double units;
  final DateTime at;

  /// Parses "units:epochMs", or null when the record is absent or malformed.
  static AdvisoryDelivery? parse(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length != 2) {
      return null;
    }
    final units = double.tryParse(parts[0]);
    final millis = int.tryParse(parts[1]);
    if (units == null || millis == null || units <= 0) {
      return null;
    }
    return AdvisoryDelivery(
      units: units,
      at: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

/// The one open record, kept until the user has seen it in the app.
///
/// One slot, not a list: the banner says what just happened, and the meal log
/// is where the history lives. A second delivery overwrites the first, which is
/// correct — it is the newer thing to be told about.
class AdvisoryDeliveryStore {
  const AdvisoryDeliveryStore();

  static const _key = 'advisory.delivered';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<void> record(double units) => _storage.write(
    key: _key,
    value: '$units:${DateTime.now().millisecondsSinceEpoch}',
  );

  Future<AdvisoryDelivery?> load() async =>
      AdvisoryDelivery.parse(await _storage.read(key: _key));

  Future<void> clear() => _storage.delete(key: _key);
}
