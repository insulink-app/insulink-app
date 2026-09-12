import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/pump/pod_activation_steps.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// What the activation wizard says at each stage.
///
/// Presentation only — [PodActivationController] owns when each stage applies
/// and what the buttons do.
class PodActivationStageView extends StatelessWidget {
  const PodActivationStageView({
    super.key,
    required this.controller,
    this.basalProblem,
  });

  final PodActivationController controller;

  /// Why the active basal profile cannot be programmed, if it cannot. Shown at
  /// the very start, because discovering it after a pod is primed and bound would
  /// mean throwing that pod away.
  final String? basalProblem;

  @override
  Widget build(BuildContext context) {
    final progressKey = controller.progressKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _icon(context),
        const SizedBox(height: 20),
        LocaleText(
          _headlineKey,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        LocaleText(
          _bodyKey,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (progressKey != null) ...[
          const SizedBox(height: 18),
          _progress(context, progressKey),
        ],
        // Only the attach stage walks through steps. That is where the user has
        // something physical to do in a fixed order, right before the needle goes
        // in; everywhere else the app is working and a checklist would just be
        // something to scroll past.
        if (controller.stage == PodActivationStage.attachPod) ...[
          const SizedBox(height: 20),
          const PodActivationSteps(prefix: 'pump.activate.attach'),
        ],
        if (basalProblem != null) ...[
          const SizedBox(height: 14),
          _basalWarning(context),
        ],
      ],
    );
  }

  /// What the activation is doing right now, spelled out under the stage text.
  ///
  /// The stage headline covers a minute and a half of work in one sentence, so
  /// on its own it leaves the user watching a spinner with no way to tell a pod
  /// that is filling from one the app never found.
  Widget _progress(BuildContext context, String key) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.accent,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: LocaleText(
            key,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _icon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: scheme.tintPanel,
          shape: BoxShape.circle,
        ),
        child: Icon(_stageIcon, size: 34, color: context.accent),
      ),
    );
  }

  Widget _basalWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.danger.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'pump.activate.basal_problem',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.danger,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            basalProblem!,
            style: TextStyle(fontSize: 12, color: context.danger),
          ),
        ],
      ),
    );
  }

  IconData get _stageIcon => switch (controller.stage) {
    PodActivationStage.explaining => PhosphorIconsBold.info,
    PodActivationStage.priming => PhosphorIconsBold.drop,
    PodActivationStage.attachPod => PhosphorIconsBold.handTap,
    PodActivationStage.starting => PhosphorIconsBold.playCircle,
    PodActivationStage.running => PhosphorIconsBold.checkCircle,
    PodActivationStage.failed => PhosphorIconsBold.warningCircle,
  };

  String get _headlineKey {
    if (controller.stage == PodActivationStage.attachPod &&
        controller.isAlreadyAttached) {
      return 'pump.activate.attach_resume_title';
    }
    return 'pump.activate.${_stageKey}_title';
  }

  String get _bodyKey {
    if (controller.stage == PodActivationStage.attachPod &&
        controller.isAlreadyAttached) {
      return 'pump.activate.attach_resume_body';
    }
    return 'pump.activate.${_stageKey}_body';
  }

  String get _stageKey => switch (controller.stage) {
    PodActivationStage.explaining => 'explain',
    PodActivationStage.priming => 'priming',
    PodActivationStage.attachPod => 'attach',
    PodActivationStage.starting => 'starting',
    PodActivationStage.running => 'running',
    PodActivationStage.failed => 'failed',
  };
}
