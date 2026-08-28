import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The ways out of the activation wizard, and the warning in front of them.
///
/// A search that cannot be left is a trap: it runs for up to a minute, and the
/// priming wait for another. So the back arrow, the system back gesture and the
/// stop button all work while something is in flight, and all three come through
/// here.
///
/// Stopping never discards what was recorded. Every protocol step is written
/// before the next one runs, so the wizard picks the attempt up exactly where it
/// left off. What already happened to the pod cannot be undone, and the warning
/// says that rather than pretending otherwise.
class PodActivationExit {
  const PodActivationExit(this.controller);

  final PodActivationController controller;

  /// Leaves the wizard, asking first when something is in flight.
  void leave(BuildContext context) {
    if (!controller.isBusy) {
      Navigator.of(context).pop();
      return;
    }
    final navigator = Navigator.of(context);
    confirmStopping(context, then: navigator.pop);
  }

  /// Asks before stopping, then stops and runs [then].
  void confirmStopping(BuildContext context, {VoidCallback? then}) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.warning,
      content: _content(),
      cancelButton: true,
      cancelButtonText: 'pump.activate.stop_keep',
      confirmButtonText: 'pump.activate.stop_confirm',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () async {
        await controller.stopAttempt();
        then?.call();
      },
    ).show(context);
  }

  /// Two versions, because the honest answer differs: a search that has not found
  /// anything yet has touched no pod, while a pod already paired or primed is
  /// committed and can only be picked up again later.
  String get _bodyKey => controller.canResume || controller.store.hasPod
      ? 'pump.activate.stop_started'
      : 'pump.activate.stop_clean';

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocaleText(
            'pump.activate.stop_title',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          LocaleText(
            _bodyKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ],
      ),
    );
  }
}
