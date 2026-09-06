/// Notification-action ids for the pre-warning's countermeasure buttons: log the
/// suggested rescue carbs, or deliver the suggested correction bolus.
const String advisoryCarbsAction = 'advisory_carbs';
const String advisoryBolusAction = 'advisory_bolus';

/// A countermeasure the user accepted from a pre-warning notification, carried
/// from the notification to the app in the notification's own payload.
///
/// The payload is the whole hand-off. There is no store and no queue: the button
/// brings the app to the front (`showsUserInterface`), so the isolate that reads
/// this is the one with the meal log, the pod and the screen. An earlier version
/// buffered the tap in a file for the background service to pick up on its next
/// watchdog tick, which had three failure modes that all looked identical from
/// the outside, and no way to tell the user that any of them had happened.
class AdvisoryRequest {
  const AdvisoryRequest({
    required this.isBolus,
    required this.amount,
    required this.glucoseMgdl,
  });

  /// Insulin units when [isBolus], otherwise grams of fast carbohydrate.
  final bool isBolus;
  final double amount;

  /// The reading the suggestion was computed from, logged with the meal.
  final int glucoseMgdl;

  /// What the notification carries: the two numbers the buttons act on. Which
  /// button was pressed comes from the action id, not from here.
  static String encode(double amount, int glucoseMgdl) =>
      '$amount\n$glucoseMgdl';

  /// The request a tap stands for, or null when the tap was not one of ours or
  /// the payload is unreadable.
  static AdvisoryRequest? parse(String? actionId, String? payload) {
    if (actionId != advisoryCarbsAction && actionId != advisoryBolusAction) {
      return null;
    }
    final parts = (payload ?? '').split('\n');
    if (parts.length != 2) {
      return null;
    }
    final amount = double.tryParse(parts[0]);
    final glucoseMgdl = int.tryParse(parts[1]);
    if (amount == null || glucoseMgdl == null || amount <= 0) {
      return null;
    }
    return AdvisoryRequest(
      isBolus: actionId == advisoryBolusAction,
      amount: amount,
      glucoseMgdl: glucoseMgdl,
    );
  }
}
