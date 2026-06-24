import 'package:flutter/cupertino.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/overview/overview_chart.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/overview/overview_next_update.dart';
import 'package:insulink/src/overview/overview_states.dart';
import 'package:insulink/src/profile/profile_silent_state.dart';
import 'package:provider/provider.dart';

class OverviewBody extends AppPageBody {
  OverviewBody({super.key})
    : super(
        name: "overview.label",
        unselectedIcon: CupertinoIcons.square_grid_2x2,
        selectedIcon: CupertinoIcons.square_grid_2x2_fill,
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
class _OverviewTitle extends StatelessWidget {
  const _OverviewTitle();

  @override
  Widget build(BuildContext context) {
    final lastUpdate = context.watch<G7Controller>().lastUpdate;
    return OverviewNextUpdate(lastUpdate: lastUpdate);
  }
}

class OverviewBodyContent extends StatelessWidget {
  const OverviewBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<G7Controller>();
    final silent = context.watch<ProfileSilentState>().silent;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (silent) ...[const SilentBanner(), const SizedBox(height: 12)],
          Expanded(child: _view(controller)),
        ],
      ),
    );
  }

  /// Picks the body for the current state. Show the loader while we don't yet
  /// know there's NO sensor: during initial store load, or when a sensor is
  /// paired / connecting but no reading has arrived yet. Only fall through to
  /// the "no sensor" view once we're sure.
  Widget _view(G7Controller controller) {
    if (controller.currentMgdl != null) {
      return _DataView(controller: controller);
    }
    final loading =
        !controller.initialized ||
        controller.hasSensor ||
        controller.connected ||
        controller.busy;
    return loading ? const SearchingView() : const EmptyView();
  }
}

/// Normal view once a (live or cached) reading exists: headline value + chart.
class _DataView extends StatelessWidget {
  const _DataView({required this.controller});

  final G7Controller controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        OverviewCurrentValue(
          mgdl: controller.currentMgdl,
          trendPerMin: controller.latest?.trendMgDlPerMin,
          busy: controller.busy,
        ),
        const SizedBox(height: 56),
        Expanded(
          child: OverviewChart(
            byTime: controller.byTime,
            sensorStart: controller.sensorStart,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
