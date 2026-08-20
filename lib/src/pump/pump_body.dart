import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/base/pinned_header_scroll.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:insulink/src/pump/pod_status_attributes.dart';
import 'package:insulink/src/pump/pod_status_box.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/pump/pump_notice.dart';
import 'package:insulink/src/sensor/info/sensor_info_section.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The pump device page, shown inside the Devices tab (see [DevicesBody]).
///
/// Laid out like the sensor page: a pinned box at the top that fades as the
/// detail list scrolls up into its place. The box holds the state and the control
/// that stops the pod — when that is needed, it should not require reading
/// anything first.
///
/// Before a pod is paired the page is only the setup box: there is no pod to
/// detail, and a heading over an empty page reads as something failing to load.
class PumpBodyContent extends StatefulWidget {
  const PumpBodyContent({super.key});

  @override
  State<PumpBodyContent> createState() => _PumpBodyContentState();
}

class _PumpBodyContentState extends State<PumpBodyContent> {
  /// Reads the pod once when the page opens, unless the last read is still fresh.
  ///
  /// A device page that cannot say whether the device is running is not much of a
  /// device page — and the control it offers depends on the answer.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PodController>().refreshIfStale();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        child: controller.hasPod && controller.store.isActivated
            ? _pod(context, controller)
            : _setup(),
      ),
    );
  }

  /// With a pod: the status box pins to the top and the detail list scrolls up
  /// into its place, exactly as the sensor page behaves.
  Widget _pod(BuildContext context, PodController controller) {
    return PinnedHeaderScroll(
      header: PodStatusBox(controller: controller),
      child: _details(context, controller),
    );
  }

  /// Without a RUNNING pod there is nothing to detail, so the setup box stands on
  /// its own: no heading over an empty page, and nothing to scroll it away with.
  ///
  /// A pod that is paired but not yet activated lands here too. It refuses
  /// everything but the activation sequence, so a status page for it would be a
  /// page of failures; what it needs is the wizard finished.
  Widget _setup() {
    return const SingleChildScrollView(child: PodSetupBox());
  }

  Widget _details(BuildContext context, PodController controller) {
    final sections = PodStatusAttributes(
      status: controller.status,
      readAt: controller.statusReadAt,
      localize: (key) => Locales.string(context, key),
    ).build();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(),
        const SizedBox(height: 4),
        ..._notices(context, controller),
        const PodBasalOutOfDateNotice(),
        SensorSectionList(sections: sections),
      ],
    );
  }

  /// The detail heading with the re-read beside it: the control belongs to what
  /// it refreshes, rather than sitting at the far end of the page.
  Widget _heading() {
    return Row(
      children: [
        Expanded(
          child: LocaleText(
            'pump.info.title',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const PodRefreshButton(),
      ],
    );
  }

  /// A pump failure and a stale reading both stay on screen until the next
  /// action replaces them — never timed out, because neither is something to
  /// miss.
  List<Widget> _notices(BuildContext context, PodController controller) {
    return [
      if (controller.failure != null) ...[
        PumpNotice.failure(controller.failure!),
        const SizedBox(height: 14),
      ],
      if (_isStale(controller)) ...[
        const PumpNotice.stale(),
        const SizedBox(height: 14),
      ],
    ];
  }

  /// Whether the shown status is too old to base anything on. Matches the window
  /// the delivery guard enforces, so the UI and the guard agree.
  bool _isStale(PodController controller) {
    final age = controller.statusAge;
    return age != null && age > const Duration(minutes: 2);
  }
}

/// The pinned box before a pod is paired: adopt the account's pod, or activate a
/// new one. Sits in the same panel the status box uses, so the page does not
/// change shape when a pod appears.
class PodSetupBox extends StatelessWidget {
  const PodSetupBox({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A pod can be PAIRED without running: the key is stored several commands
    // before delivery starts. That pod needs the wizard finished, not a new one.
    final paired = context.watch<PodController>().hasPod;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PodRestoreCard(),
          EmptyState(
            icon: PhosphorIconsBold.syringe,
            titleKey: paired ? 'pump.activate.title' : 'pump.status.no_pod',
          ),
          const SizedBox(height: 8),
          LocaleText(
            paired ? 'pump.status.unfinished' : 'pump.status.no_pod_hint',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const PodActivateButton(),
        ],
      ),
    );
  }
}
