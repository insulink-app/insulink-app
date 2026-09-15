import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/demo_pod.dart';
import 'package:insulink/src/pump/pod_ble_permissions.dart';
import 'package:insulink/src/pump/pod_backup_restore.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_activation.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/pump_sync.dart';

/// Where the user is in the activation, as the wizard presents it.
///
/// Coarser than [PodActivationStep], which tracks the protocol. This is about
/// what the user has to DO, and the split at [attachPod] is the point of it: the
/// pod is primed off the body and only then goes on, so the two halves cannot run
/// back to back without the user acting in between.
enum PodActivationStage {
  /// Explaining that activation binds the pod to this app for good.
  explaining,

  /// Finding, pairing and priming a pod that is not on the body yet.
  priming,

  /// Primed. Waiting for the user to attach it and confirm.
  attachPod,

  /// Programming basal and alerts, then seating the cannula.
  starting,

  /// The pod is running.
  running,

  /// Something went wrong; [PodActivationController.failure] says what.
  failed,
}

/// Drives a pod from a sealed package to running insulin.
///
/// Resumable by design. Every protocol step is written to [PodStore] before the
/// next one runs, so an interruption — a crash, a closed app, a pod out of range
/// — continues where it stopped rather than starting over. Starting over would
/// re-send commands the pod has already carried out, two of which deliver insulin.
class PodActivationController extends ChangeNotifier {
  PodActivationController({
    required this.store,
    required this.confirmCannulaInsertion,
    PodConnection? connection,
    this.permissions = const PodBlePermissions(),
  }) : _connection = connection ?? podConnectionFor(store);

  final PodStore store;

  /// Asked right before the cannula goes in. Supplied by the wizard, which puts
  /// the device biometric behind it.
  final Future<bool> Function() confirmCannulaInsertion;

  /// Asked for the Bluetooth permissions before the first scan, since a pump user
  /// who never set up a sensor has never been asked for them.
  final PodBlePermissions permissions;

  final PodConnection _connection;

  PodActivationStage _stage = PodActivationStage.explaining;
  String? _failure;
  String? _failureKey;
  bool _cancelled = false;
  bool _stopped = false;
  bool _disposed = false;
  PodActivationFacts? _facts;
  String? _progressKey;
  int? _podUniqueId;
  PodSession? _session;

  PodActivationStage get stage => _stage;

  /// Why activation stopped, or null. Sticky until the next attempt.
  ///
  /// Raw diagnostic text — an exception message. The UI shows it under a
  /// localized headline, so it reads as detail rather than as instruction.
  String? get failure => _failure;

  /// A locale key for failures the user has to ACT on, where a raw exception
  /// string would be no help. Preferred over [failure] when present.
  String? get failureKey => _failureKey;

  /// What the activation is doing right now, as a locale key, or null while it
  /// is not working. Detail under the stage headline, so the user can see the
  /// pod being found, bound and filled instead of watching one spinner for a
  /// minute and a half.
  String? get progressKey => _progressKey;

  /// Whether the last attempt stopped because the cannula confirmation was
  /// declined. Not a failure — the pod is untouched — so it reads differently.
  bool get wasCancelled => _cancelled;

  /// Whether the user has asked to stop the attempt and it is still winding down.
  bool get isStopping => _stopped && isBusy;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Notifies only while the wizard is still on screen.
  ///
  /// The user may leave mid-operation — that is the whole point of being able to
  /// stop one — and the call still in flight lands afterwards, on a controller the
  /// route has already disposed.
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Stops the attempt in flight: ends the scan, drops the link, and puts the
  /// wizard back where the user can act.
  ///
  /// Nothing recorded is thrown away. Every protocol step is written before the
  /// next one runs, so a stopped activation picks up exactly where it got to. What
  /// has already happened to the pod cannot be undone — a primed pod stays primed —
  /// but nothing is lost by stopping, and a pod left mid-activation is reachable
  /// again from this same wizard.
  Future<void> stopAttempt() async {
    if (!isBusy || _stopped) {
      return;
    }
    _stopped = true;
    _notify();
    await _connection.stop();
  }

