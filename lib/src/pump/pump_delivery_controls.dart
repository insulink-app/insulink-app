import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/base/action_buttons.dart';

/// The one control that decides whether insulin is flowing: stop it, or put the
/// pod back on its schedule.
///
/// Which of the two is offered follows what the pod last REPORTED, not what the
/// app remembers doing. A pod that has not been read shows the stop, because with
/// no reading to go on, the control that must work is the one that stops
/// delivery.
///
/// Never gated and never hidden: a pod that is delivering has to stay stoppable
/// whatever any setting says, and it sits at the top of the page so that when it
/// is needed it does not require reading anything first.
class PodStopButton extends StatelessWidget {
  const PodStopButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    if (controller.isSuspended) {
      return const _ResumeButton();
    }
    return DangerActionButton(
      labelKey: 'pump.action.suspend',
      icon: PhosphorIconsFill.pause,
      onPressed: controller.isBusy ? null : () => _confirm(context, controller),
    );
  }

  void _confirm(BuildContext context, PodController controller) {
    PodDeliveryPrompt(
      titleKey: 'pump.stop._',
      bodyKey: 'pump.stop.body',
      confirmKey: 'pump.stop.confirm',
      destructive: true,
      onConfirm: controller.suspendDelivery,
    ).show(context);
  }
}

/// Puts a suspended pod back on the user's active basal profile.
///
/// The pod has no resume of its own: a suspend leaves it holding no schedule, so
/// coming back means programming one. That is why this reads the profile rather
/// than just sending a command.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final basal = PodBasalAdapter(context.watch<ProfileBasalState>().active);
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      onPressed: controller.isBusy || !basal.isProgrammable
          ? null
          : () => _confirm(context, controller, basal),
      icon: const Icon(PhosphorIconsBold.play, size: 20),
      label: LocaleText('pump.action.resume'),
    );
  }

  void _confirm(
    BuildContext context,
    PodController controller,
    PodBasalAdapter basal,
  ) {
    PodDeliveryPrompt(
      titleKey: 'pump.resume._',
      bodyKey: 'pump.resume.body',
      confirmKey: 'pump.resume.confirm',
      destructive: false,
      onConfirm: () => controller.resumeDelivery(basal.program),
    ).show(context);
  }
}

/// The confirmation in front of anything that changes whether insulin flows.
class PodDeliveryPrompt {
  const PodDeliveryPrompt({
    required this.titleKey,
    required this.bodyKey,
    required this.confirmKey,
    required this.destructive,
    required this.onConfirm,
  });

  final String titleKey;
  final String bodyKey;
  final String confirmKey;
  final bool destructive;
  final VoidCallback onConfirm;

  void show(BuildContext context) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: destructive ? context.danger : null,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              titleKey,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            LocaleText(
              bodyKey,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: confirmKey,
      confirmButtonColor: destructive
          ? Theme.of(context).colorScheme.error
          : null,
      callback: onConfirm,
    ).show(context);
  }
}
