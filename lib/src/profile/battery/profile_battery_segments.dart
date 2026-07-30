import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// One labelled option of a [ProfileBatterySegments] row.
typedef BatterySegment = ({String labelKey, bool selected, VoidCallback? onTap});

/// A segmented row of mutually exclusive options, styled like the silent-mode
/// picker (bordered track, animated pill on the picked segment).
///
/// The battery saver needs two of these — mode and duration — so the track lives
/// here instead of being written twice. A null [BatterySegment.onTap] renders the
/// segment dimmed and inert, which is how the duration row reads while the saver
/// is off.
class ProfileBatterySegments extends StatelessWidget {
  const ProfileBatterySegments(this.segments, {super.key});

  final List<BatterySegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(child: _segment(theme, segment)),
        ],
      ),
    );
  }

  Widget _segment(ThemeData theme, BatterySegment segment) {
    final enabled = segment.onTap != null;
    final label = segment.selected
        ? theme.colorScheme.surface
        : theme.colorScheme.onSurface.withValues(alpha: enabled ? 1 : 0.35);
    return GestureDetector(
      onTap: segment.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: segment.selected
              ? theme.colorScheme.onSurface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: LocaleText(
          segment.labelKey,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, color: label),
        ),
      ),
    );
  }
}
