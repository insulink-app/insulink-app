import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_scanner.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

/// A scanner whose radio is scripted, so the choosing logic can be exercised
/// without one.
class ScriptedScanner extends PodScanner {
  ScriptedScanner(this.rounds);

  /// What each successive scan returns, oldest first.
  final List<List<DiscoveredPod>> rounds;

  int scans = 0;

  /// Whether each successive scan used the service-uuid filter.
  final List<bool> filters = <bool>[];

  /// The address each successive scan was told to stop at, if any.
  final List<String?> stopTargets = <String?>[];

  @override
  Future<List<DiscoveredPod>> scan({
    required int wantedPodId,
    Duration timeout = const Duration(seconds: 30),
    bool filtered = true,
    String? stopAt,
  }) async {
    filters.add(filtered);
    stopTargets.add(stopAt);
    final round = scans < rounds.length ? rounds[scans] : const <DiscoveredPod>[];
    scans++;
    return round;
  }
}

DiscoveredPod podAt(String address, {int podId = 4241}) => DiscoveredPod(
      device: BluetoothDevice.fromId(address),
      podId: podId,
      lotNumber: 135,
      podSequenceNumber: 7,
    );

void main() {
  group('choosing among the pods a scan found', () {
    /// Every pod this app activates is given the SAME id, so a pod that was just
    /// replaced answers to the same address as the one on the body until its
    /// battery dies. Only the stored BLE address tells them apart.
    test('the remembered address settles two pods with the same id', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA'), podAt('BB:BB:BB:BB:BB:BB')],
      ]);

      final pod = await scanner.scanForSingle(
        wantedPodId: 4241,
        preferredAddress: 'BB:BB:BB:BB:BB:BB',
      );

      expect(pod.device.remoteId.str, 'BB:BB:BB:BB:BB:BB');
    });

    /// Commanding the wrong pod is worse than failing, so an ambiguity that the
    /// address does not settle is refused rather than guessed.
    test('an unrecognised pair is refused, not guessed', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA'), podAt('BB:BB:BB:BB:BB:BB')],
      ]);

      await expectLater(
        () => scanner.scanForSingle(
          wantedPodId: 4241,
          preferredAddress: 'CC:CC:CC:CC:CC:CC',
        ),
        throwsA(isA<PodLinkException>()),
      );
    });

    test('a pairing scan, which has no address to prefer, still refuses two', () async {
      final scanner = ScriptedScanner([
        [
          podAt('AA:AA:AA:AA:AA:AA', podId: DiscoveredPod.unactivatedPodId),
          podAt('BB:BB:BB:BB:BB:BB', podId: DiscoveredPod.unactivatedPodId),
        ],
      ]);

      await expectLater(
        () => scanner.scanForSingle(wantedPodId: DiscoveredPod.unactivatedPodId),
        throwsA(isA<PodLinkException>()),
      );
    });
  });

  group('an empty scan is tried twice', () {
    /// Only one BLE scan runs at a time and the CGM service scans on its own
    /// schedule, so a collision looks exactly like "no pod in range".
    test('a pod found on the second attempt is used', () async {
      final scanner = ScriptedScanner([
        [],
        [podAt('AA:AA:AA:AA:AA:AA')],
      ]);

      final pod = await scanner.scanForSingle(wantedPodId: 4241);

      expect(scanner.scans, 2);
      expect(pod.device.remoteId.str, 'AA:AA:AA:AA:AA:AA');
    });

    /// A service-uuid filter that does not match returns the same silence as an
    /// absent pod. The second pass drops the filter so the two can be told
    /// apart, in the log as well as in the result.
    test('the second attempt drops the service filter', () async {
      final scanner = ScriptedScanner([]);

      await expectLater(
        () => scanner.scanForSingle(wantedPodId: 4241),
        throwsA(isA<PodLinkException>()),
      );
      expect(scanner.filters, [true, false]);
    });

    test('a single hit does not scan a second time', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA')],
      ]);

      await scanner.scanForSingle(wantedPodId: 4241);

      expect(scanner.scans, 1);
    });

    test('twice empty gives up', () async {
      final scanner = ScriptedScanner([]);

      await expectLater(
        () => scanner.scanForSingle(wantedPodId: 4241),
        throwsA(isA<PodLinkException>()),
      );
      expect(scanner.scans, 2);
    });
  });

  group('a search the user stopped', () {
    /// The retry exists for a scan the CGM service interrupted. It must not fire
    /// for a user who just asked to stop, or stopping costs another half minute
    /// of staring at a spinner.
    test('does not start the second attempt', () async {
      final scanner = ScriptedScanner([[], [podAt('AA:AA:AA:AA:AA:AA')]]);

      await expectLater(
        () => scanner.scanForSingle(wantedPodId: 4241, isCancelled: () => true),
        throwsA(isA<PodLinkException>()),
      );
      expect(scanner.scans, 1);
    });

    /// A pod found on the way out is not handed back either. Connecting to a pod
    /// the user has just abandoned is the opposite of what they asked for.
    test('does not return a pod it happened to find', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA')],
      ]);

      await expectLater(
        () => scanner.scanForSingle(wantedPodId: 4241, isCancelled: () => true),
        throwsA(isA<PodLinkException>()),
      );
    });

    /// Not stopping leaves the retry exactly as it was.
    test('an uncancelled search still retries', () async {
      final scanner = ScriptedScanner([[], [podAt('AA:AA:AA:AA:AA:AA')]]);

      final pod = await scanner.scanForSingle(
        wantedPodId: 4241,
        isCancelled: () => false,
      );

      expect(scanner.scans, 2);
      expect(pod.device.remoteId.str, 'AA:AA:AA:AA:AA:AA');
    });
  });

  group('a scan ends as soon as the known pod appears', () {
    /// Without this the scan runs its whole window even though the pod was seen
    /// in the first second, and every pod operation pays that as dead time.
    test('a reconnect names the address to stop at', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA')],
      ]);

      await scanner.scanForSingle(
        wantedPodId: 4241,
        preferredAddress: 'AA:AA:AA:AA:AA:AA',
      );

      expect(scanner.stopTargets, ['AA:AA:AA:AA:AA:AA']);
    });

    /// Pairing has no address yet, and stopping early would give up the chance
    /// to notice a second pod answering to the same id. Activating the wrong pod
    /// is irreversible, so that scan runs its full window.
    test('a pairing scan stops at nothing', () async {
      final scanner = ScriptedScanner([
        [podAt('AA:AA:AA:AA:AA:AA', podId: DiscoveredPod.unactivatedPodId)],
      ]);

      await scanner.scanForSingle(wantedPodId: DiscoveredPod.unactivatedPodId);

      expect(scanner.stopTargets, [null]);
    });
  });
}
