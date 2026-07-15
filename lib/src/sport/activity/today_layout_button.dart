import 'package:flutter/material.dart';
import 'package:insulink/src/sport/activity/tile_layout_button.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:provider/provider.dart';

/// Opens the "Today" box editor from the Sport settings sheet.
class TodayLayoutButton extends StatelessWidget {
  const TodayLayoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayoutButton<TodayTile>(
      state: context.read<TodayLayoutState>(),
      icon: todayTileIcon,
      labelKey: todayTileLabelKey,
    );
  }
}
