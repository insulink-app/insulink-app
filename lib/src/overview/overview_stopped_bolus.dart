import 'package:flutter/material.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// What became of a bolus that did not simply run its course: one the user
/// stopped, one the pod refused, or one whose fate the app cannot establish.
///
/// Stays until tapped away, because in every one of those cases the meal on file
/// carries less insulin than the user asked for, and only they can put that
/// right.
///
/// Deliberately quiet: a neutral panel with a small amber glyph, not a red slab.
/// Nothing here is an emergency — the pod stopped doing something — and shouting
/// about it next to the glucose reading would drown out the alarms that are.
class StoppedBolusNotice extends StatelessWidget {
  const StoppedBolusNotice({
    super.key,
    required this.controller,
    required this.dispatcher,
  });

  final PodController controller;
  final BolusDispatcher dispatcher;

  @override
  Widget build(BuildContext context) {
    final message = _message(context);
    if (message == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _dismiss,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsBold.info,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The stopped-bolus figure wins over a dispatcher failure: it is the more
  /// specific answer, and it carries the number the user needs.
  String? _message(BuildContext context) {
    final stopped = controller.cancelledBolus;
    if (stopped != null) {
      return Locales.string(context, 'pump.bolus.stopped')
          .replaceFirst('#', stopped.given.toStringAsFixed(2))
          .replaceFirst('#', stopped.programmed.toStringAsFixed(2));
    }
    final failure = dispatcher.failure;
    if (failure == null) {
      return null;
    }
    return '${Locales.string(context, 'pump.bolus.not_delivered')}'
        '${failure.detail == null ? '' : ' ${failure.detail}'}';
  }

  void _dismiss() {
    controller.clearCancelledBolus();
    dispatcher.dismissFailure();
  }
}
