import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_activation_page.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_notice.dart';
import 'package:insulink/src/pump/pod_temp_basal_sheet.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Starts an activation. The wizard itself explains what activating does — it
/// primes the pod and binds it to this app for good — and asks before anything
/// irreversible happens.
class PodActivateButton extends StatelessWidget {
  const PodActivateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    // A pod that is already paired needs the wizard FINISHED, not started, and
    // the button has to say so: tapping "activate a pod" when one is half
    // activated reads like it would fetch a second one.
    final unfinished = controller.hasPod;
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: controller.isBusy ? null : () => openPodActivation(context),
      icon: Icon(
        unfinished ? PhosphorIconsBold.arrowRight : PhosphorIconsBold.plus,
        size: 20,
      ),
      label: LocaleText(
        unfinished ? 'pump.action.resume_activation' : 'pump.action.activate',
      ),
    );
  }
}

/// Re-reads the pod, as the icon beside the detail heading.
///
/// An icon rather than a full-width button because it does not change anything:
/// it only refreshes what is already on screen, which is what the heading it sits
/// next to describes.
class PodRefreshButton extends StatelessWidget {
  const PodRefreshButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final stale = _isStale(controller);
    return IconButton(
      onPressed: controller.isBusy ? null : controller.refresh,
      tooltip: Locales.string(
        context,
        stale ? 'pump.status.stale' : 'pump.action.refresh',
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(PhosphorIconsBold.arrowsClockwise, size: 20),
          if (stale) _staleDot(context),
        ],
      ),
    );
  }

  /// A dot on the control that fixes it, instead of a banner saying so.
  ///
  /// The old notice was a full-width card explaining that the reading was a few
  /// minutes old, which is the ordinary resting state of a pod nobody has just
  /// read: the page carried a warning most of the time it was open, and a warning
  /// that is always there is one nobody reads. The dot says the same thing where
  /// the answer is, and the tooltip still spells it out.
  Widget _staleDot(BuildContext context) {
    return Positioned(
      right: -1,
      top: -1,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: context.warning,
          shape: BoxShape.circle,
          // Cut out of the icon rather than floating on it, so the dot reads as
          // a mark ON the control at any icon size.
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  /// Whether the shown status is too old to base a delivery on. The same window
  /// the guard enforces, read from the controller rather than repeated.
  bool _isStale(PodController controller) {
    final age = controller.statusAge;
    return age != null && age > PodController.statusFreshFor;
  }
}

/// Starts or ends a temporary basal rate.
///
/// One control, two faces: while a temporary rate runs it becomes the way to end
/// it, named with the rate it is ending, so the page never shows a "set" button
/// for something already set.
class PodTempBasalButton extends StatelessWidget {
  const PodTempBasalButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final temporary = controller.activeTemporaryBasal;
    if (temporary == null) {
      return SecondaryActionButton(
        labelKey: 'pump.temp.set',
        icon: PhosphorIconsBold.timer,
        onPressed: controller.isBusy ? null : () => openTempBasalSheet(context),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: context.warning,
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: context.warning.withValues(alpha: 0.4)),
      ),
      onPressed: controller.isBusy
          ? null
          : () => _confirmEnd(context, controller, temporary),
      icon: const Icon(PhosphorIconsBold.prohibit, size: 20),
      label: Text(
        Locales.string(
          context,
          'pump.temp.running',
        ).replaceFirst('#', temporary.unitsPerHour.toStringAsFixed(2)),
      ),
    );
  }

  /// Asks before ending it, because the button sits where a mis-tap is easy and
  /// what it does is not obvious from its name.
  ///
  /// Ending a temporary rate does not merely stop something: it hands delivery
  /// back to the schedule. The common case is a rate of zero set before sport,
  /// where "end" means insulin STARTS again. A tap that resumes delivery is
  /// worth one question.
  ///
  /// Deliberately not the emergency stop, which suspends everything and stays
  /// one tap: a control that halts insulin must never be behind a step that can
  /// fail closed.
  void _confirmEnd(
    BuildContext context,
    PodController controller,
    PodTemporaryBasal temporary,
  ) {
    Alert(
      icon: PhosphorIconsBold.prohibit,
      iconColor: context.warning,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LocaleText(
              'pump.temp.end.title',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              Locales.string(
                context,
                'pump.temp.end.body',
              ).replaceFirst('#', temporary.unitsPerHour.toStringAsFixed(2)),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.temp.end.confirm',
      callback: controller.cancelTemporaryBasal,
    ).show(context);
  }
}

/// Acknowledges the pod's alerts so it stops beeping. Renders nothing when there
/// is nothing to acknowledge.
class PodSilenceAlertsButton extends StatelessWidget {
  const PodSilenceAlertsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final hasAlerts = controller.status?.activeAlerts.isNotEmpty ?? false;
    if (!hasAlerts) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SecondaryActionButton(
        labelKey: 'pump.action.silence',
        icon: PhosphorIconsBold.bellSlash,
        onPressed: controller.isBusy ? null : controller.silenceAlerts,
      ),
    );
  }
}

