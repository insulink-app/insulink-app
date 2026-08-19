import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_activation_page.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
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
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed:
          controller.isBusy ? null : () => openPodActivation(context),
      icon: const Icon(PhosphorIconsBold.plus, size: 20),
      label: LocaleText('pump.action.activate'),
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
    return IconButton(
      onPressed: controller.isBusy ? null : controller.refresh,
      tooltip: Locales.string(context, 'pump.action.refresh'),
      icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 20),
    );
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
        onPressed:
            controller.isBusy ? null : () => openTempBasalSheet(context),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: context.warning,
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: context.warning.withValues(alpha: 0.4)),
      ),
      onPressed: controller.isBusy ? null : controller.cancelTemporaryBasal,
      icon: const Icon(PhosphorIconsBold.prohibit, size: 20),
      label: Text(
        Locales.string(context, 'pump.temp.running')
            .replaceFirst('#', temporary.unitsPerHour.toStringAsFixed(2)),
      ),
    );
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
      onPressed:
          controller.isBusy ? null : () => _confirm(context, controller),
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
            LocaleText('pump.action.deactivate',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LocaleText('pump.stop.body',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
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


/// Offers to send an edited basal profile to a pod that is still running the old
/// one.
///
/// Only appears when the two actually differ. The pod holds its whole schedule
/// itself, so until this is tapped the app shows one schedule and the pod
/// delivers another — which is exactly the mismatch worth naming out loud.
class PodBasalOutOfDateNotice extends StatelessWidget {
  const PodBasalOutOfDateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final basal = PodBasalAdapter(context.watch<ProfileBasalState>().active);
    if (!basal.isProgrammable || !controller.runsDifferentBasalThan(basal.program)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PumpNotice.problem('pump.basal.out_of_date'),
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
