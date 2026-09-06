import 'package:flutter/widgets.dart';

/// Turns the timestamps a device left behind into a coverage strip.
///
/// There is no connection log to draw from, because none of these devices
/// reports its own outages. What each one does leave is data with a time on it:
/// a glucose reading, a heart-rate sample, a pod poll. The ABSENCE of that over
/// a slice of the window is the outage — a sensor that produced nothing for an
/// hour was not reachable for an hour, whatever it believed at the time.
///
/// Buckets rather than exact spans, because the three cadences are wildly
/// different (a band delivers about once a second, a pod is polled every fifteen
/// minutes). A bucket wide enough for the slowest of them asks the same question
/// of all three: did anything at all arrive in this half hour?
class ConnectionTimeline {
  const ConnectionTimeline({required this.now, this.window = defaultWindow});

  /// One day: long enough to show last night, short enough that a bucket is
  /// still a few pixels wide on a phone.
  static const Duration defaultWindow = Duration(hours: 24);

  /// Half an hour, the pod's poll cadence doubled, so a single skipped poll is
  /// not drawn as an outage.
  static const Duration bucket = Duration(minutes: 30);

  final DateTime now;
  final Duration window;

  DateTime get start => now.subtract(window);

  int get bucketCount => window.inMinutes ~/ bucket.inMinutes;

  /// When the slice at [index] begins, so it can name the half hour it covers.
  DateTime bucketStart(int index) => start.add(bucket * index);

  /// One flag per bucket, oldest first: whether anything arrived in it.
  List<bool> cover(Iterable<int> epochMinutes) {
    final covered = List<bool>.filled(bucketCount, false);
    final startMinute = start.millisecondsSinceEpoch ~/ 60000;
    for (final minute in epochMinutes) {
      final index = (minute - startMinute) ~/ bucket.inMinutes;
      if (index >= 0 && index < bucketCount) {
        covered[index] = true;
      }
    }
    return covered;
  }

  /// How many separate stretches of silence the strip holds.
  ///
  /// Stretches, not buckets: an outage that lasted three hours is one thing that
  /// happened, and counting it as six would say more about the bucket size than
  /// about the link. Leading silence counts too — a device that only came back
  /// halfway through the day was out for the first half.
  static int outages(List<bool> covered) {
    var count = 0;
    var inGap = false;
    for (final bucketCovered in covered) {
      if (!bucketCovered && !inGap) {
        count++;
      }
      inGap = !bucketCovered;
    }
    return count;
  }
}

/// One device on the connection page: what it is, when it was last heard from,
/// and which slices of the window it was in contact during.
class DeviceConnection {
  const DeviceConnection({
    required this.labelKey,
    required this.icon,
    required this.lastContact,
    required this.covered,
  });

  final String labelKey;
  final IconData icon;

  /// Null when the device has never been reached, which is not the same as an
  /// outage and is said differently on the page.
  final DateTime? lastContact;

  /// One flag per [ConnectionTimeline.bucketCount] slice, oldest first.
  final List<bool> covered;

  /// Whether the device has ever been set up. A device nobody owns draws an
  /// empty strip that would otherwise read as one long outage.
  bool get isKnown => lastContact != null || covered.contains(true);

  int get outages => ConnectionTimeline.outages(covered);
}
