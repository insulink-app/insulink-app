import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Card that opens the "Today" box editor — same visual language as the Health
/// import card it sits next to (tinted badge, title + subtitle, trailing icon).
class TodayLayoutButton extends StatelessWidget {
  const TodayLayoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _badge(scheme),
              const SizedBox(width: 14),
              Expanded(child: _text(scheme)),
              const SizedBox(width: 10),
              Icon(PhosphorIconsRegular.caretRight, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final state = context.read<TodayLayoutState>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor<TodayTile>(
          state: state,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
          icon: todayTileIcon,
          labelKey: todayTileLabelKey,
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }

  Widget _badge(ColorScheme scheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(
        PhosphorIconsRegular.squaresFour,
        color: scheme.onPrimary,
        size: 22,
      ),
    );
  }

  Widget _text(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LocaleText(
          'sport.layout.title',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        LocaleText(
          'sport.layout.subtitle',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
