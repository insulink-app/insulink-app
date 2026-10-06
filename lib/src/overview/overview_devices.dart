import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_pod_life.dart';
import 'package:insulink/src/overview/overview_section.dart';
import 'package:insulink/src/overview/overview_sensor_life.dart';
import 'package:insulink/src/pump/loop/loop_overview_line.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:provider/provider.dart';

/// The devices panel: the sensor's remaining days, the pod's days beside its
/// reservoir, and below a divider whether the automation is running. Each part
/// opens its own page. Renders nothing while neither device is known.
class OverviewDevices extends StatelessWidget {
  const OverviewDevices({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSensor = context.watch<CgmController>().sensorStart != null;
    final hasPod = context.watch<PodController>().hasPod;
    if (!hasSensor && !hasPod) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(
            Locales.string(context, 'overview.devices'),
            style: InsulinkTextStyles.sectionTitle,
          ),
        ),
        OverviewSection(child: _content(context, hasSensor, hasPod)),
      ],
    );
  }

  Widget _content(BuildContext context, bool hasSensor, bool hasPod) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (hasSensor)
          _tappable(() => openSensorPage(context), const OverviewSensorLife()),
        if (hasPod)
          _tappable(() => openPumpPage(context), const OverviewPodLife()),
        if (hasPod) _loop(context),
      ],
    );
  }

  Widget _tappable(VoidCallback onTap, Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  Widget _loop(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: context.insulinkColors.line),
        const PodLoopOverviewLine(),
      ],
    );
  }
}
