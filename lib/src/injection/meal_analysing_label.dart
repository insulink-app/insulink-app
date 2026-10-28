import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/photo_estimate_step.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One quiet line above the deck while a photo is analysed, in the slot the
/// zoom takes in the live picture: a small spinner and the step the server's
/// estimate is at ([PhotoEstimateStep]), asked for every [_interval]. Until the
/// first step arrives it says "Analysing"; after that the step says it better,
/// so the two never stack. A new step fades in over the old one.
class MealAnalysingLabel extends StatefulWidget {
  const MealAnalysingLabel({super.key});

  @override
  State<MealAnalysingLabel> createState() => _MealAnalysingLabelState();
}

class _MealAnalysingLabelState extends State<MealAnalysingLabel> {
  static const _interval = Duration(milliseconds: 1500);

  late final Timer _poll;
  PhotoEstimateStep? _step;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_interval, (_) => _askStep());
  }

  /// Skips a tick while the previous answer is still on its way, so a slow
  /// network never stacks requests.
  Future<void> _askStep() async {
    if (_asking) {
      return;
    }
    _asking = true;
    final step = await PhotoEstimateStep.request(context);
    _asking = false;
    if (mounted && step != null) {
      setState(() => _step = step);
    }
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _line(),
          ),
        ),
      ],
    );
  }

  /// The step, or "Analysing" before there is one. One line: a long search
  /// query is cut, the foot must not grow while the user decides.
  Widget _line() {
    final step = _step;
    return LocaleText(
      step?.localeKey ?? 'injection.photo.analysing',
      key: ValueKey('${step?.step}${step?.detail}'),
      params: [step?.detail ?? ''],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: InkText.label.copyWith(color: Colors.white70),
    );
  }
}
