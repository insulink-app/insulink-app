import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_backup_restore.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_sync.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Offers to adopt the pod the account is holding, shown when no pod is paired
/// locally but one is on file — typically right after a reinstall or a reset.
///
/// Renders nothing until the backend confirms a pod exists, so a user with none
/// never sees an empty promise.
///
/// It cannot be dismissed, only answered. A pod still on the body is reachable
/// through these credentials and nothing else, so offering it once and forgetting
/// would be a way to lose it. The second answer is that the pod is GONE, which
/// stamps the record so it stops being offered: without that, a dead pod is
/// suggested at every launch with no way to say no, which is what happened. The
/// record itself stays, in the pump history.
class PodRestoreCard extends StatefulWidget {
  const PodRestoreCard({super.key});

  @override
  State<PodRestoreCard> createState() => _PodRestoreCardState();
}

class _PodRestoreCardState extends State<PodRestoreCard> {
  PodRestore? _offer;
  bool _adopting = false;
  bool _discarding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<PodController>();
    final offer = await PodBackupRestore(
      controller.store,
    ).availableBackendPod(context);
    if (mounted) {
      setState(() => _offer = offer);
    }
  }

  Future<void> _use() async {
    final offer = _offer;
    if (offer == null || _adopting) {
      return;
    }
    setState(() => _adopting = true);
    final controller = context.read<PodController>();
    await PodBackupRestore(controller.store).restoreFromBackend(offer);
    await controller.adoptRestoredPod();
    if (mounted) {
      setState(() {
        _adopting = false;
        _offer = null;
      });
    }
  }

  /// Asks before retiring it, and says what is lost. Nothing here can be
  /// checked: the account cannot see whether the pod is on the body, and the
  /// user can.
  void _confirmDiscard() {
    final offer = _offer;
    if (offer == null || _adopting || _discarding) {
      return;
    }
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              'pump.restore.discard_title',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            LocaleText(
              'pump.restore.discard_body',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.restore.discard_confirm',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () => _discard(offer),
    ).show(context);
  }

  /// The card goes only once the account has accepted it. Hiding it on a failed
  /// call would leave the pod still being offered and the card back at the next
  /// launch, with the user believing they had already dealt with it.
  Future<void> _discard(PodRestore offer) async {
    setState(() => _discarding = true);
    final dropped = await PumpSync().discard(offer.pumpId, context);
    if (mounted) {
      setState(() {
        _discarding = false;
        _offer = dropped ? null : _offer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // The card's own gap, because it collapses to nothing when there is no pod
      // on file — a spacer at the call site would be left hanging.
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const SizedBox(height: 6),
          LocaleText(
            'pump.restore.body',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            _remaining(context, offer),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _adopting || _discarding ? null : _use,
            icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 18),
            label: LocaleText('pump.restore.use'),
          ),
          const SizedBox(height: 6),
          // Quieter than the offer it sits under, because adopting the pod is
          // what a user with one on their body is here to do. This is the answer
          // for the other case, not a second thing to weigh.
          TextButton(
            onPressed: _adopting || _discarding ? null : _confirmDiscard,
            child: LocaleText(
              'pump.restore.discard',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Icon(PhosphorIconsFill.syringe, size: 18, color: context.accent),
        const SizedBox(width: 8),
        Expanded(
          child: LocaleText(
            'pump.restore._',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.accent,
            ),
          ),
        ),
      ],
    );
  }

  /// How much of the pod's life is left, so the user can tell whether adopting it
  /// is still worth doing.
  String _remaining(BuildContext context, PodRestore offer) {
    final left = offer.remaining;
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    return Locales.string(
      context,
      'pump.restore.remaining',
    ).replaceFirst('#', '${hours}h ${minutes}min');
  }
}
