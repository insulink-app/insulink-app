import 'dart:io';

/// Notification-action ids for the pre-warning's countermeasure buttons: log the
/// suggested rescue carbs, or deliver the suggested correction bolus.
const String advisoryCarbsAction = 'advisory_carbs';
const String advisoryBolusAction = 'advisory_bolus';

/// A countermeasure the user accepted from a pre-warning notification, buffered
/// until the service isolate can carry it out.
class AdvisoryRequest {
  const AdvisoryRequest({
    required this.isBolus,
    required this.amount,
    required this.glucoseMgdl,
    required this.at,
  });

  /// Insulin units when [isBolus], otherwise grams of fast carbohydrate. Already
  /// on the pod's pulse grid for a bolus, snapped where the notification was
  /// composed, so the number the button showed is the number that goes out.
  final bool isBolus;
  final double amount;

  /// The reading the suggestion was computed from, logged with the meal.
  final int glucoseMgdl;

  /// When the button was tapped, NOT when the request is applied.
  final DateTime at;

  /// How long a tap stays actionable.
  ///
  /// A dose is sized for the glucose that was on screen when the notification
  /// was posted. A request the service only finds much later (the process was
  /// killed, the phone was off) would deliver that dose against a body that has
  /// moved on, so it is dropped instead. Fifteen minutes is three CGM readings:
  /// long enough to survive a restart, short enough to still be this episode.
  static const Duration validFor = Duration(minutes: 15);

  bool get isStale => DateTime.now().difference(at) > validFor;

  /// Parses one `kind:amount:glucose:epochMs` line, or null when it is malformed
  /// or names a dose of nothing.
  static AdvisoryRequest? parse(String line) {
    final parts = line.split(':');
    if (parts.length != 4) {
      return null;
    }
    final amount = double.tryParse(parts[1]);
    final glucoseMgdl = int.tryParse(parts[2]);
    final millis = int.tryParse(parts[3]);
    if (amount == null || glucoseMgdl == null || millis == null) {
      return null;
    }
    if (amount <= 0) {
      return null;
    }
    return AdvisoryRequest(
      isBolus: parts[0] == 'bolus',
      amount: amount,
      glucoseMgdl: glucoseMgdl,
      at: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

/// Hand-off for pre-warning action taps, exactly like
/// `SportStore.recordTrainingDecision`: the isolate `flutter_local_notifications`
/// spawns for an action tap has no secure storage and no plugins, so it can only
/// append a line to a plain file. The service isolate drains it on its next
/// watchdog tick and does the real work ([AdvisoryActionRunner]).
///
/// This is what lets the buttons work on a locked phone. The alternative, an
/// action that brings the app to the front, means unlocking the device and
/// watching it open before anything happens, which is a lot to ask of somebody
/// who has just been told their glucose is about to drop.
class AdvisoryActionStore {
  const AdvisoryActionStore();

  File get _requestFile =>
      File('${Directory.systemTemp.path}/insulink_advisory_requests');

  /// Absolute path of the hand-off file, resolved in the plugin-capable service
  /// isolate and carried in the notification payload. The action-tap isolate
  /// cannot resolve its own writable temp dir reliably, so it writes to THIS
  /// path (see `SportStore.decisionFilePath` for the failure that taught us).
  String get requestFilePath => _requestFile.path;

  /// Record an accepted countermeasure. Synchronous and plugin-free so it
  /// completes before the ephemeral action isolate is torn down.
  void record(
    String kind,
    double amount,
    int glucoseMgdl, {
    String? filePath,
  }) {
    final file = filePath != null ? File(filePath) : _requestFile;
    final at = DateTime.now().millisecondsSinceEpoch;
    file.writeAsStringSync(
      '$kind:$amount:$glucoseMgdl:$at\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Everything buffered since the last drain, clearing the file first so a
  /// request cannot be carried out twice if applying it throws.
  Future<List<AdvisoryRequest>> drain() async {
    final file = _requestFile;
    if (!await file.exists()) {
      return const [];
    }
    final lines = await file.readAsLines();
    await file.delete();
    return [
      for (final line in lines) ?AdvisoryRequest.parse(line),
    ];
  }
}
