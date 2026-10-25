import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Pulses of the running bolus already felt, so each new one buzzes once.
  int _feltPulses = 0;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _keepTicking(bool running) {
    if (running && _tick == null) {
      _feltPulses = 0;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else if (!running && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  void _onTick() {
    _buzzOnPulse();
    setState(() {});
  }

  /// A short buzz for every pulse a bolus the user gave puts out, so the dose
  /// can be followed without looking. Only while the app is in the foreground
  /// (this timer cannot run otherwise, the check covers a locked screen), and
  /// never for a micro bolus the loop gave by itself.
  void _buzzOnPulse() {
    final bolus = context.read<PodController>().runningBolus;
    if (bolus == null || bolus.automated) {
      return;
    }
    final pulses = bolus.deliveredPulses(DateTime.now());
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (pulses > _feltPulses && foreground) {
      HapticFeedback.mediumImpact();
    }
    _feltPulses = pulses;
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
      child: RunningBolusCard(
        controller: controller,
        bolus: bolus,
        queued: bolus.automated && dispatcher.isSending,
      ),
    );
  }
}