  /// What the pod reported about itself, once it has been asked — from this run,
  /// or from the interrupted one this is picking up.
  PodActivationFacts? get facts => _facts ?? _storedFacts;

  /// What an earlier attempt recorded, or null if it never got that far.
  PodActivationFacts? get _storedFacts {
    final stored = store.activationFacts;
    if (stored == null || stored.isEmpty) {
      return null;
    }
    return PodActivationFacts.fromJson(
      jsonDecode(stored) as Map<String, dynamic>,
    );
  }

  bool get isBusy =>
      _stage == PodActivationStage.priming ||
      _stage == PodActivationStage.starting;

  /// Whether the pod is already on the body, so the attach stage is being resumed
  /// rather than reached for the first time.
  ///
  /// Programming the basal only ever happens after the user has confirmed the pod
  /// is attached, so anything past that step proves it is on. Without this the
  /// resume would tell a user wearing a pod to attach it.
  bool get isAlreadyAttached =>
      !storedStep.isBefore(PodActivationStep.basalSet) &&
      storedStep != PodActivationStep.running;

  /// How far the protocol got, from the durable record.
  PodActivationStep get storedStep {
    final stored = store.activationStep;
    return PodActivationStep.values.firstWhere(
      (step) => step.name == stored,
      orElse: () => PodActivationStep.notStarted,
    );
  }

  /// Whether an activation was interrupted and can be picked up.
  ///
  /// A PAIRED pod counts even with no step recorded. The key is stored the
  /// instant it exists, which is before the first step is written, so a failure
  /// in between leaves exactly that: a pod bound to this app that no protocol
  /// step describes. Treating it as "nothing to resume" would strand it.
  bool get canResume =>
      (storedStep != PodActivationStep.notStarted || store.hasPod) &&
      storedStep != PodActivationStep.running;

  /// Places the user at the right stage for a stored activation, so reopening the
  /// wizard continues instead of offering to start a second pod.
  ///
  void restoreStage() {
    final step = storedStep;
    if (step == PodActivationStep.running) {
      _stage = PodActivationStage.running;
    } else if (step.isBefore(PodActivationStep.primed)) {
      _stage = PodActivationStage.explaining;
    } else {
      _stage = PodActivationStage.attachPod;
    }
    _notify();
  }

  /// Phase one: pair a pod and prime it, with the pod still off the body.
  Future<void> primePod() async {
    if (!await permissions.ensure()) {
      _fail(
        'Bluetooth permission is needed to find the pod',
        messageKey: 'pump.activate.no_permission',
      );
      return;
    }
    _stopped = false;
    _enter(PodActivationStage.priming);
    _reportProgress('searching');
    try {
      final activation = await _openActivation();
      try {
        _facts = await activation.primePod(from: storedStep);
      } finally {
        await _persistSequence(activation);
      }
      await _logActivationDelivery(PodDeliveryKind.prime);
      _enter(PodActivationStage.attachPod);
      unawaited(_buzzReadyToAttach());
      // The user now leaves the phone to attach the pod, which is the longest
      // gap in the whole activation. Mirror before it, not after.
      await _mirrorPairing();
    } catch (error) {
      _stoppedOrFailed(error);
    } finally {
      _session = null;
      await _connection.close();
    }
  }

  /// Buzzes twice once the pod is primed and can go on the body.
  ///
  /// Priming runs about a minute with nothing to tap, so the user has usually
  /// looked away by the time it finishes. Not awaited by the caller: a phone
  /// that cannot buzz must not fail the activation. Follows the system's touch
  /// feedback setting, so it stays still where that is switched off.
  Future<void> _buzzReadyToAttach() async {
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await HapticFeedback.vibrate();
  }

