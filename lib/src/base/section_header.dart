import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The title above a section: 18/700 in sentence case on the left, optional
/// controls on the right (plain [HeaderIconButton]s), 28 px of air above it.
///
/// The controls are pulled 10 px into the margin, so the glyph rather than its
/// 44 px touch area lines up with the panel edge below.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.titleKey,
    this.actions = const [],
    this.topGap = InkSpace.sectionGap,
  });

  final String titleKey;
  final List<Widget> actions;

  /// Space above the header; the first section of a page sets less.
  final double topGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: InkSpace.minTouch),
        child: Row(
          children: [
            Expanded(child: LocaleText(titleKey, style: InkText.section)),
            if (actions.isNotEmpty)
              Transform.translate(
                offset: const Offset(10, 0),
                child: Row(spacing: 2, children: actions),
              ),
          ],
        ),
      ),
    );
  }
}
