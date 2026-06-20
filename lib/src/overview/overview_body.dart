import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/overview_chart.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/overview/overview_next_update.dart';
import 'package:insulink/src/profile/profile_silent_state.dart';
import 'package:provider/provider.dart';

class OverviewBody extends ProductPageBody {
  OverviewBody({super.key})
    : super(
        name: "overview.label",
        unselectedIcon: CupertinoIcons.chart_bar,
        selectedIcon: CupertinoIcons.chart_bar_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const OverviewBodyContent();
  }
}

class OverviewBodyContent extends StatelessWidget {
  const OverviewBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final silent = context.watch<ProfileSilentState>().silent;
    final hasData = g7.currentMgdl != null;
    // Show the loader while we don't yet know there's NO sensor: during initial
    // store load, or when a sensor is paired / connecting but no reading has
    // arrived yet. Only fall through to the "no sensor" view once we're sure.
    final loading =
        !hasData &&
        (!g7.initialized || g7.hasSensor || g7.connected || g7.busy);

    final Widget view = hasData
        ? _DataView(g7: g7)
        : loading
        ? const _SearchingView()
        : const _EmptyView();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (silent) ...[
            const _SilentBanner(),
            const SizedBox(height: 12),
          ],
          Expanded(child: view),
        ],
      ),
    );
  }
}

/// Prominent, tappable indicator shown on the overview while silent mode mutes
/// all alarms. Tapping it turns silent mode back off — alarms are safety
/// relevant, so it's deliberately easy to clear from the main screen.
class _SilentBanner extends StatelessWidget {
  const _SilentBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFFE8A13A);
    return Material(
      color: accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<ProfileSilentState>().setSilent(false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_off_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocaleText(
                      'overview.silent.title',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LocaleText(
                      'overview.silent.hint',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Normal view once a (live or cached) reading exists: headline value + chart.
class _DataView extends StatelessWidget {
  const _DataView({required this.g7});

  final G7Controller g7;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0.0,
          right: 0.0,
          child: Padding(
            padding: const EdgeInsets.all(5.0),
            child: OverviewNextUpdate(lastUpdate: g7.lastUpdate),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 56),
            OverviewCurrentValue(
              mgdl: g7.currentMgdl,
              trendPerMin: g7.latest?.trendMgDlPerMin,
              busy: g7.busy,
            ),
            const SizedBox(height: 56),
            Expanded(
              child: OverviewChart(
                byTime: g7.byTime,
                sensorStart: g7.sensorStart,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ],
    );
  }
}

/// Shown while the service is scanning/connecting but no reading has arrived.
class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          LocaleText(
            'overview.searching',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LocaleText(
            'overview.searching.hint',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Shown when no sensor is set up yet — points the user to the sensor page,
/// where pairing now happens.
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(CupertinoIcons.drop, size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 24),
            LocaleText(
              'overview.empty.title',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            LocaleText(
              'overview.empty.body',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => appTab.value = kSensorTabIndex,
              icon: const Icon(CupertinoIcons.drop_fill, size: 18),
              label: LocaleText('overview.empty.action'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
