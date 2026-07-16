import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Card that opens the box-layout editor (show/hide + reorder the summary
/// boxes). Shared by the Sport and nutrition settings sheets.
///
/// The whole card is the control, so it carries the accent on a neutral surface
/// — same visual language as the Health import box it sits next to. A tinted
/// card with a neutral badge was tried and read as two unrelated things.
class TileLayoutButton<T extends Enum> extends StatelessWidget {
  const TileLayoutButton({
    super.key,
    required this.state,
    required this.icon,
    required this.labelKey,
  });

  final TileLayoutState<T> state;
  final IconData Function(T) icon;
  final String Function(T) labelKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                PhosphorIconsBold.squaresFour,
                color: context.accent,
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(child: _text(scheme)),
              const SizedBox(width: 10),
              Icon(PhosphorIconsBold.caretRight, color: context.accent),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor<T>(
          state: state,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
          icon: icon,
          labelKey: labelKey,
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
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
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