  /// Phase two: program the schedule and seat the cannula, once the user has
  /// confirmed the pod is on the body.
  ///
  /// [basalProgram] is the schedule the pod will run unattended for its whole
  /// life, so a profile that cannot be represented has to be rejected before this
  /// is reached rather than approximated here.
  Future<void> startDelivery(PodBasalProgram basalProgram) async {
    _clearCancelled();
    _stopped = false;
    _enter(PodActivationStage.starting);
    if (!await _runDelivery(basalProgram)) {
      return;
    }
    _enter(PodActivationStage.running);
    await _logActivationDelivery(PodDeliveryKind.cannula);
    await _recordRunningPod(basalProgram);
  }

  /// The protocol half. Returns whether the pod came out of it delivering.
  Future<bool> _runDelivery(PodBasalProgram basalProgram) async {
    try {
      final activation = await _openActivation();
      try {
        final podFacts = facts ?? await activation.primePod(from: storedStep);
        _facts = podFacts;
        await activation.startDelivery(
          from: storedStep,
          facts: podFacts,
          basalProgram: basalProgram,
        );
        return true;
      } finally {
        await _persistSequence(activation);
      }
    } on PodActivationCancelled {
      _cancelled = true;
      _enter(PodActivationStage.attachPod);
      return false;
    } catch (error) {
      _stoppedOrFailed(error);
      return false;
    } finally {
      _session = null;
      // Closed before the mirror that follows, because closing records where the
      // message-packet counter stands and the mirror is what a restored app
      // resumes it from.
      await _connection.close();
    }
  }

  /// Pushes the pairing to the account as soon as the key exists.
  ///
  /// The key is what makes a pod reachable, and it cannot be renegotiated: a pod
  /// answers only the controller that activated it, once, for good. Storing it
  /// locally is not enough on its own, because the device holding it can be
  /// reset, reinstalled or lost — and a pod already bound to a key nobody has is
  /// a pod that will keep delivering with nothing able to stop it.
  ///
  /// So this runs at pairing time and again before the user walks off to attach
  /// the pod, rather than waiting for the activation to finish. Everything
  /// between those points is a window in which the local copy is the only copy.
  ///
  /// Never allowed to fail the activation: a pod in hand beats a mirror, and the
  /// next successful operation pushes the same blob again.
  Future<void> _mirrorPairing() async {
    final mirrored = await _mirrorQuietly();
    if (mirrored) {
      debugPrint('pod activation: key mirrored to the account');
      return;
    }
    // Said out loud, not swallowed. This is the only copy of a credential that
    // cannot be renegotiated, and the user is the only one who can decide
    // whether to carry on without it.
    debugPrint('pod activation: the account copy of the key FAILED');
    _failure =
        'The pod is paired, but its key could not be saved to your '
        'account. Resetting the app would lose this pod for good.';
    _notify();
  }

  Future<bool> _mirrorQuietly() async {
    try {
      return await PumpSync().sync(store);
    } catch (error) {
      debugPrint('pod activation: mirroring the key THREW: $error');
      return false;
    }
  }

  /// Records what an activation step consumed from the reservoir.
  ///
  /// Neither volume reaches the user, but both leave the reservoir, so a log that
  /// left them out would not add up against what the pod reports it has left.
  Future<void> _logActivationDelivery(PodDeliveryKind kind) async {
    final pulses = kind == PodDeliveryKind.prime
        ? facts?.primePulses
        : facts?.cannulaInsertionPulses;
    if (pulses == null) {
      return;
    }
    await store.recordDelivery(
      PodDelivery(
        at: DateTime.now(),
        units: pulses * PodBolusAmount.pulseUnits,
        kind: kind,
      ),
    );
  }

  /// Bookkeeping for a pod that is ALREADY in the body and delivering.
  ///
  /// A failure here is reported but NEVER turns the wizard back to "failed". The
  /// pod is running; a screen that says the activation stopped invites the user to
  /// discard it, and discarding means throwing away the only key to a pod that is
  /// putting insulin into them.
  Future<void> _recordRunningPod(PodBasalProgram basalProgram) async {
    try {
      await _startBasalAccounting(basalProgram);
      await PumpSync().sync(store);
    } catch (error) {
      _failure = 'The pod is running, but recording it failed: $error';
      _notify();
    }
  }

