import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// ‹ date › to step through the nights: two round buttons with the night's
/// date between them. A button at the end of the list is dimmed and inert.
class SleepNightPager extends StatelessWidget {
  const SleepNightPager({
    super.key,
    required this.date,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime date;

  /// Null at the first and the last night.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Row(
      children: [
        _step(
          PhosphorIconsBold.caretLeft,
          'google_health.sleep_page.previous_night',
          onPrevious,
        ),
        Expanded(
          child: Text(
            DateFormat.MMMEd(locale).format(date),
            textAlign: TextAlign.center,
            style: InkText.row,
          ),
        ),
        _step(
          PhosphorIconsBold.caretRight,
          'google_health.sleep_page.next_night',
          onNext,
        ),
      ],
    );
  }

  Widget _step(IconData icon, String labelKey, VoidCallback? onTap) {
    return HeaderIconButton(icon: icon, labelKey: labelKey, onTap: onTap);
  }
}
