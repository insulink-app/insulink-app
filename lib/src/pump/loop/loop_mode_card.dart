import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_segments.dart';
import 'package:insulink/src/pump/loop/loop_cycle_line.dart';
import 'package:insulink/src/pump/loop/loop_switch.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The switch that hands basal delivery to the automation, on the pump page.
///
/// Three positions rather than two. Observation sits between off and engaged
/// because it is how the automation is checked against a real day: it decides
/// every cycle and writes each one to the log, and programs nothing. Anyone
/// turning this on for the first time should spend a while there.
///
/// Engaging asks twice, the way muting alarms does: a warning that has to be
/// read, then the device biometric. Both other positions are one tap, because
/// only one direction of this switch can hurt anyone.
class PodLoopModeCard extends StatefulWidget {
  const PodLoopModeCard({super.key});

  @override
  State<PodLoopModeCard> createState() => _PodLoopModeCardState();
}

class _PodLoopModeCardState extends State<PodLoopModeCard> {
  String? _blocked;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final scheme = Theme.of(context).colorScheme;
    final mode = controller.store.loopMode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LocaleText(
            'pump.loop.title',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          LocaleText(
            'pump.loop.hint.${mode.name}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ProfileSegments(_modes(context, controller, mode)),
          ..._stoppedNotice(context, controller),
          ..._blockedNotice(context),
          const SizedBox(height: 12),
          const PodLoopCycleLine(),
        ],
      ),
    );
  }

  List<ProfileSegment> _modes(
    BuildContext context,
    PodController controller,
    PodLoopMode current,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final mode in PodLoopMode.values)
        (
          labelKey: 'pump.loop.mode.${mode.name}',
          selected: mode == current,
          fill: mode == PodLoopMode.engaged ? scheme.primary : null,
          onTap: controller.isBusy || mode == current
              ? null
              : () => _pick(context, controller, mode),
        ),
    ];
  }

  /// Engaging is the only direction that starts insulin nobody asked for by hand,
  /// so it is the only one behind the warning and the biometric.
  Future<void> _pick(
    BuildContext context,
    PodController controller,
    PodLoopMode mode,
  ) async {
    if (mode != PodLoopMode.engaged) {
      await _apply(controller, mode);
      return;
    }
    final blocked = await LoopSwitch(controller).blockedReason();
    if (blocked != null) {
      setState(() => _blocked = blocked);
      return;
    }
    if (!context.mounted) {
      return;
    }
    _confirmEngage(context, controller);
  }

  void _confirmEngage(BuildContext context, PodController controller) {
    Alert(
      icon: PhosphorIconsFill.warning,
      iconColor: context.warning,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LocaleText(
              'pump.loop.warning.title',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const LocaleText(
              'pump.loop.warning.body',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.loop.warning.confirm',
      callback: () => _authThenEngage(context, controller),
    ).show(context);
  }

  Future<void> _authThenEngage(
    BuildContext context,
    PodController controller,
  ) async {
    final confirmed = await BiometricAuth().confirm(
      Locales.string(context, 'pump.loop.auth_reason'),
      allowDeviceCredential: true,
    );
    if (confirmed) {
      await _apply(controller, PodLoopMode.engaged);
    }
  }

  Future<void> _apply(PodController controller, PodLoopMode mode) async {
    final blocked = await LoopSwitch(controller).setMode(mode);
    if (mounted) {
      setState(() => _blocked = blocked);
    }
  }

  /// Why the automation stopped by itself. Stays until the user switches it back
  /// on, because a switch found in a different position than it was left in is
  /// exactly the thing that needs explaining.
  List<Widget> _stoppedNotice(BuildContext context, PodController controller) {
    final stop = controller.store.loopStop;
    if (stop == null) {
      return const [];
    }
    return [
      const SizedBox(height: 12),
      _notice(context, 'pump.loop.stopped.${stop.localeKey}', context.warning),
    ];
  }

  List<Widget> _blockedNotice(BuildContext context) {
    final blocked = _blocked;
    if (blocked == null) {
      return const [];
    }
    return [
      const SizedBox(height: 12),
      _notice(context, blocked, context.danger),
    ];
  }

  Widget _notice(BuildContext context, String key, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(PhosphorIconsBold.warning, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: LocaleText(key, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}
