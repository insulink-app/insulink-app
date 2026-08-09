import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/overview/overview_box_builder.dart';
import 'package:insulink/src/sport/activity/tile_grid.dart';

/// Every tracked value in one place — shown, hidden, imported and hand-entered
/// alike — as the same boxes the overview draws.
///
/// A box IS the door to its metric: it already carries the value and opens that
/// metric's detail page, where the value is charted and (for the hand-entered
/// ones, weight and HbA1c) added with the page's own "+". The overview only shows
/// the boxes the user picked, so hiding one used to take its detail page with it
/// — there was no other way in. This page renders [OverviewBox.values] through
/// the SAME [OverviewBoxBuilder], so nothing here is per-metric code and any box
/// added later shows up on its own.
class AllValuesPage extends StatelessWidget {
  const AllValuesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final builder = OverviewBoxBuilder.of(context);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('overview.boxes.all'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: LocaleText(
                'overview.boxes.all_hint',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TileGrid<OverviewBox>(
              tiles: OverviewBox.values,
              tileBuilder: (context, box, _) => builder.build(context, box),
            ),
          ],
        ),
      ),
    );
  }
}
