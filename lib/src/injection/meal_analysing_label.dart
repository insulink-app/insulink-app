import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/photo_estimate_step.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// "Analysing" with a small spinner at the foot of the photo, and under it the
/// step the server's estimate is at ([PhotoEstimateStep]), asked for every
/// [_interval] while the label is up. A new step fades in over the old one.
/// Below it, "New photo" ([onRetake]) calls the estimate off for another shot.
class MealAnalysingLabel extends StatefulWidget {
  const MealAnalysingLabel({super.key, required this.onRetake});

  final VoidCallback onRetake;

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
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  LocaleText(
                    'injection.photo.analysing',
                    style: InkText.rowTitle.copyWith(color: Colors.white),
                  ),
                ],
              ),
              SizedBox(height: 40, child: _stepText()),
              _retakeButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// White on the darkened photo like the rest of the label, at least 44 px.
  Widget _retakeButton() {
    return OutlinedButton.icon(
      onPressed: widget.onRetake,
      icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 18),
      label: const LocaleText('injection.photo.retake'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size(0, 44),
      ),
    );
  }

  /// Two lines at most: a search query can run long.
  Widget _stepText() {
    final step = _step;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: step == null
          ? const SizedBox.shrink()
          : LocaleText(
              step.localeKey,
              key: ValueKey('${step.step}${step.detail}'),
              params: [step.detail],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: InkText.body.copyWith(color: Colors.white70),
            ),
    );
  }
}
