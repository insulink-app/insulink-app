import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/status/connection_status_page.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/overview/battery_saver_banner.dart';
import 'package:insulink/src/overview/advisory_bolus_notice.dart';
import 'package:insulink/src/overview/overview_pod_warnings.dart';
import 'package:insulink/src/overview/overview_running_bolus.dart';
import 'package:insulink/src/overview/update/overview_update.dart';
import 'package:insulink/src/overview/overview_data_view.dart';
import 'package:insulink/src/overview/overview_header_glucose.dart';
import 'package:insulink/src/overview/overview_states.dart';
import 'package:insulink/src/overview/sensor_restore_offer.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

class OverviewBody extends AppPageBody {
  OverviewBody({super.key})
    : super(
        name: "overview.label",
        unselectedIcon: PhosphorIconsRegular.squaresFour,
        selectedIcon: PhosphorIconsFill.squaresFour,
      );

  @override
  Widget content(BuildContext context) {
    return const OverviewBodyContent();
  }

  @override
  Widget? title(BuildContext context) => const _OverviewTitle();
}

/// Header title for the overview: the "next reading" clock, which used to sit
/// in the top-right corner of the chart view. Watches the controller itself so
/// only this widget rebuilds when a new reading arrives.
///
/// Tapping it opens the connection page. The clock is already the thing the user
/// looks at when they wonder whether anything is still arriving, so "is it still
/// connected, and when did it last say anything" belongs behind it.
class _OverviewTitle extends StatelessWidget {
  const _OverviewTitle();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final colors = context.insulinkColors;
    return Row(
      children: [
        _pill(context, controller, colors),
        const Expanded(child: Center(child: OverviewHeaderGlucose())),
      ],
    );
  }

  Widget _pill(
    BuildContext context,
    CgmController controller,
    InsulinkColors colors,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: Locales.string(context, 'connections.label'),
        child: Material(
          color: colors.panel,
          shape: StadiumBorder(side: BorderSide(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openConnectionStatus(context),
            child: Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(9, 0, 14, 0),
              child: OverviewUpdate(
                lastUpdate: controller.lastUpdate,
                intervalSec: controller.sensorType.readingIntervalSec,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OverviewBodyContent extends StatelessWidget {
  const OverviewBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final silent = context.watch<ProfileSilentState>().activeMode;
    final battery = context.watch<ProfileBatteryState>().activeMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          const OverviewRunningBolus(),
          const AdvisoryBolusNotice(),
          const OverviewPodWarnings(),
          if (silent != SilentMode.off) ...[
            SilentBanner(silent),
            const SizedBox(height: 12),
          ],
          if (battery != BatteryMode.off) ...[
            BatterySaverBanner(battery),
            const SizedBox(height: 12),
          ],
          Expanded(child: _view(controller)),
        ],
      ),
    );
  }

  /// Picks the body for the current state. Show the loader while we don't yet
  /// know there's NO sensor: during initial store load, or when a sensor is
  /// paired / connecting but no reading has arrived yet. Only fall through to
  /// the "no sensor" view once we're sure.
  Widget _view(CgmController controller) {
    // Known data (a live/cached value OR archived history) → show the chart
    // straight away, even before a fresh reading lands after a re-login/restore;
    // the headline shows a loader until the current value arrives.
    //
    // Read ONCE per build and handed down: every `byTime` read rebuilds the
    // series out of the archive, and the view used to ask for it four times
    // (here, the chart, and each Y-axis bound).
    final byTime = controller.byTime;
    if (controller.currentMgdl != null || byTime.isNotEmpty) {
      return OverviewDataView(controller: controller, byTime: byTime);
    }
    final loading =
        !controller.initialized ||
        controller.hasSensor ||
        controller.connected ||
        controller.busy;
    if (loading) {
      return const SearchingView();
    }
    // No sensor set up: above the empty prompt, offer whatever the account is
    // holding. Each renders nothing unless the backend has one, and a reinstall
    // typically has BOTH to pick up: the sensor and the pod on the body.
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SensorRestoreOffer(),
        PodRestoreCard(),
        Expanded(child: EmptyView()),
      ],
    );
  }
}
