import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/demo_pod.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/pump/pod_backup_restore.dart';
import 'package:insulink/src/pump/pod_connection.dart';
import 'package:insulink/src/pump/pod_retry.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';
import 'package:insulink/src/pump/protocol/pod_basal_command.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';

/// The UI's view of the pod, and the few operations it can start.
///
/// Each operation opens a session, does one thing, and closes it — the pod does
/// not hold a link open, so there is no connection to keep alive between taps.
///
/// What a delivery is allowed to be is decided by [PodDeliveryGuard], on the dose
/// and the pod's own reported state — not by a mode the user can be in.
class PodController extends ChangeNotifier {
  PodController({
    required this.store,
    this.retry = const PodRetry(),
    PodConnection? connection,
  })  : _sequence = store.commandSequence,
        // Opens on the last status anyone read, usually the background poll's.
        // Without it the page began every visit blank, several seconds of a
        // spinner before it could say whether the pod was even delivering.
        _status = store.lastStatus,
        _statusReadAt = store.lastStatusAt,
        _connection = connection ?? podConnectionFor(store);

  static const int _fixedNonce = podFixedNonce;

  final PodStore store;

  /// How a failed operation is repeated. Injectable so tests need not wait out
  /// the real backoff.
  final PodRetry retry;
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
  ///
  /// Through [_absorb] like every other reply. It used to assign the two fields
  /// itself, which quietly meant the ONE operation whose whole job is reading the
  /// pod was also the one that never wrote the result down: no cached status for
  /// the next page open, and nothing for [PodStore.saveLastStatus] to learn the
  /// activation state from. A pod adopted from the account was read successfully
  /// and still came back as "activation unfinished".
  Future<void> refresh() => _withSession('refresh', (session) async {
        await _absorb(await _readStatus(session));
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
        // Remember that WE stopped it, so the background watch does not report a
        // deliberate suspend as the pod having stopped on its own.
        await store.setSuspendedByUs(true);
        // A suspend-everything cuts a running bolus short as well, so its record
        // has to be closed here too, or the overview keeps counting a dose the
        // pod has stopped delivering.
        await _endRunningBolus();
        await _absorb(response);
      });

  /// Puts the pod back on its schedule after a suspend.
  ///
  /// Resuming IS programming the basal schedule: the pod has no separate resume,
  /// and a suspend leaves it holding no schedule to go back to. So the caller
  /// passes the profile it should run, exactly as an activation does.
  ///
  /// Without this a suspended pod could only ever be deactivated, which means
  /// thrown away — a full pod in the bin for the sake of a pause.
  Future<void> resumeDelivery(PodBasalProgram program) =>
      _programBasal('resume delivery', program);

  /// Sends an edited basal profile to a pod that is already running.
  ///
  /// The pod holds its whole schedule itself and runs it unattended, so editing
  /// the profile in the app changes nothing until it is sent. Until then the app
  /// would show one schedule while the pod delivered another.
  Future<void> applyBasalProfile(PodBasalProgram program) =>
      _programBasal('send the basal profile', program);

  /// Programs [program] and records it as the schedule the POD is now running.
  ///
  /// Recording it matters as much as sending it: the ledger that feeds the
  /// forecasting model bills against these rates, so a pod reprogrammed without
  /// updating them would have its insulin booked at the old schedule.
  Future<void> _programBasal(String what, PodBasalProgram program) =>
      _withSession(what, (session) async {
        final response = await _programBasalDelivery(
          session,
          () => PodProgramBasalCommand(
            uniqueId: store.uniqueId!,
            sequenceNumber: _nextSequence,
            nonce: _fixedNonce,
            program: program,
            now: DateTime.now(),
          ),
        );
        await store.saveBasalRates(hourlyRatesOf(program));
        await store.setSuspendedByUs(false);
        await _absorb(response);
      });