  /// Opens a session and wires an activation onto it.
  ///
  /// A pod that has been paired but not yet given its id still advertises the
  /// discovery address, so the scan target depends on how far the interrupted
  /// activation got.
  Future<PodActivation> _openActivation() async {
    // Same per-isolate cache rule as everywhere else: the background service may
    // have advanced the counters since this screen was opened.
    await store.reload();
    final step = storedStep;
    // A stored key means this pod is ALREADY paired, whatever the step says — the
    // key is written the instant it is derived, so a crash between pairing and the
    // first recorded step leaves exactly that state. Pairing again would derive a
    // second key for a pod that already holds one, which is how a pod is lost.
    if (step == PodActivationStep.notStarted && !store.hasPod) {
      final started = await _connection.beginActivation(
        // Called the moment the pod is found and before anything is sent to it,
        // which is the only place that knows the search is over.
        confirmIrreversible: (_) async {
          _reportProgress('found');
          return true;
        },
      );
      _podUniqueId = started.podUniqueId;
      _session = started.session;
      await _mirrorPairing();
      return _activationOn(started.podUniqueId);
    }
    _reportProgress('connecting');
    _session = await _openSession();
    return _activationOn(_podUniqueId ?? store.uniqueId!);
  }

  /// Opens a session on a pod that is already paired.
  ///
  /// Always looks for the ASSIGNED id. A pod adopts the address it was given in
  /// SP1 as soon as pairing completes, well before the activation command that
  /// formally sets its id — real hardware advertises 0x1091 while still reporting
  /// lifecycle `filled`. Searching for the discovery address here found nothing
  /// and stalled every resumed activation.
  Future<PodSession> _openSession({bool allowScan = true}) async {
    return _connection.openSession(allowScan: allowScan);
  }

  /// Drops the spent link and opens a fresh one.
  ///
  /// Called after the pod has been left alone long enough to hang up — priming
  /// takes close to a minute, and the pod closes an idle link. Reconnecting here,
  /// rather than letting the next read fail, is what the reference driver does at
  /// the same two points.
  Future<void> _reopenLink() async {
    await _connection.close();
    try {
      _session = await _openSession(allowScan: false);
      return;
    } on Exception {
      // The address is known and this process has just seen it, so connecting
      // straight to it is both faster and quieter than a scan. Falling back to one
      // covers the pod having moved out of range and back while we waited — but
      // the half-open link of the failed attempt has to go first, or the app ends
      // up holding two GATT clients to the same pod.
      await _connection.close();
      _session = await _openSession();
    }
  }

  /// Commands go through the CURRENT session, looked up per call, so a reconnect
  /// takes effect without rebuilding the activation around it.
  Future<PodResponse> _send(PodCommand command) {
    final session = _session;
    if (session == null) {
      throw PodActivationException('No pod session is open');
    }
    return session.run(command);
  }

  PodActivation _activationOn(int podUniqueId) {
    return PodActivation(
      sendCommand: _send,
      podUniqueId: podUniqueId,
      onStep: (step) async {
        await store.saveActivationStep(step.name);
        _reportProgress(step.name);
      },
      confirmCannulaInsertion: confirmCannulaInsertion,
      reopenLink: _reopenLink,
      onFacts: (facts) => store.saveActivationFacts(jsonEncode(facts.toJson())),
      knownFacts: facts,
      startFromSequence: store.commandSequence,
    );
  }

  /// Hands the pod command counter on to whatever talks to the pod next.
  ///
  /// Without this the activation's numbers would be forgotten and the next command
  /// would start again at one — a number this pod has already run. The pod treats a
  /// repeat as the command it already carried out, so a bolus would be quietly
  /// ignored while the app recorded it as given.
  Future<void> _persistSequence(PodActivation activation) =>
      store.saveCommandSequence(activation.commandSequence);

