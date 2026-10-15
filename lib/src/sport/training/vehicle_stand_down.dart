import 'cardio_models.dart';

/// Recognises a ride that is clearly motorised, so the detect stream can stand
/// down for the rest of it. The activity recognition reporting a vehicle opens
/// the stream (a bike ride is often labelled as one), but a few GNSS fixes at
/// [_vehicleKmh] or more under that label settle it: no human-powered training
/// gets there, and the classifier would discard the segment anyway. Any other
/// label ends the ride, so stepping off the bus reopens detection at once.
class VehicleStandDown {
  /// GNSS (Doppler) speed no commuter bike reaches on the flat, while a car or
  /// bus passes it on most rides.
  static const _vehicleKmh = 50.0;

  /// Fixes at vehicle speed it takes to confirm, so one downhill stretch on a
  /// misread bike ride never stops its route.
  static const _fastFixesToConfirm = 3;

  int _fastFixes = 0;

  /// Whether the current ride is confirmed motorised.
  bool get confirmed => _fastFixes >= _fastFixesToConfirm;

  /// Feeds the current activity label and, for a fix, its speed (0 without
  /// one): a fast fix under a vehicle label counts, any other label resets.
  void observe(ActivityKind? activity, double speedKmh) {
    if (activity != ActivityKind.vehicle) {
      _fastFixes = 0;
    } else if (speedKmh >= _vehicleKmh) {
      _fastFixes++;
    }
  }
}
