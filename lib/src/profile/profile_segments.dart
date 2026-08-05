import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// One labelled option of a [ProfileSegments] row.
///
/// [fill] is the colour the segment takes while picked — silent mode paints its
/// muting choices in the error colour so the picked state reads as "alarms are
/// held back" rather than as a neutral choice. Defaults to `onSurface`.
/// A null [onTap] renders the segment dimmed and inert.
typedef ProfileSegment = ({
  String labelKey,
  bool selected,
  Color? fill,
  VoidCallback? onTap,
});

/// A segmented row of mutually exclusive settings options: bordered track, an
/// animated pill on the picked one.
///
/// Shared by every setting built this way (silent mode's reach and the battery
/// saver's level, plus the duration row both of them carry), so the track is
/// written once instead of per setting.
class ProfileSegments extends StatelessWidget {
  const ProfileSegments(this.segments, {super.key});

  final List<ProfileSegment> segments;

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

  Widget _segment(ThemeData theme, ProfileSegment segment) {
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
              ? (segment.fill ?? theme.colorScheme.onSurface)
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
