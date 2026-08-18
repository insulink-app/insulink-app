import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';

/// The UI's view of the pod, and the few operations it can start.
///
/// Each operation opens a session, does one thing, and closes it — the pod does
/// not hold a link open, so there is no connection to keep alive between taps.
///
/// [suspendDelivery] and [deactivatePod] never consult [PodDeliveryGate]. A pod
/// that is already delivering must stay stoppable whatever any setting says;
/// only the paths that START delivery are gated.
class PodController extends ChangeNotifier {
  PodController({required this.store, required this.gate})
      : _sequence = store.commandSequence,
        _connection = PodConnection(store: store);

  static const int _fixedNonce = 0;

  final PodStore store;
  final PodDeliveryGate gate;
  final PodConnection _connection;

  /// The pod command sequence number, a persisted 4-bit counter.
  ///
  /// Distinct from the message-packet sequence inside a session: that one also
  /// advances for acknowledgements, which are not pod commands. Conflating them
  /// makes the pod see a sequence number it has already run and refuse the
  /// command, so this is loaded from and written back to the store on its own.
  int _sequence;

  PodStatusResponse? _status;
  DateTime? _statusReadAt;
  String? _failure;
  bool _busy = false;

  /// The last status read from the pod, or null if none has been read.
  PodStatusResponse? get status => _status;

  /// When [status] was read. Any decision that depends on the pod's state must
  /// check this rather than trusting the cached value.
  DateTime? get statusReadAt => _statusReadAt;

  /// A standing failure to show, cleared when the next operation starts.
  String? get failure => _failure;

  bool get isBusy => _busy;

  bool get hasPod => store.hasPod;

  /// How old [status] is, or null if nothing has been read.
  Duration? get statusAge {
    final readAt = _statusReadAt;
    return readAt == null ? null : DateTime.now().difference(readAt);
  }

  /// Reads the pod's current state.
  Future<void> refresh() => _withSession('refresh', (session) async {
        _status = await _readStatus(session);
        _statusReadAt = DateTime.now();
      });

  /// Stops every kind of delivery. The path that must work when nothing else
  /// does, so it is not gated and carries no computed dose.
  Future<void> suspendDelivery() =>
      _withSession('suspend', (session) async {
        final response = await session.run(PodStopDeliveryCommand.suspendAll(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
        ));
        _absorb(response);
      });

