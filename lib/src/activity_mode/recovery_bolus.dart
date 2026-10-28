import 'package:insulink/src/activity_mode/activity_bout.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// The cut the bolus calculator makes to its suggestion in the recovery after
/// a long endurance bout.
///
/// The recovery's lower basal has nothing to take away in the evening and at
/// night, where the schedule is close to zero; the insulin behind the lows of
/// an active day is the dinner bolus. So the suggestion shrinks by the user's
/// percentage while [ActivityBout.bolusRecoveryUntil] holds. It is a
/// suggestion: the sheet says why it is smaller, and the field stays editable.
class RecoveryBolus {
  const RecoveryBolus(this.percent);

  const RecoveryBolus.none() : percent = 0;

  /// How much smaller the suggestion is, 0 when nothing is cut.
  final int percent;

  /// The cut in force at [now]: none while the activity mode is off, the
  /// setting is 0, or no long bout ended within the recovery hours.
  static Future<RecoveryBolus> load(DateTime now) async {
    if (!await ActivityModeSettings.enabled.load()) {
      return const RecoveryBolus.none();
    }
    final percent = await ActivityModeSettings.recoveryBolus.load();
    final until = await const ActivityBout().bolusRecoveryUntil(now);
    return percent == 0 || until == null
        ? const RecoveryBolus.none()
        : RecoveryBolus(percent);
  }

  bool get applies => percent > 0;

  double reduce(double units) => units * (100 - percent) / 100;
}
