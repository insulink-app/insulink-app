import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// ‹ date › to step through days or nights: two round buttons with the day
/// between them, "Heute" and "Gestern" by name. A button at the end is dimmed and inert.
class DayPager extends StatelessWidget {
  const DayPager({
    super.key,
    required this.date,
    required this.onPrevious,
    required this.onNext,
    this.previousLabelKey = 'date.previous_day',
    this.nextLabelKey = 'date.next_day',
  });

  final DateTime date;

  /// Null at the first and the last night.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Read out by screen readers for the two buttons.
  final String previousLabelKey;
  final String nextLabelKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _step(PhosphorIconsBold.caretLeft, previousLabelKey, onPrevious),
        Expanded(
          child: Text(
            RelativeDay(date).label(context),
            textAlign: TextAlign.center,
            style: InkText.row,
          ),
        ),
        _step(PhosphorIconsBold.caretRight, nextLabelKey, onNext),
      ],
    );
  }

  Widget _step(IconData icon, String labelKey, VoidCallback? onTap) {
    return HeaderIconButton(icon: icon, labelKey: labelKey, onTap: onTap);
  }
}