  /// **The only way a basal schedule or a temporary rate is programmed.**
  ///
  /// The pod holds ONE basal delivery. A program arriving while a temporary rate
  /// is in progress leaves it with two answers to the same question, and a real
  /// pod answered exactly that with alarm 0x31 and a stopped delivery: an edited
  /// profile was sent while the automation held 0.0 U/h. So the temporary rate is
  /// ended first, in this session, before the new program goes out.
  ///
  /// It exists as a chokepoint rather than as a step each caller remembers,
  /// because that is precisely what failed: three call sites needed the step and
  /// one of them did not have it. A caller that reaches for
  /// [PodProgramBasalCommand] or [PodProgramTempBasalCommand] without coming
  /// through here is the bug coming back.
  ///
  /// **Judged from the POD, not from the app.** [activeTemporaryBasal] is what
  /// this app believes, and the automation runs in the other isolate: it can set
  /// a rate this isolate's cache has never seen, and the store would then say
  /// there is nothing to cancel while the pod is mid-delivery. The status is read
  /// fresh here, in the same session, and its answer is the one that counts.
  Future<PodResponse> _programBasalDelivery(
    PodSession session,
    PodCommand Function() build,
  ) async {
    final status = await _readStatus(session);
    await _absorb(status);
    if (status.delivery.isTempBasalRunning) {
      await _endRunningTempBasal(session);
    }
    return session.run(build());
  }

  /// Ends a temporary rate the pod says it is running.
  ///
  /// Silent, because the user asked for a profile or a rate change and not for a
  /// cancel: a beep here would report a step they never took.
  Future<void> _endRunningTempBasal(PodSession session) async {
    final response = await session.run(PodStopDeliveryCommand(
      uniqueId: store.uniqueId!,
      sequenceNumber: _nextSequence,
      nonce: _fixedNonce,
      target: PodDeliveryTarget.tempBasal,
      beep: PodBeep.silent,
    ));
    final running = store.temporaryBasal;
    if (running != null) {
      await store.saveTemporaryBasal(running.endedAt(DateTime.now()));
    }
    await _absorb(response);
  }

  /// One rate per hour, sampled from [program] at the middle of each hour so a
  /// half-hour boundary cannot land on the wrong side of it.
  static List<double> hourlyRatesOf(PodBasalProgram program) {
    final midnight = DateTime(2026);
    return [
      for (var hour = 0; hour < 24; hour++)
        program.rateAt(midnight.add(Duration(hours: hour, minutes: 15))),
    ];
  }

  /// Whether the app still knows which schedule the pod was given.
  ///
  /// False after a restore from the account, which brings back the key and the
  /// counters but no record of what was programmed. The pod is unaffected by
  /// that: it holds its schedule itself and goes on delivering it. Only the app
  /// has forgotten, and telling those two apart is the difference between "your
  /// profile changed" and "we lost track of yours".
  bool get knowsPodSchedule => store.basalRates != null;

  /// Whether the pod is running a schedule other than [program].
  ///
  /// Answered from the rates the pod was PROGRAMMED with, not from the user's
  /// profile, because that is the only record of what the pod is actually doing.
  ///
  /// NOT KNOWING counts as different. Only "no pod" answers false here: there is
  /// nothing to send a schedule to. A paired pod with no record of what it was
  /// given is the state a restore from the account leaves behind, and treating
  /// that as "already matches" was a dead end with no way out of it — the notice
  /// offering to send the profile is hidden exactly when the app has no schedule
  /// on file, while the automation refuses to start for want of that same
  /// schedule. Unknown is not agreement; the schedule has to be sent.
  bool runsDifferentBasalThan(PodBasalProgram program) {
    if (!hasPod) {
      return false;
    }
    final onPod = store.basalRates;
    if (onPod == null) {
      return true;
    }
    final wanted = hourlyRatesOf(program);
    for (var hour = 0; hour < 24; hour++) {
      if ((onPod[hour] - wanted[hour]).abs() > 1e-9) {
        return true;
      }
    }
    return false;
  }

  /// Picks up a pod the activation wizard just paired.
  ///
  /// The wizard writes through the same store, but nothing tells this controller
  /// to look again — so the page it returns to would keep saying there is no pod
  /// until it is rebuilt from scratch.
  Future<void> adoptActivatedPod() async {
    await store.reload();
    notifyListeners();
    await refreshIfStale();
  }

