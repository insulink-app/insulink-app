import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/pump/pod_activation_page.dart';
import 'package:insulink/src/pump/pod_activation_exit.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/base/button_loader.dart';

/// The buttons at the foot of the wizard, one set per stage.
///
/// Every stage offers a way onward AND a way out. The busy stages in particular:
/// they cover a scan and a priming wait, either of which can otherwise leave the
/// user watching a spinner that answers nothing.
class PodActivationActions extends StatelessWidget {
  const PodActivationActions({
    super.key,
    required this.controller,
    required this.basal,
  });

  final PodActivationController controller;
  final PodBasalAdapter basal;

  @override
  Widget build(BuildContext context) {
    if (controller.isBusy) {
      return _busy(context);
    }
    return switch (controller.stage) {
      PodActivationStage.explaining => _primary(
        labelKey: 'pump.activate.start',
        icon: PhosphorIconsBold.magnifyingGlass,
        onPressed: basal.isProgrammable ? controller.primePod : null,
      ),
      PodActivationStage.attachPod => _primary(
        labelKey: 'pump.activate.attached',
        icon: PhosphorIconsBold.fingerprint,
        onPressed: basal.isProgrammable
            ? () => _confirmThenStart(context)
            : null,
      ),
      PodActivationStage.running => _primary(
        labelKey: 'pump.activate.done',
        icon: PhosphorIconsBold.check,
        onPressed: () => Navigator.of(context).pop(),
      ),
      PodActivationStage.failed => _afterFailure(context),
      _ => _busy(context),
    };
  }

  /// The spinner paired with a way out, disabled once the stop is under way so it
  /// cannot be asked for twice.
  Widget _busy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BusyButton(),
        const SizedBox(height: 10),
        SecondaryActionButton(
          labelKey: controller.isStopping
              ? 'pump.activate.stopping'
              : 'pump.activate.stop',
          icon: PhosphorIconsBold.x,
          onPressed: controller.isStopping
              ? null
              : () => PodActivationExit(controller).confirmStopping(context),
        ),
      ],
    );
  }

  /// After a failure the user gets both ways forward: try the same pod again, or
  /// give up on it. A retry resumes rather than restarting, so it cannot
  /// re-deliver the priming insulin.
  Widget _afterFailure(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _primary(
          labelKey: 'pump.activate.retry',
          icon: PhosphorIconsBold.arrowsClockwise,
          onPressed: _retry,
        ),
        const SizedBox(height: 10),
        DangerActionButton(
          labelKey: 'pump.activate.discard',
          icon: PhosphorIconsBold.trash,
          onPressed: controller.discardAttempt,
        ),
      ],
    );
  }

  /// Asks for the fingerprint FIRST, then starts.
  ///
  /// The other way round is what the protocol wants — the confirmation belongs
  /// immediately before the command — but it left the user waiting through a
  /// scan, a handshake and two programming commands before the prompt appeared.
  /// [CannulaConfirmation] bridges the two: asked here, spent there, single use.
  Future<void> _confirmThenStart(BuildContext context) async {
    final confirmation = context.read<CannulaConfirmation>();
    final started = controller.startDelivery;
    if (await confirmation.ask()) {
      await started(basal.program);
      return;
    }
    controller.reportCannulaDeclined();
  }

  void _retry() {
    if (controller.storedStep.isBefore(PodActivationStep.primed)) {
      controller.primePod();
      return;
    }
    controller.startDelivery(basal.program);
  }

  Widget _primary({
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
      icon: const ButtonLoader(),
      label: LocaleText('pump.activate.working'),
    );
  }
}
