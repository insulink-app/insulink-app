import 'device_record.dart';

/// One device in the history, with the moment it came off resolved.
class DeviceHistoryEntry {
  const DeviceHistoryEntry({required this.record, required this.endedAt});

  final DeviceRecord record;

  /// When the device came off, or null while it is still running.
  final DateTime? endedAt;

  String get typeKey => record.typeKey;

  DateTime get start => record.start;

  bool get isActive => endedAt == null;

  /// Whether it ended because the user said so rather than by running out.
  bool get wasDiscarded => record.discardedAt != null;

  /// How long the device was actually worn: from its start to when it came off,
  /// or to [now] while it is still running.
  Duration worn({DateTime? now}) =>
      (endedAt ?? now ?? DateTime.now()).difference(start);

  /// Whole rated days of the session, floored the way `DeviceLifespan.totalDays`
  /// floors them: a G7 reports 10 d + 12 h of grace and is a 10-day sensor.
  int get ratedDays =>
      (record.expiresAt.difference(start).inSeconds / 86400).floor();
}

/// Turns the account's device registrations into the rows the history page
/// draws. Two things have to be worked out here rather than read off a record.
///
/// **One row per physical device.** A reinstall restores the running device and
/// registers it a second time, so the earliest registration of each device wins
/// and the rest are dropped.
///
/// **When it came off.** No record says so. A device swapped out early keeps its
/// future expiry, so expiry alone would call two of them active at once. It
/// ended at whichever came first of three things: its expiry, the moment the
/// user said it was gone, and the start of the device that replaced it.
class DeviceHistory {
  const DeviceHistory(this.records, {this.now});

  final List<DeviceRecord> records;

  /// Injectable clock, so the resolution can be tested without the wall clock.
  final DateTime? now;

  /// The history, newest device first.
  List<DeviceHistoryEntry> resolve() {
    final devices = _oneRowPerDevice();
    final entries = [
      for (final record in devices)
        DeviceHistoryEntry(record: record, endedAt: _endedAt(record, devices)),
    ];
    entries.sort((first, second) => second.start.compareTo(first.start));
    return entries;
  }

  List<DeviceRecord> _oneRowPerDevice() {
    final byDevice = <String, DeviceRecord>{};
    for (final record in records) {
      final seen = byDevice[record.deviceKey];
      if (seen == null || record.registeredAt.isBefore(seen.registeredAt)) {
        byDevice[record.deviceKey] = record;
      }
    }
    return byDevice.values.toList();
  }

  /// The starts of every device that began after [record].
  List<DateTime> _successorStarts(
    DeviceRecord record,
    List<DeviceRecord> devices,
  ) {
    return [
      for (final other in devices)
        if (other.start.isAfter(record.start)) other.start,
    ];
  }

  DateTime? _endedAt(DeviceRecord record, List<DeviceRecord> devices) {
    final successors = _successorStarts(record, devices);
    final at = now ?? DateTime.now();
    final stillRunning = record.discardedAt == null &&
        successors.isEmpty &&
        record.expiresAt.isAfter(at);
    if (stillRunning) {
      return null;
    }
    return [record.expiresAt, ?record.discardedAt, ...successors].reduce(
      (earliest, candidate) => candidate.isBefore(earliest) ? candidate : earliest,
    );
  }
}
