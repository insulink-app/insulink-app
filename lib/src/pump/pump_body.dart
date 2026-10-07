import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/loop/loop_mode_card.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:insulink/src/pump/pod_status_attributes.dart';
import 'package:insulink/src/pump/pod_head_section.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/pump/pump_notice.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/key_value_row.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/pump/pump_delivery_controls.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: controller.hasPod && controller.store.isActivated
            ? _pod(context, controller)
            : _setup(),
      ),
    );
  }

  /// With a pod, in the redesign's order (`docs/redesign/screens/11-pumpe.png`):
  /// the device head with life and reservoir, delivery (automation, temporary
  /// rate, stop), the pod's data, and at the bottom the two actions that end
  /// the pod. One ordinary scroll, no pinned header: a control that fades while
  /// you scroll is distracting and, past half transparency, no longer tappable.
  ///
  /// Pulling it down re-reads the pod. Everything on the page is a cached status
  /// that ages on its own, and a pull is the gesture a phone user already makes
  /// at one.
  Widget _pod(BuildContext context, PodController controller) {
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          PodHeadSection(controller: controller),
          _header('pump.status.delivery', topGap: 32),
          ..._delivery(context, controller),
          _header('pump.info.title', actions: const [PodRefreshButton()]),
          _details(context, controller),
          _header('pump.manage'),
          const InkPanel.list(rows: [PodDeactivateButton(), PodForgetButton()]),
        ],
      ),
    );
  }

  /// The automation, a running temporary rate, and the stop, as separate
  /// elements 10 px apart. A failure stays here until the next action replaces
  /// it, never timed out, because it is not something to miss.
  ///
  /// A stale READING is not in here. It is the ordinary resting state of a pod
  /// nobody has just read; it is marked with a dot on the refresh button
  /// instead (see [PodRefreshButton]), which puts the notice on the control
  /// that fixes it.
  List<Widget> _delivery(BuildContext context, PodController controller) {
    return [
      const PodLoopModeCard(),
      const SizedBox(height: InkSpace.tileGap),
      const PodTempBasalButton(),
      const SizedBox(height: InkSpace.tileGap),
      const PodStopButton(),
      const PodSilenceAlertsButton(),
      if (controller.failure != null) ...[
        const SizedBox(height: InkSpace.tileGap),
        PumpNotice.failure(controller.failure!),
      ],
      const PodBasalOutOfDateNotice(),
    ];
  }

  /// Section titles line up with the page text, 8 px inside the panels' edge.
  Widget _header(
    String titleKey, {
    List<Widget> actions = const [],
    double topGap = InkSpace.sectionGap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SectionHeader(
        titleKey: titleKey,
        actions: actions,
        topGap: topGap,
      ),
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

  /// What the pod last reported, as key/value rows in one panel.
  Widget _details(BuildContext context, PodController controller) {
    final sections = PodStatusAttributes(
      status: controller.status,
      readAt: controller.statusReadAt,
      localize: (key) => Locales.string(context, key),
    ).build();
    return InkPanel.list(
      rows: [
        for (final section in sections)
          for (final item in section.items)
            KeyValueRow(label: item.key, value: item.value),
      ],
    );
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
    final controller = context.watch<PodController>();
    final paired = controller.hasPod;
    return InkPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PodRestoreCard(),
          // A failed read lands here too, and this page used to swallow it: a pod
          // adopted from the account that could not be reached left the user on
          // an unexplained offer to resume an activation. The notice belongs
          // wherever the failure can happen, not only on the page for a pod that
          // is already known to be running.
          if (controller.failure != null) ...[
            PumpNotice.failure(controller.failure!),
            const SizedBox(height: 14),
          ],
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
