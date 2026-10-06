import 'package:flutter/material.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_notice.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// What became of a bolus that did not simply run its course: one the user
/// stopped, one the pod refused, or one whose fate the app cannot establish.
///
/// Stays until tapped or swiped away, because in every one of those cases the
/// meal on file carries less insulin than the user asked for, and only they can
/// put that right.
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
    return OverviewNotice(
      dismissKey: 'stopped-bolus',
      icon: PhosphorIconsBold.info,
      message: message,
      onDismiss: _dismiss,
    );
  }

  /// The stopped-bolus figure wins over a dispatcher failure: it is the more
  /// specific answer, and it carries the number the user needs.
  String? _message(BuildContext context) {
    final stopped = controller.cancelledBolus;
    if (stopped != null) {
      return Locales.string(context, 'pump.bolus.stopped')
          .replaceFirst('#', sportDecimal(stopped.given, 2))
          .replaceFirst('#', sportDecimal(stopped.programmed, 2));
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