  /// Forgets the stopped-bolus notice once the user has seen it.
  void clearCancelledBolus() {
    _cancelledBolus = null;
    notifyListeners();
  }

  /// Reads the pod when what is on screen is too old to act on.
  ///
  /// The pump page opens on this. Without it the page sits on "not read yet" until
  /// the user asks, which means it cannot say whether the pod is delivering — and
  /// a page that cannot say that has to show the control that STOPS delivery,
  /// even when the pod is in fact already stopped.
  ///
  /// Bounded by the same window the delivery guard uses, so opening the page twice
  /// in a minute costs one session, not two.
  ///
  /// A pod that is paired but not yet ACTIVATED is left alone: it refuses a status
  /// request with an illegal-command-state NAK, because in that state it accepts
  /// only the activation sequence. Asking anyway is noise on a link that has an
  /// activation waiting to finish on it.
  ///
  /// A pod with NO activation record is read, though. That is a pod adopted from
  /// the account ([PodStore.activationUnknown]), which has no wizard waiting on
  /// its link and is most likely long since running — the read is what finds out,
  /// and [PodStore.saveLastStatus] writes down what it learns.
  Future<void> refreshIfStale() async {
    if (!hasPod || _busy || !(store.isActivated || store.activationUnknown)) {
      return;
    }
    final age = statusAge;
    if (age != null && age <= _refreshOnOpenAfter) {
      return;
    }
    await refresh();
  }

  /// How long a status stays worth trusting for a DELIVERY. Matches
  /// [PodDeliveryGuard], and drives the stale notice on the page.
  static const Duration statusFreshFor = Duration(minutes: 2);

  /// How old the shown status may be before opening the page reads the pod again.
  ///
  /// Deliberately longer than [_statusFreshFor], because these are different
  /// questions. Two minutes is how fresh a status must be to DOSE against; it is
  /// far too strict for whether a page needs to open a radio link before it can
  /// draw. The background watch refreshes the cache on its own poll anyway, so
  /// most visits now find it recent and read nothing.
  static const Duration _refreshOnOpenAfter = Duration(minutes: 5);

  /// The bolus the pod is working through, or null once it has run its course.
  ///
  /// Cleared lazily, on the way past: the record only matters while it is live,
  /// and clearing it on a timer would need a timer running for a pod that is
  /// usually doing nothing.
  PodRunningBolus? get runningBolus {
    final bolus = store.runningBolus;
    if (bolus == null || bolus.isFinished(DateTime.now())) {
      return null;
    }
    return bolus;
  }

  /// Tells listeners a bolus started. Called by [BolusDelivery], which writes the
  /// record through the store rather than through this class.
  void notifyRunningBolusChanged() => notifyListeners();

  /// Stops the bolus in progress and corrects the log to what the pod gave.
  ///
  /// The stop is a targeted one: basal keeps running, because a user cutting a
  /// bolus short is not asking to be taken off insulin entirely.
  ///
  /// The delivered amount is taken from the clock at the moment the stop went
  /// out, floored to a whole pulse. That is off by at most one pulse and errs
  /// towards understating what was given — the recoverable direction, since a
  /// user can always log more, while insulin credited but never received would
  /// suppress a correction they need.
  Future<void> cancelBolus() async {
    if (runningBolus == null) {
      return;
    }
    await _withSession('stop the bolus', (session) async {
      final response = await session.run(PodStopDeliveryCommand(
        uniqueId: store.uniqueId!,
        sequenceNumber: _nextSequence,
        nonce: _fixedNonce,
        target: PodDeliveryTarget.bolus,
      ));
      await _endRunningBolus();
      await _absorb(response);
    });
  }