  /// A stop the user asked for is not a failure: the wizard simply returns to the
  /// stage the durable record puts it at, with no alarm text, because nothing went
  /// wrong and the attempt can be picked up again.
  ///
  /// Reached from a catch-all rather than `on Exception`, deliberately. A plugin
  /// that throws an `Error` instead — flutter_blue_plus does, on a platform it does
  /// not support — would otherwise escape and leave the wizard stuck on its
  /// spinner, which is the one state the user cannot get out of.
  void _stoppedOrFailed(Object error) {
    debugPrint(
      'pod activation: ${_stopped ? 'stopped' : 'threw'} '
      'at ${storedStep.name}: $error',
    );
    if (_stopped) {
      restoreStage();
      return;
    }
    _fail('$error');
  }

  /// Names the activity now under way. [step] carries the protocol step's own
  /// name, converted to the snake_case the locale files use, so a step added to
  /// [PodActivationStep] needs only its text and no wiring here.
  void _reportProgress(String step) {
    _progressKey =
        'pump.activate.progress.'
        '${step.replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}')}';
    _notify();
  }

  void _enter(PodActivationStage stage) {
    debugPrint('pod activation: ${stage.name} (step ${storedStep.name})');
    _stage = stage;
    _progressKey = null;
    if (stage != PodActivationStage.failed) {
      _failure = null;
      _failureKey = null;
    }
    _notify();
  }

  /// Reports a fingerprint the user declined at the button, before anything was
  /// sent. Reads the same as a decline at the command, because it is one.
  void reportCannulaDeclined() {
    _cancelled = true;
    _enter(PodActivationStage.attachPod);
  }

  /// Clears the declined-confirmation notice, so it does not outlive the attempt
  /// the user is now retrying.
  void _clearCancelled() {
    _cancelled = false;
  }

  void _fail(String reason, {String? messageKey}) {
    debugPrint('pod activation: FAILED at ${storedStep.name}: $reason');
    _failure = reason;
    _failureKey = messageKey;
    _stage = PodActivationStage.failed;
    _notify();
  }

  /// Abandons the attempt and forgets the pod.
  ///
  /// Only safe for a pod that never started delivering. A primed pod has insulin
  /// in it but has not been told to run a schedule, so discarding it is the same
  /// as throwing the pod away — which is the right outcome for a failed
  /// activation, and why this is offered rather than a silent retry loop.
  ///
  /// Once the cannula command has gone out, this REFUSES. The pod may be in the
  /// body and delivering, and forgetting it throws away the only key that can stop
  /// it — the one outcome the whole design exists to prevent. Such a pod is
  /// deactivated from the pump page instead, which stops it first.
  Future<void> discardAttempt() async {
    if (!storedStep.isBefore(PodActivationStep.insertingCannula)) {
      _fail(
        'This pod has a cannula in the body and may be delivering',
        messageKey: 'pump.activate.discard_refused',
      );
      return;
    }
    // The account, too. Pairing mirrors the key the moment it succeeds, which is
    // before the cannula goes in, so a pod abandoned here is already on file and
    // would be offered back at the next launch.
    await PodBackupRestore(store).letGo();
    _facts = null;
    _podUniqueId = null;
    _enter(PodActivationStage.explaining);
  }

  /// Remembers the schedule the pod is now running and opens the basal ledger.
  ///
  /// The rates are sampled from the program rather than taken from the user's
  /// profile: the profile can be edited afterwards, while this has to stay what the
  /// POD was told, since that is what it delivers and what the forecasting model
  /// needs to see.
  ///
  /// The ledger starts now with nothing booked, so the first poll bills only the
  /// stretch since activation and not the whole day.
  Future<void> _startBasalAccounting(PodBasalProgram program) async {
    await store.saveBasalRates(PodController.hourlyRatesOf(program));
    await store.startBasalAccounting(DateTime.now());
  }
}