/// Ends the pod's life so it can be taken off, then forgets it.
///
/// Two gates, in this order: a confirmation that says what it does, then the
/// device biometric. Deactivating stops the insulin AND drops the key, so a
/// pocket-tap must not be able to reach it.
///
/// The biometric allows the device PIN as a fallback, unlike the one in front of
/// the cannula. Taking a pod OFF has to stay possible on a phone with no
/// fingerprint enrolled — and "Abgabe stoppen" above it is never gated at all,
/// because the emergency path must work whatever the phone thinks.
class PodDeactivateButton extends StatelessWidget {
  const PodDeactivateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return DangerActionButton(
      labelKey: 'pump.action.deactivate',
      icon: PhosphorIconsBold.trash,
      onPressed: controller.isBusy ? null : () => _confirm(context, controller),
    );
  }

  void _confirm(BuildContext context, PodController controller) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              'pump.action.deactivate',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            LocaleText(
              'pump.stop.body',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.action.deactivate_confirm',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () => _authThenDeactivate(context, controller),
    ).show(context);
  }

  /// A declined or failed check leaves the pod exactly as it was: still running,
  /// still paired, still stoppable.
  Future<void> _authThenDeactivate(
    BuildContext context,
    PodController controller,
  ) async {
    final confirmed = await BiometricAuth().confirm(
      Locales.string(context, 'pump.action.deactivate_auth_reason'),
      allowDeviceCredential: true,
    );
    if (confirmed) {
      await controller.deactivatePod();
    }
  }
}

/// Drops a pod the app cannot reach any more, without deactivating it.
///
/// The way out of a pod that stopped where the app could not see it: it shut
/// itself down, or a deactivation half-succeeded, and the pump page is left
/// occupied by something that will never answer again. Every other path to
/// forgetting waits for the pod to confirm it stopped, so without this there was
/// no way out at all.
///
/// Gated like the deactivation, and worded harder. Nothing here can be checked,
/// because the pod is not answering: the user is the check, since they are the
/// one who can see whether it is still on their body.
class PodForgetButton extends StatelessWidget {
  const PodForgetButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PodController>();
    // NOT gated on isBusy, unlike every other control here. What makes a pod
    // unreachable is that the attempt to reach it is not finishing, so a way out
    // that waits for the app to stop trying is no way out at all.
    return DangerActionButton(
      labelKey: 'pump.action.forget',
      icon: PhosphorIconsBold.linkBreak,
      onPressed: () => _confirm(context, controller),
    );
  }

  void _confirm(BuildContext context, PodController controller) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              'pump.forget',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            LocaleText(
              'pump.forget.body',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.action.forget_confirm',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () => _authThenForget(context, controller),
    ).show(context);
  }

  Future<void> _authThenForget(
    BuildContext context,
    PodController controller,
  ) async {
    final confirmed = await BiometricAuth().confirm(
      Locales.string(context, 'pump.action.forget_auth_reason'),
      allowDeviceCredential: true,
    );
    if (confirmed) {
      await controller.forgetUnreachablePod();
    }
  }
}

/// Offers to send the basal profile to a pod that is not known to be running it.
///
/// Two different situations, and they must not be worded the same. Either the
/// profile was edited and the pod still runs the old one, or the app has no
/// record of what the pod was given at all (a pod adopted from the account).
/// Saying "your profile has changed" in the second case states something that
/// did not happen, and reads as though the pod had stopped, which it has not.
class PodBasalOutOfDateNotice extends StatelessWidget {
  const PodBasalOutOfDateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final basal = PodBasalAdapter(context.watch<ProfileBasalState>().active);
    if (!basal.isProgrammable ||
        !controller.runsDifferentBasalThan(basal.program)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PumpNotice.problem(
            controller.knowsPodSchedule
                ? 'pump.basal.out_of_date'
                : 'pump.basal.unknown',
          ),
          const SizedBox(height: 10),
          SecondaryActionButton(
            labelKey: 'pump.basal.send',
            icon: PhosphorIconsBold.uploadSimple,
            onPressed: controller.isBusy
                ? null
                : () => controller.applyBasalProfile(basal.program),
          ),
        ],
      ),
    );
  }
}

/// Asks the pod to beep, as an icon in the pump page header.
///
/// A test, not an operation: it changes nothing about delivery, so it belongs
/// beside the log rather than among the controls that do. Sitting in the header
/// keeps it findable without putting it near anything that moves insulin.
class PodTestBeepButton extends StatelessWidget {
  const PodTestBeepButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return IconButton(
      onPressed: controller.isBusy || !controller.hasPod
          ? null
          : controller.playTestBeep,
      tooltip: Locales.string(context, 'pump.action.test_beep'),
      icon: const Icon(PhosphorIconsBold.speakerHigh, size: 22),
    );
  }
}