  /// Closes the books on a bolus the pod has just been told to stop.
  ///
  /// Called from every path that stops one, not only from [cancelBolus]: a
  /// suspend-everything and a deactivation both cut a running bolus short too,
  /// and leaving the record behind would keep a progress bar counting insulin
  /// that is no longer flowing.
  ///
  /// Does nothing when no bolus was running, so the callers need no condition.
  Future<void> _endRunningBolus() async {
    final bolus = runningBolus;
    if (bolus == null) {
      await store.clearRunningBolus();
      return;
    }
    final given = bolus.deliveredUnits(DateTime.now());
    await store.amendDelivery(bolus.startedAt, given);
    await store.clearRunningBolus();
    _cancelledBolus = (programmed: bolus.programmedUnits, given: given);
  }

  /// What a stopped bolus actually amounted to, until the next operation clears
  /// it. The user has to be told, because the meal it was logged against still
  /// carries the full dose.
  ({double programmed, double given})? get cancelledBolus => _cancelledBolus;

  ({double programmed, double given})? _cancelledBolus;

  /// Whether the pod last reported itself stopped, so the page can offer the way
  /// back rather than a second stop.
  ///
  /// A pod that has not been read is NOT treated as suspended: with no reading to
  /// go on, the control that stops delivery is the one that has to be there.
  bool get isSuspended => _status?.delivery.isSuspended ?? false;

