import 'dart:async';
import 'package:flutter/material.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/overview/overview_stopped_bolus.dart';
import 'package:insulink/src/overview/sending_bolus_card.dart';
import 'package:insulink/src/overview/running_bolus_card.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:provider/provider.dart';

/// The strip at the top of the overview while the pod is working through a bolus.
///
/// A pod delivers 0.05 U at a time, two seconds apart, so a 6 U bolus takes four
/// minutes. Without this the app would say "delivered" the moment the pod
/// accepted the command and show nothing for the four minutes that follow, which
/// is exactly when the user might want it to stop.
///
/// Renders nothing when no bolus is running, so the overview is unchanged the
/// rest of the time.
class OverviewRunningBolus extends StatefulWidget {
  const OverviewRunningBolus({super.key});

  @override
  State<OverviewRunningBolus> createState() => _OverviewRunningBolusState();
}

class _OverviewRunningBolusState extends State<OverviewRunningBolus> {
  /// Redraws once a second while a bolus runs. Progress comes from the clock, so
  /// nothing else would move it — and the timer only exists while there is
  /// something to show.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _keepTicking(bool running) {
    if (running && _tick == null) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!running && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final dispatcher = context.watch<BolusDispatcher>();
    final bolus = controller.runningBolus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keepTicking(bolus != null);
      }
    });
    if (bolus == null) {
      if (dispatcher.isSending) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SendingBolusCard(),
        );
      }
      return StoppedBolusNotice(controller: controller, dispatcher: dispatcher);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RunningBolusCard(controller: controller, bolus: bolus),
    );
  }
}
