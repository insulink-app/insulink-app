import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_chart.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/overview/overview_next_update.dart';
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
    String t(String key) => Locales.string(context, key);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OverviewCurrentValue(
            mgdl: g7.currentMgdl,
            trendPerMin: g7.latest?.trendMgDlPerMin,
            // Dimmed "cached" until a live reading arrives from the service.
            stale: !g7.latestIsLive,
            busy: g7.busy,
          ),
          const SizedBox(height: 12),
          OverviewNextUpdate(lastUpdate: g7.lastUpdate),
          const SizedBox(height: 12),
          Expanded(child: OverviewChart(byTime: g7.byTime)),
          const SizedBox(height: 8),
          if (!g7.connected) ...[
            TextField(
              controller: g7.code,
              decoration: InputDecoration(
                labelText: t('overview.pairing_code'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: g7.busy ? null : g7.start,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(
                g7.busy ? t('overview.connecting') : t('overview.connect'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
