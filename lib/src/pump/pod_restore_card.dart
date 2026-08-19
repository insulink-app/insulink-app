import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_backup_restore.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_sync.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Offers to adopt the pod the account is holding, shown when no pod is paired
/// locally but one is on file — typically right after a reinstall or a reset.
///
/// Renders nothing until the backend confirms a pod exists, so a user with none
/// never sees an empty promise. Unlike the sensor's equivalent this has no
/// dismiss action: a pod that is still on the body and only reachable through
/// these credentials is not something to offer once and forget.
class PodRestoreCard extends StatefulWidget {
  const PodRestoreCard({super.key});

  @override
  State<PodRestoreCard> createState() => _PodRestoreCardState();
}

class _PodRestoreCardState extends State<PodRestoreCard> {
  PodRestore? _offer;
  bool _adopting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<PodController>();
    final offer = await PodBackupRestore(controller.store).availableBackendPod(context);
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
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _adopting ? null : _use,
            icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 18),
            label: LocaleText('pump.restore.use'),
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
    return Locales.string(context, 'pump.restore.remaining')
        .replaceFirst('#', '${hours}h ${minutes}min');
  }
}
