import 'package:flutter/material.dart';

import '../localization/locale_text.dart';

/// Shared chrome for the focused settings bottom-sheet editors (glucose ranges,
/// bolus factors): the rounded container, grab handle, title + current-value
/// header, the editor [children], and a "Done" button. Keeps dragging away from
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grabHandle(theme),
            const SizedBox(height: 18),
            _header(),
            const SizedBox(height: 22),
            ...children,
            const SizedBox(height: 24),
            _doneButton(context),
          ],
        ),
      ),
    );
  }

  Widget _grabHandle(ThemeData theme) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          titleKey,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        Text(
          valueText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    );
  }

  Widget _doneButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: LocaleText(
          'alert.done',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
