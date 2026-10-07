import 'package:flutter/material.dart';

import '../localization/locale_text.dart';
import '../theme/insulink_theme.dart';
import 'ink_sheet.dart';

/// Shared body of the focused settings sheet editors (glucose ranges, bolus
/// factors) as an [InkSheet]: title with the current value beside it, the
/// editor [children], and a "Done" button. Keeps dragging away from
/// the scrolling settings list behind it.
class EditorSheet extends StatelessWidget {
  const EditorSheet({
    super.key,
    required this.titleKey,
    required this.valueText,
    required this.accent,
    required this.children,
  });

  final String titleKey;
  final String valueText;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return InkSheet(
      title: _header(),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: LocaleText('alert.done'),
            ),
          ],
        ),
      ),
    );
  }

  /// The title with the current value beside it, in [accent].
  Widget _header() {
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: LocaleText(
            titleKey,
            style: InkText.bigValue.copyWith(fontSize: 20),
          ),
        ),
        Text(valueText, style: InkText.rowTitle.copyWith(color: accent)),
      ],
    );
  }
}
