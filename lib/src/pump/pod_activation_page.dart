import 'package:flutter/material.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/pump/pod_activation_stage_view.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Opens the activation wizard.
///
/// The cannula confirmation is wired in here, at the point where a
/// [BuildContext] exists to prompt with. It goes through the same [BiometricAuth]
/// that gates a bolus, and with the same setting: biometric only, no PIN
/// fallback. Driving a needle into the body is not something a pocket-tap should
/// be able to do.
void openPodActivation(BuildContext context) {
  final store = context.read<PodController>().store;
  final gate = context.read<PodDeliveryGate>();
  final reason = Locales.string(context, 'pump.activate.confirm_reason');
  final auth = BiometricAuth();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => PodActivationController(
          store: store,
          gate: gate,
          confirmCannulaInsertion: () => auth.confirm(reason),
        )..restoreStage(),
        child: const PodActivationPage(),
      ),
    ),
  );
}

/// Walks the user through starting a pod: acknowledge the binding, prime it off
/// the body, attach it, then let it start delivering.
///
/// The wizard never skips its own stages even when the protocol could continue
/// unattended — the pause at [PodActivationStage.attachPod] exists because the
/// pod has to physically move onto the body between the two halves, and no state
/// machine can know that happened.
class PodActivationPage extends StatelessWidget {
  const PodActivationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodActivationController>();
    final basal = _basal(context);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('pump.activate.title'),
        automaticallyImplyLeading: !controller.isBusy,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: PodActivationStageView(
                    controller: controller,
                    basalProblem: basal.problem,
                  ),
                ),
              ),
              if (controller.wasCancelled) _cancelled(context),
              if (controller.failure != null) _failure(context, controller),
              const SizedBox(height: 12),
              _actions(context, controller, basal),
            ],
          ),
        ),
      ),
    );
  }

  /// The pod schedule from the user's active basal profile.
  ///
  /// Converted up front so a profile the pod cannot hold is reported on the very
  /// first screen, rather than after the pod has already been primed and bound.
  PodBasalAdapter _basal(BuildContext context) =>
      PodBasalAdapter(context.watch<ProfileBasalState>().active);

  Widget _failure(BuildContext context, PodActivationController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 18, color: context.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.failureKey != null
                  ? Locales.string(context, controller.failureKey!)
                  : controller.failure!,
              style: TextStyle(fontSize: 13, color: context.danger),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when the fingerprint was declined. Deliberately not an error: nothing
  /// went wrong and the pod is untouched, so it explains rather than alarms.
  Widget _cancelled(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsBold.fingerprint, size: 18, color: context.warning),
          const SizedBox(width: 8),
          Expanded(
            child: LocaleText(
              'pump.activate.confirm_declined',
              style: TextStyle(fontSize: 13, color: context.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    PodActivationController controller,
    PodBasalAdapter basal,
  ) {
    if (controller.isBusy) {
      return const _BusyButton();
    }
    return switch (controller.stage) {
      PodActivationStage.explaining => _primaryButton(
          labelKey: 'pump.activate.start',
          icon: PhosphorIconsBold.magnifyingGlass,
          onPressed: basal.isProgrammable ? controller.primePod : null,
        ),
      PodActivationStage.attachPod => _primaryButton(
          labelKey: 'pump.activate.attached',
          icon: PhosphorIconsBold.fingerprint,
          onPressed: basal.isProgrammable
              ? () => controller.startDelivery(basal.program)
              : null,
        ),
      PodActivationStage.running => _primaryButton(
          labelKey: 'pump.activate.done',
          icon: PhosphorIconsBold.check,
          onPressed: () => Navigator.of(context).pop(),
        ),
      PodActivationStage.failed => _failedActions(context, controller, basal),
      _ => const _BusyButton(),
    };
  }

  /// After a failure the user gets both ways forward: try the same pod again,
  /// or give up on it. A retry resumes rather than restarting, so it cannot
  /// re-deliver the priming insulin.
  Widget _failedActions(
    BuildContext context,
    PodActivationController controller,
    PodBasalAdapter basal,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _primaryButton(
          labelKey: 'pump.activate.retry',
          icon: PhosphorIconsBold.arrowsClockwise,
          onPressed: () => controller.storedStep.isBefore(PodActivationStep.primed)
              ? controller.primePod()
              : controller.startDelivery(basal.program),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: context.danger),
          onPressed: controller.discardAttempt,
          icon: const Icon(PhosphorIconsBold.trash, size: 18),
          label: LocaleText('pump.activate.discard'),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String labelKey,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      onPressed: onPressed,
      icon: Icon(icon),
      label: LocaleText(labelKey),
    );
  }

}

/// A disabled button with a spinner, shown while the pod is being talked to.
class _BusyButton extends StatelessWidget {
  const _BusyButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      onPressed: null,
      icon: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      label: LocaleText('pump.activate.working'),
    );
  }
}
