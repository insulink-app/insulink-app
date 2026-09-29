import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_notice.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The alerts the pod itself is beeping about, with the button that silences
/// them, so a beeping pod can be answered from the screen the user opens.
///
/// Unlike [OverviewPodWarnings] this is not the notification shade: it is the
/// pod's own alert bits from the last status anyone read, the background poll's
/// included ([PodController.adoptBackgroundStatus]).
///
/// A tap opens the pump page, like the warnings above it. A swipe acknowledges. The card then stays hidden until a newer status
/// arrives, so one the pod still reports after the acknowledgement comes back.
class OverviewPodAlerts extends StatefulWidget {
  const OverviewPodAlerts({super.key});

  @override
  State<OverviewPodAlerts> createState() => _OverviewPodAlertsState();
}

class _OverviewPodAlertsState extends State<OverviewPodAlerts> {
  /// The status time the card was swiped away at.
  DateTime? _dismissedAt;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final alerts = controller.status?.activeAlerts ?? const {};
    final hidden =
        _dismissedAt != null && _dismissedAt == controller.statusReadAt;
    if (!controller.hasPod || alerts.isEmpty || hidden) {
      return const SizedBox.shrink();
    }
    return OverviewNotice(
      dismissKey: 'pod-alerts-${controller.statusReadAt}',
      icon: PhosphorIconsBold.bellRinging,
      title: Locales.string(context, 'overview.pod_alerts'),
      message: alerts
          .map(
            (alert) => Locales.string(context, 'pump.alert.${alert.localeKey}'),
          )
          .join(', '),
      onDismiss: () => _acknowledge(controller),
      onTap: () => openPumpPage(context),
      action: const PodSilenceAlertsButton(),
    );
  }

  void _acknowledge(PodController controller) {
    setState(() => _dismissedAt = controller.statusReadAt);
    controller.silenceAlerts();
  }
}