  /// Ends the pod's life so it can be removed, then forgets it.
  ///
  /// The pod is only forgotten once it reports itself stopped. Dropping the key
  /// while it still delivers would leave insulin running with nothing able to
  /// command it.
  Future<void> deactivatePod() => _withSession('deactivate', (session) async {
        final response = await session.run(PodDeactivateCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
        ));
        _absorb(response);
        final stopped = _status?.delivery.isSuspended ?? false;
        if (stopped) {
          await store.forgetPod();
        } else {
          _failure = 'Pod did not confirm it stopped — it was NOT forgotten';
        }
      });

  /// Acknowledges the pod's alerts so it stops beeping.
  Future<void> silenceAlerts() => _withSession('silence', (session) async {
        final active = _status?.activeAlerts;
        if (active == null || active.isEmpty) {
          return;
        }
        final response = await session.run(PodSilenceAlertsCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          alerts: active,
        ));
        _absorb(response);
      });

  int get _nextSequence {
    _sequence = (_sequence + 1) & 0x0f;
    return _sequence;
  }

  Future<PodStatusResponse> _readStatus(PodSession session) async {
    final response = await session.run(PodGetStatusCommand(
      uniqueId: store.uniqueId!,
      sequenceNumber: _nextSequence,
    ));
    if (response is PodStatusResponse) {
      return response;
    }
    throw PodResponseException('Pod answered a status request with $response');
  }

  /// Takes a status reply as the new known state, and records a refusal as a
  /// failure rather than letting it pass as success.
  ///
  /// A status also reports `lastProgrammingSequenceNumber`, which is tempting to
  /// adopt but is NOT the same counter: it only moves for delivery programs, so
  /// adopting it after a status or an alert acknowledgement would step this
  /// counter BACKWARDS and reuse a number the pod has already run. The counter is
  /// therefore ours alone, persisted after every operation; a genuine desync is
  /// what the pod's `illegalSecurityCode` refusal is for.
  void _absorb(PodResponse response) {
    if (response is PodStatusResponse) {
      _status = response;
      _statusReadAt = DateTime.now();
      return;
    }
    if (response is PodNakResponse) {
      _failure = 'Pod refused the command: ${response.error.name}';
      return;
    }
    _failure = 'Unexpected pod reply';
  }

  /// Runs [body] against a fresh session, always closing the link.
  ///
  /// A [PodCommandOutcomeUnknown] is reported as exactly that: the command may
  /// have taken effect, so the message tells the user to check the pod rather
  /// than implying nothing happened.
  Future<void> _withSession(
    String what,
    Future<void> Function(PodSession session) body,
  ) async {
    if (_busy) {
      return;
    }
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      final session = await _connection.openSession();
      await body(session);
      await store.saveCommandSequence(_sequence);
      await PumpSync().sync(store);
    } on PodCommandOutcomeUnknown catch (error) {
      _failure = 'The pod may have acted on this — check the pod. ${error.message}';
    } on Exception catch (error) {
      _failure = 'Could not $what: $error';
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }

  /// The pod the account is holding for us, or null if there is none, one is
  /// already paired locally, or it has expired.
  ///
  /// Never offered while a pod is paired locally: adopting a second identity
  /// would silently replace the key to a pod that may still be delivering.
  Future<PodRestore?> availableBackendPod(BuildContext context) async {
    if (hasPod) {
      return null;
    }
    final restore = await PumpSync().fetchCurrent(context);
    if (restore == null || restore.isExpired) {
      return null;
    }
    return restore;
  }

  /// Adopts a pod from the account and reads its status to confirm it answers.
  ///
  /// If the pod does not answer, the credentials are KEPT rather than rolled
  /// back: the pod may simply be out of range, and discarding the only key to a
  /// pod that is still on the body is the one outcome worth avoiding.
  Future<void> restoreFromBackend(PodRestore restore) async {
    await store.adoptFromBackend(
      pumpId: restore.pumpId,
      uniqueId: restore.uniqueId,
      longTermKey: restore.longTermKey,
      lotNumber: restore.lotNumber,
      podSequenceNumber: restore.podSequenceNumber,
      activatedAt: restore.activatedAt,
      expiryHours: restore.expiryHours,
      eapSequence: restore.eapSequence,
      commandSequence: restore.commandSequence,
      bleAddress: restore.bleAddress,
    );
    _sequence = store.commandSequence;
    notifyListeners();
    await refresh();
  }

  /// Programs a bolus on the pod and returns its answer.
  ///
  /// Unlike the maintenance operations this does NOT swallow failures into
  /// [failure]: the caller has to distinguish "refused" from "we do not know",
  /// because only the first one is safe to treat as "no insulin was given". A
  /// [PodCommandOutcomeUnknown] therefore propagates.
  ///
  /// Gated by [PodDeliveryGate] — this is a path that starts a delivery.
  Future<PodResponse> sendBolus(PodBolusAmount amount) async {
    if (!gate.allowsDelivery) {
      throw StateError('Pod delivery is locked');
    }
    final uniqueId = store.uniqueId;
    if (uniqueId == null) {
      throw StateError('No pod is paired');
    }
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      final session = await _connection.openSession();
      final response = await session.run(PodProgramBolusCommand(
        uniqueId: uniqueId,
        sequenceNumber: _nextSequence,
        nonce: _fixedNonce,
        amount: amount,
        reminder: const PodProgramReminder(atEnd: true),
      ));
      await store.saveCommandSequence(_sequence);
      await PumpSync().sync(store);
      _absorb(response);
      return response;
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }
}
