import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// The numbered things the user has to do at one stage of the activation.
///
/// Read from locale keys `<prefix>_step_1`, `_step_2` and so on, stopping at the
/// first one that is missing. Keys rather than a list because the locale loader
/// flattens to dotted paths of strings, and a numbered tail is the cheapest way
/// to keep a list in that shape.
///
/// Renders nothing when a stage has no steps, so a stage can be left without.
class PodActivationSteps extends StatelessWidget {
  const PodActivationSteps({super.key, required this.prefix});

  /// The locale prefix for this stage, e.g. `pump.activate.attach`.
  final String prefix;

  /// Nobody writes a wizard step longer than this; the cap only stops a missing
  /// key turning into an endless loop.
  static const int _maxSteps = 8;

  @override
  Widget build(BuildContext context) {
    final steps = _read(context);
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _step(context, number: index + 1, text: steps[index]),
        ],
      ],
    );
  }

  /// The steps this stage has, stopping at the first number the locale has no
  /// key for.
  ///
  /// Asked with [Locales.contains] rather than compared against the returned
  /// text: a missing key resolves to `\$key`, not to the key, so comparing would
  /// never find the end and the list would run to [_maxSteps] of placeholders.
  List<String> _read(BuildContext context) {
    final steps = <String>[];
    for (var number = 1; number <= _maxSteps; number++) {
      final key = '${prefix}_step_$number';
      if (!Locales.contains(context, key)) {
        return steps;
      }
      steps.add(Locales.string(context, key));
    }
    return steps;
  }

  Widget _step(
    BuildContext context, {
    required int number,
    required String text,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _number(context, scheme, number),
        const SizedBox(width: 12),
        Expanded(child: _text(text, scheme)),
      ],
    );
  }

  /// The step, with the parts between asterisks in bold.
  ///
  /// A step is one instruction and one thing that matters in it — the site being
  /// dry, the film coming off, the needle going in. Marking that inline keeps the
  /// sentence short instead of spelling the emphasis out in words.
  Widget _text(String text, ColorScheme scheme) {
    final base = TextStyle(fontSize: 14, height: 1.35, color: scheme.onSurface);
    final parts = text.split('*');
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < parts.length; index++)
            TextSpan(
              text: parts[index],
              style: index.isOdd
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
        ],
      ),
      style: base,
    );
  }

  /// A filled disc carrying the step number. Neutral and unpressable by design:
  /// the shape says "this is an identity", not "this is a button".
  Widget _number(BuildContext context, ColorScheme scheme, int number) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.accent,
        ),
      ),
    );
  }
}