  /// Ends the pod's life so it can be removed, then forgets it.
  ///
  /// The pod is only forgotten once it reports that it can no longer deliver.
  /// Dropping the key while it still delivers would leave insulin running with
  /// nothing able to command it.
  ///
  /// Judged on the LIFECYCLE, not on the delivery status. A deactivated pod
  /// reports `PodLifecycleStatus.deactivated`, and its delivery byte is not
  /// required to read as a plain `suspended`; asking only that question left a
  /// pod that had genuinely shut down looking alive to the app, still paired,
  /// with no way to let go of it. [PodLifecycleStatus.acceptsDelivery] is the
  /// question actually being asked, and it also covers a pod in `alarm`, which
  /// has stopped for good and is never coming back either.
  Future<void> deactivatePod() => _withSession('deactivate', (session) async {
        final response = await session.run(PodDeactivateCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
        ));
        await _absorb(response);
        await _endRunningBolus();
        await _confirmItStopped(session);
        if (_reportsItCannotDeliver) {
          await _letGoOfPod();
        } else {
          _failure ??= 'Pod did not confirm it stopped. It was NOT forgotten';
        }
      });

  /// Asks the pod again while it still claims it can deliver.
  ///
  /// The reply to the deactivate command is not always the settled state: the
  /// pod answers before it has finished shutting down, and that answer is what
  /// left a pod that HAD stopped looking alive to the app. It is also the reply
  /// that may not be a status at all, in which case the state being judged is
  /// the stale cached one. Re-reading is the whole fix.
  ///
  /// ponytail: two extra reads, no state machine. A read that fails escapes to
  /// [_withSession], which retries the deactivate as a whole; a deactivate is
  /// safe to repeat.
  Future<void> _confirmItStopped(PodSession session) async {
    for (var attempt = 0; attempt < 2 && !_reportsItCannotDeliver; attempt++) {
      await Future<void>.delayed(stoppedConfirmationDelay);
      await _absorb(await _readStatus(session));
    }
  }

  /// How long the pod is given to settle between confirmation reads. Short
  /// enough that the user is still watching, long enough to outlast the shutdown.
  @visibleForTesting
  static Duration stoppedConfirmationDelay = const Duration(milliseconds: 800);

  /// Forgets the pod locally and tells the account it is gone. See
  /// [PodBackupRestore.letGo].
  Future<void> _letGoOfPod() => PodBackupRestore(store).letGo();

  /// Whether the pod's own last answer says it is not delivering and cannot be
  /// made to.
  bool get _reportsItCannotDeliver {
    final status = _status;
    if (status == null) {
      return false;
    }
    return !status.lifecycle.acceptsDelivery || status.delivery.isSuspended;
  }

  /// Drops a pod the app can no longer reach, WITHOUT deactivating it.
  ///
  /// The way out of a pod that has stopped where the app could not see it: it
  /// shut down on its own, or a deactivation half-succeeded, and the app is left
  /// holding a pairing for something that is never going to answer again. Every
  /// other path to forgetting requires the pod to confirm it stopped, so without
  /// this there was no way out at all and the pump page stayed occupied by a pod
  /// that no longer exists.
  ///
  /// It cannot check anything, which is the whole point: the pod is not
  /// answering. **The user is the check**, because they can see whether the thing
  /// is still on their body, so the UI states the consequence plainly and asks
  /// for the device biometric. A pod can never be paired a second time, so a key
  /// dropped while the pod is still delivering leaves nothing able to stop it.
  /// Available even while an operation is in flight, which is the whole point:
  /// what makes a pod unreachable is that the attempt to reach it is not
  /// finishing, so a control gated on "not busy" is unreachable exactly when it
  /// is needed. The attempt is stopped rather than waited out, and [_withSession]
  /// declines to write this pod's state back once the pairing is gone.
  Future<void> forgetUnreachablePod() async {
    await _connection.stop();
    await _letGoOfPod();
    _status = null;
    _statusReadAt = null;
    _failure = null;
    _busy = false;
    notifyListeners();
  }

  /// Makes the pod beep now, and re-states its reminder beeps while it is there.
  ///
  /// The only way to ask a pod for a sound on demand. Worth having: it answers
  /// whether the pod is in earshot and whether its beeper still works, which is
  /// exactly what you want to know BEFORE relying on it for an occlusion at three
  /// in the morning.
  ///
  /// Carries no nonce and starts no delivery, so it is safe to press at any time.
  Future<void> playTestBeep() => _withSession('beep', (session) async {
        final beepAtEnd = await NotificationSetting.podBolusBeep.load();
        final response = await session.run(PodProgramBeepsCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          bolusReminder: PodProgramReminder(atEnd: beepAtEnd),
        ));
        await _absorb(response);
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
        await _absorb(response);
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
  /// The store write is AWAITED, which it did not used to be. It was fire and
  /// forget while it only fed the next page open, but it now also carries what
  /// the pod says about its own activation — and [PodStore] fills its cache after
  /// the keystore write returns, so an unawaited one loses the race against the
  /// [notifyListeners] that follows. The page then rebuilt reading the old value
  /// and, with nothing left to notify it, stayed there.
  Future<void> _absorb(PodResponse response) async {
    if (response is PodStatusResponse) {
      _status = response;
      _statusReadAt = DateTime.now();
      await store.saveLastStatus(response, _statusReadAt!);
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
  /// Closed before the backend mirror goes out rather than only in the `finally`:
  /// closing is what records where the message-packet counter stands, and the
  /// mirror is what a restored app resumes that counter from. Closing twice is a
  /// no-op, so the `finally` still covers every path that threw.
  ///
  /// A [PodCommandOutcomeUnknown] is reported as exactly that: the command may
  /// have taken effect, so the message tells the user to check the pod rather
  /// than implying nothing happened.
  ///
  /// Retried while the failure left the pod untouched (see [PodRetry]), because
  /// most of what goes wrong here goes wrong during the connect and handshake,
  /// and telling the user it did not work when a second attempt would have
  /// worked is its own wrong answer. The retry starts at [_resyncFromStorage],
  /// so every attempt re-reads the PERSISTED command counter and therefore sends
  /// the same sequence number. That is what lets the pod recognise a repeat, and
  /// it is also why a failed attempt must not save the counter.
  Future<void> _withSession(
    String what,
    Future<void> Function(PodSession session) body,
  ) async {
    if (_busy) {
      return;
    }
    _busy = true;
    _failure = null;
    _cancelledBolus = null;
    notifyListeners();
    try {
      await retry.copyWith(onLog: debugPrint).run(what, () => _attempt(body));
      // Only for a pod we still have. [forgetUnreachablePod] can land while an
      // operation is in flight, precisely because that operation is what will
      // not finish, and writing this pod's counters back afterwards would put
      // half of it into the keystore again.
      if (store.hasPod) {
        await store.saveCommandSequence(_sequence);
      }
      await _connection.close();
      if (store.hasPod) {
        await PumpSync().sync(store, status: _status);
      }
    } on PodCommandOutcomeUnknown catch (error) {
      debugPrint('pod: $what outcome UNKNOWN: ${error.message}');
      _failure = 'The pod may have acted on this — check the pod. ${error.message}';
    } catch (error) {
      // Catch-all, not `on Exception`: a plugin that throws an `Error` would
      // otherwise vanish into an unhandled async error and the page would show
      // nothing at all about why the operation did nothing.
      debugPrint('pod: $what FAILED: $error');
      _failure = 'Could not $what: $error';
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }

  /// One try at [body] against a fresh session, dropping the link if it fails.
  ///
  /// The link is closed before the error escapes so the next attempt starts from
  /// nothing rather than inheriting a half-open one, and so the settle window the
  /// pod needs between links is measured from now.
  Future<void> _attempt(Future<void> Function(PodSession session) body) async {
    try {
      await _resyncFromStorage();
      final session = await _connection.openSession();
      await body(session);
    } catch (error) {
      await _connection.close();
      rethrow;
    }
  }

  /// Re-reads the store and adopts the command counter it holds.
  ///
  /// The store's cache is PER ISOLATE. The background service polls the pod every
  /// quarter of an hour and advances that counter; this isolate would otherwise
  /// keep using the value it read at app start and hand the pod a sequence number
  /// it has already run — which the pod refuses as a duplicate. Reading fresh here
  /// is the same discipline `CgmController` follows for its own store.
  Future<void> _resyncFromStorage() async {
    await store.reload();
    _sequence = store.commandSequence;
  }

  /// Programs a bolus on the pod and returns its answer.
  ///
  /// Unlike the maintenance operations this does NOT swallow failures into
  /// [failure]: the caller has to distinguish "refused" from "we do not know",
  /// because only the first one is safe to treat as "no insulin was given". A
  /// [PodCommandOutcomeUnknown] therefore propagates.
  ///
  /// Reads the pod and delivers in ONE session, with [refuseIf] judging the
  /// status that comes back. Two sessions back to back is what a separate status
  /// read used to cost, and the pod hangs up on the second: it drops a link
  /// opened immediately after the previous one closed. One session is also the
  /// truer check — the state the guard judges IS the state the pod is in when the
  /// dose is programmed, with no window in between for it to change.
  ///
  Future<PodResponse> sendBolus(
    PodBolusAmount amount, {
    required String? Function(PodStatusResponse status) refuseIf,
  }) async {
    if (store.uniqueId == null) {
      throw StateError('No pod is paired');
    }
    _busy = true;
    _failure = null;
    _cancelledBolus = null;
    notifyListeners();
    try {
      return await retry
          .copyWith(onLog: debugPrint)
          .run('send bolus', () => _attemptBolus(amount, refuseIf));
    } finally {
      await _connection.close();
      _busy = false;
      notifyListeners();
    }
  }

  /// One try: open a session, read the pod, judge it, program the dose.
  ///
  /// Everything before the bolus command is safe to repeat. Opening a session,
  /// reading a status and judging it change nothing about the pod, so a link that
  /// dropped during any of them leaves a pod that has been asked for nothing.
  ///
  /// The bolus command is where that stops. If it goes out and is not answered,
  /// [PodCommandOutcomeUnknown] escapes and [PodRetry] will not repeat it, because
  /// the pod may be delivering and a second attempt would be a second dose. The
  /// guard reading `isBolusing` cannot be relied on to catch that either: a small
  /// bolus can finish between the two attempts and leave the pod looking idle.
  Future<PodResponse> _attemptBolus(
    PodBolusAmount amount,
    String? Function(PodStatusResponse status) refuseIf,
  ) async {
    try {
      await _resyncFromStorage();
      final session = await _connection.openSession();
      final status = await _readStatus(session);
      await _absorb(status);
      final refusal = refuseIf(status);
      if (refusal != null) {
        throw PodBolusRefused(refusal);
      }
      // Asked fresh each time rather than held: the toggle lives in secure
      // storage and may have been changed on the panel since this screen opened.
      final beepAtEnd = await NotificationSetting.podBolusBeep.load();
      final response = await session.run(PodProgramBolusCommand(
        uniqueId: store.uniqueId!,
        sequenceNumber: _nextSequence,
        nonce: _fixedNonce,
        amount: amount,
        reminder: PodProgramReminder(atEnd: beepAtEnd),
      ));
      await store.saveCommandSequence(_sequence);
      await _connection.close();
      await PumpSync().sync(store, status: _status);
      await _absorb(response);
      return response;
    } on PodBolusRefused {
      rethrow;
    } catch (error) {
      await _connection.close();
      rethrow;
    }
  }

  /// Picks up credentials that were just written by a restore and reads the pod.
  ///
  /// The pod may simply be out of range, in which case the read fails but the
  /// credentials stay — discarding the only key to a pod that is still on the body
  /// is the one outcome worth avoiding.
  Future<void> adoptRestoredPod() async {
    _sequence = store.commandSequence;
    notifyListeners();
    await refresh();
  }

  /// Runs a temporary basal rate for a set time.
  ///
  /// The stretch is stored BEFORE the
  /// command goes out, so a confirmation lost in transit leaves the ledger
  /// crediting the temporary rate rather than the schedule — understating insulin
  /// is recoverable, claiming insulin the pod may not have delivered is not.
  Future<void> setTemporaryBasal(PodTempBasalRate rate) =>
      _withSession('set temporary basal', (session) async {
        // Asked fresh each time rather than held, like the bolus beep: the toggle
        // lives in secure storage and may have been changed since this screen
        // opened. Only the manual path reads it; the automation is silent
        // regardless, because it changes the rate every five minutes.
        final beeps = await NotificationSetting.podTempBasalBeep.load();
        final started = DateTime.now();
        await store.saveTemporaryBasal(PodTemporaryBasal(
          unitsPerHour: rate.unitsPerHour,
          start: started,
          end: started.add(Duration(minutes: rate.minutes)),
        ));
        final response = await _programBasalDelivery(
          session,
          () => PodProgramTempBasalCommand(
            uniqueId: store.uniqueId!,
            sequenceNumber: _nextSequence,
            nonce: _fixedNonce,
            rate: rate,
            reminder: PodProgramReminder(atEnd: beeps),
          ),
        );
        await _absorb(response);
      });

  /// Ends a running temporary basal, returning the pod to its schedule.
  ///
  /// Only ever returns delivery to what the user already programmed, so it asks
  /// for nothing beyond the tap.
  Future<void> cancelTemporaryBasal() =>
      _withSession('cancel temporary basal', (session) async {
        final beeps = await NotificationSetting.podTempBasalBeep.load();
        final response = await session.run(PodStopDeliveryCommand(
          uniqueId: store.uniqueId!,
          sequenceNumber: _nextSequence,
          nonce: _fixedNonce,
          target: PodDeliveryTarget.tempBasal,
          beep: beeps ? PodBeep.longSingleBeep : PodBeep.silent,
        ));
        final running = store.temporaryBasal;
        if (running != null) {
          await store.saveTemporaryBasal(running.endedAt(DateTime.now()));
        }
        await _absorb(response);
      });

  /// The temporary rate running right now, or null.
  PodTemporaryBasal? get activeTemporaryBasal {
    final temporary = store.temporaryBasal;
    return temporary != null && temporary.covers(DateTime.now())
        ? temporary
        : null;
  }
}

/// Thrown when a guard refused a bolus against the pod's freshly read state.
///
/// Distinct from a failure: nothing went wrong and nothing was sent, so the
/// caller may treat it as "no insulin was given" — which is exactly the
/// distinction a delivery path must never blur.
class PodBolusRefused implements Exception {
  PodBolusRefused(this.reason);

  final String reason;

  @override
  String toString() => 'PodBolusRefused: $reason';
}
