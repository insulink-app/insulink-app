import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_gate_card.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:insulink/src/pump/pod_status_attributes.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/sensor/info/sensor_info_section.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The pump device page, shown inside the Devices tab (see [DevicesBody]).
///
/// Shows what the pod reports and the few things the user can start from here.
/// The stop control sits above the status rather than below it: when it is
/// needed, it should not require reading anything first.
class PumpBodyContent extends StatelessWidget {
  const PumpBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const PodGateCard(),
        const SizedBox(height: 14),
        if (!controller.hasPod) _noPod(context) else ..._pod(context, controller),
      ],
    );
  }

  Widget _noPod(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PodRestoreCard(),
        const SizedBox(height: 14),
        const EmptyState(
          icon: PhosphorIconsBold.syringe,
          titleKey: 'pump.status.no_pod',
        ),
        const SizedBox(height: 8),
        LocaleText(
          'pump.status.no_pod_hint',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        const PodActivateButton(),
      ],
    );
  }

  List<Widget> _pod(BuildContext context, PodController controller) {
    final sections = PodStatusAttributes(
      status: controller.status,
      readAt: controller.statusReadAt,
      localize: (key) => Locales.string(context, key),
    ).build();
    return [
      const PodStopButton(),
      const SizedBox(height: 14),
      if (controller.failure != null) ...[
        _failure(context, controller.failure!),
        const SizedBox(height: 14),
      ],
      if (_isStale(controller)) ...[
        _stale(context),
        const SizedBox(height: 14),
      ],
      SensorSectionList(sections: sections),
      const SizedBox(height: 14),
      const PodMaintenanceActions(),
    ];
  }

  /// Whether the shown status is too old to base anything on. Matches the
  /// window the delivery guard enforces, so the UI and the guard agree.
  bool _isStale(PodController controller) {
    final age = controller.statusAge;
    return age != null && age > const Duration(minutes: 2);
  }

  /// A failure stays on screen until the next action replaces it — never timed
  /// out, because a pump failure is not something to miss.
  Widget _failure(BuildContext context, String message) {
    return _notice(context, context.danger, PhosphorIconsFill.warningCircle,
        Text(message, style: TextStyle(fontSize: 13, color: context.danger)));
  }

  Widget _stale(BuildContext context) {
    return _notice(
      context,
      context.warning,
      PhosphorIconsBold.clockCountdown,
      LocaleText('pump.status.stale',
          style: TextStyle(fontSize: 13, color: context.warning)),
    );
  }

  Widget _notice(
    BuildContext context,
    Color accent,
    IconData icon,
    Widget body,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Confirms and then stops every kind of delivery.
class PodStopButton extends StatelessWidget {
  const PodStopButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        minimumSize: const Size.fromHeight(52),
      ),
      onPressed: controller.isBusy ? null : () => _confirm(context, controller),
      icon: const Icon(PhosphorIconsBold.pause, size: 20),
      label: LocaleText('pump.action.suspend'),
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
            LocaleText('pump.stop._',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LocaleText('pump.stop.body',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.stop.confirm',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: controller.suspendDelivery,
    ).show(context);
  }
}
