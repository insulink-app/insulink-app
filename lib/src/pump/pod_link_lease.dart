import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when another part of the app is already holding the pod's link.
class PodLinkBusy implements Exception {
  PodLinkBusy(this.holder);

  final String holder;

  @override
  String toString() => 'PodLinkBusy: the link is held by $holder';
}

/// Which part of the app is allowed to hold the pod's BLE link, across isolates.
///
/// The pod's link is exclusive and the app has TWO places that reach for it: the
/// UI isolate when the user taps something, and the foreground service isolate
/// for the background poll and the automation. Neither could see the other, so
/// both would connect, and Android answers the second writer with
/// `ERROR_GATT_WRITE_REQUEST_BUSY` while the pod gives up on both sessions. That
/// looks exactly like a pod that blocks under too many commands, which is what it
/// was mistaken for.
///
/// Held in secure storage because that is the only thing both isolates can see.
/// It is a lease and not a lock: a holder that dies never releases anything, so
/// it expires on its own and the pod cannot be locked away by a crash.
///
/// Taking it is write-then-read-back rather than check-then-write. Two isolates
/// can pass the check at the same instant, but only one write lands last, and
/// reading back is what tells the loser it lost. The keystore serialises the
/// writes, so exactly one of them sees its own name.
class PodLinkLease {
  const PodLinkLease(
    this.owner, {
    this.patience = Duration.zero,
    this.storage = const FlutterSecureStorage(),
  });

  /// Names the holder in the log and in a [PodLinkBusy]. Two owners with the same
  /// name would not exclude each other, so there is one per place that connects.
  final String owner;

  /// How long to wait for a lease somebody else holds.
  ///
  /// The two sides want opposite things. A tap has to happen, and the service's
  /// poll is a few seconds long, so the UI waits it out. The service's own work
  /// is periodic and can simply come back, and waiting there would only keep the
  /// link occupied for longer, so it gives up at once.
  final Duration patience;

  final FlutterSecureStorage storage;

  static const String key = 'pod.link_lease';

  /// How long a lease lives without being released.
  ///
  /// Long enough for the longest ordinary operation (the automation's connect,
  /// status read, cancel and program), short enough that a process killed while
  /// holding one does not keep the pod away from the rest of the app for longer
  /// than a poll interval.
  static const Duration hold = Duration(seconds: 90);

  /// How often the lease is re-checked while waiting for it.
  static const Duration _pollEvery = Duration(milliseconds: 400);

  /// Claims the link, waiting up to [patience] for a holder to finish, and
  /// throwing [PodLinkBusy] when it does not.
  ///
  /// Counts polls rather than measuring elapsed time, so the wait is the same
  /// whether the clock is the real one or a fixed one handed in by a test.
  Future<void> take({DateTime? now}) async {
    final maxWaits = patience.inMilliseconds ~/ _pollEvery.inMilliseconds;
    for (var waited = 0; ; waited++) {
      final held = await _heldByOther(now ?? DateTime.now());
      if (held == null) {
        break;
      }
      if (waited >= maxWaits) {
        throw PodLinkBusy(held);
      }
      await Future<void>.delayed(_pollEvery);
    }
    final at = now ?? DateTime.now();
    await storage.write(
      key: key,
      value: jsonEncode({
        'owner': owner,
        'until': at.add(hold).millisecondsSinceEpoch,
      }),
    );
    final confirmed = await _read();
    if (confirmed == null || confirmed.owner != owner) {
      throw PodLinkBusy(confirmed?.owner ?? 'another part of the app');
    }
  }

  /// Who else holds a live lease right now, or null when the link is free.
  Future<String?> _heldByOther(DateTime at) async {
    final existing = await _read();
    if (existing == null ||
        existing.owner == owner ||
        !existing.until.isAfter(at)) {
      return null;
    }
    return existing.owner;
  }

  /// Gives the link back, but only when it is still ours. A lease that expired
  /// and was taken by someone else must not be cleared from under them.
  Future<void> release() async {
    final existing = await _read();
    if (existing == null || existing.owner != owner) {
      return;
    }
    await storage.delete(key: key);
  }

  Future<({String owner, DateTime until})?> _read() async {
    final raw = await storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final held = jsonDecode(raw) as Map<String, dynamic>;
      return (
        owner: held['owner'] as String,
        until: DateTime.fromMillisecondsSinceEpoch(
          (held['until'] as num).toInt(),
        ),
      );
    } on FormatException {
      return null;
    }
  }
}
