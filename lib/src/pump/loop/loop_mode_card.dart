import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/loop/loop_cycle_line.dart';
import 'package:insulink/src/pump/loop/loop_switch.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/pump/loop/loop_journal_page.dart';

/// The switch that hands basal delivery to the automation, on the pump page.
///
/// Two positions, and OFF is not idle: it keeps deciding and writing each cycle
/// to the journal, it just never programs anything. So the way to check the
/// automation against a real day is simply to leave it off and read the journal,
/// which is what anyone would want from a switch they have not flipped yet.
///
/// Engaging asks twice, the way muting alarms does: a warning that has to be
/// read, then the device biometric. Turning it off is one tap, because only one
/// direction of this switch can hurt anyone.
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
    final mode = controller.store.loopMode;
    return InkPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const SizedBox(height: 14),
          SegmentedToggle<PodLoopMode>(
            semanticsLabel: Locales.string(context, 'pump.loop.title'),
            selected: mode,
            onChanged: controller.isBusy
                ? null
                : (picked) => _onPicked(context, controller, mode, picked),
            options: [
              for (final option in PodLoopMode.values)
                (
                  value: option,
                  label: Locales.string(
                    context,
                    'pump.loop.mode.${option.name}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LocaleText(
            'pump.loop.hint.${mode.name}',
            style: InkText.caption.copyWith(color: context.ink.muted),
          ),
          ..._stoppedNotice(context, controller),
          ..._blockedNotice(context),
        ],
      ),
    );
  }

  /// The title over what the automation last decided; a tap opens the journal
  /// that line comes from.
  Widget _header(BuildContext context) {
    return InkWell(
      onTap: () => PodLoopJournalPage.open(context),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                LocaleText('pump.loop.title', style: InkText.row),
                const PodLoopCycleLine(),
              ],
            ),
          ),
          Icon(
            PhosphorIconsBold.caretRight,
            size: 18,
            color: context.ink.muted,
          ),
        ],
      ),
    );
  }

  void _onPicked(
    BuildContext context,
    PodController controller,
    PodLoopMode current,
    PodLoopMode picked,
  ) {
    if (picked != current) {
      _pick(context, controller, picked);
    }
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
    final confirmed = await ProfileSecurityState().confirm(
      GuardedAction.loop,
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
