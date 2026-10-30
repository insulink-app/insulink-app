import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../cgm/service/advisory_action.dart';
import '../nutrition/meal/meal.dart';
import '../pump/protocol/pod_bolus_command.dart';

/// A photographed meal whose bolus has not been confirmed yet.
///
/// Written by the injection page, because only the page knows what the
/// calculator shows, and read by the service isolate, because only the service
/// is still alive once the user has walked away. [meal] is the calculator's
/// current state, with the dose in [Meal.bolus]: zero when the page has nothing
/// it would let the user confirm.
class PendingMealBolus {
  const PendingMealBolus({
    required this.takenAt,
    required this.meal,
    this.warned = false,
  });

  /// How long a photographed meal may wait for its bolus before the warning.
  /// Long enough to read the calculator, short enough to precede the first bites.
  static const remindAfter = Duration(minutes: 2);

  final DateTime takenAt;
  final Meal meal;

  /// Whether the warning for this state of the calculator is already up. A
  /// corrected dose saves a fresh record, which replaces the notification.
  final bool warned;

  Duration get age => DateTime.now().difference(takenAt);

  bool get isDue => !warned && age >= remindAfter;

  /// Past the point a button on it would still be honoured. Measured from the
  /// photo, because that is what the calculator's dose was sized around.
  bool get isLapsed => age > AdvisoryRequest.validFor;

  /// The dose on the pod's pulse grid, so the button names what goes out.
  double get units => PodBolusAmount.snapToPulse(meal.bolus);

  PendingMealBolus markedWarned() =>
      PendingMealBolus(takenAt: takenAt, meal: meal, warned: true);

  String encode() => jsonEncode({
    'taken_at': takenAt.millisecondsSinceEpoch,
    'meal': meal.toJson(),
    'warned': warned,
  });

  /// Null when [raw] is absent or malformed: a record nobody can read must not
  /// raise a warning, let alone offer a dose.
  static PendingMealBolus? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PendingMealBolus(
        takenAt: DateTime.fromMillisecondsSinceEpoch(json['taken_at'] as int),
        meal: Meal.fromJson(json['meal'] as Map<String, dynamic>),
        warned: json['warned'] as bool? ?? false,
      );
    } on Object {
      return null;
    }
  }
}

/// The one open record, shared across isolates through secure storage. Its
/// presence is also what makes the notification button valid: clearing it on
/// confirmation is what stops a stale button delivering the meal a second time.
class PendingMealBolusStore {
  const PendingMealBolusStore();

  static const _key = 'injection.pending_meal_bolus';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<void> save(PendingMealBolus pending) =>
      _storage.write(key: _key, value: pending.encode());

  Future<PendingMealBolus?> load() async =>
      PendingMealBolus.parse(await _storage.read(key: _key));

  Future<void> clear() => _storage.delete(key: _key);
}
