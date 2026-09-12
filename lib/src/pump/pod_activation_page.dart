import 'package:flutter/material.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_activation_actions.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/pump/pod_activation_exit.dart';
import 'package:insulink/src/pump/pod_activation_stage_view.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_notice.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Opens the activation wizard.
///
/// The cannula confirmation is wired in here, at the point where a
/// [BuildContext] exists to prompt with. See [CannulaConfirmation] for why it is
/// asked at the button but consumed at the command.
Future<void> openPodActivation(BuildContext context) async {
  final controller = context.read<PodController>();
  final confirmation = CannulaConfirmation(
    reason: Locales.string(context, 'pump.activate.confirm_reason'),
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Provider<CannulaConfirmation>.value(
        value: confirmation,
        child: ChangeNotifierProvider(
          create: (_) => PodActivationController(
            store: controller.store,
            confirmCannulaInsertion: confirmation.consume,
          )..restoreStage(),
          child: const PodActivationPage(),
        ),
      ),
    ),
  );
  // The wizard wrote through the same store, but nothing would tell the page
  // behind it to look again — it would keep showing "no pod" until rebuilt.
  await controller.adoptActivatedPod();
}

/// Walks the user through starting a pod: acknowledge the binding, prime it off
/// the body, attach it, then let it start delivering.
///
/// The wizard never skips its own stages even when the protocol could continue
/// unattended — the pause at [PodActivationStage.attachPod] exists because the
/// pod has to physically move onto the body between the two halves, and no state
/// machine can know that happened.
///
/// It can always be left, including mid-search: [PodActivationExit] warns first
/// and stops the attempt cleanly, and the durable record means coming back
/// resumes rather than restarts.
class PodActivationPage extends StatefulWidget {
  const PodActivationPage({super.key});

  @override
  State<PodActivationPage> createState() => _PodActivationPageState();
}

class _PodActivationPageState extends State<PodActivationPage> {
  /// The screen stays on for the whole wizard. Priming alone runs close to a
  /// minute with nothing to tap, and a phone that sleeps mid-activation drops
  /// the link to a pod that is being filled or has a needle to drive.
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodActivationController>();
    final basal = _basal(context);
    return PopScope(
      canPop: !controller.isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          PodActivationExit(controller).leave(context);
        }
      },
      child: _scaffold(context, controller, basal),
    );
  }

  Widget _scaffold(
    BuildContext context,
    PodActivationController controller,
    PodBasalAdapter basal,
  ) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('pump.activate.title'),
        leading: IconButton(
          icon: const Icon(PhosphorIconsBold.arrowLeft),
          onPressed: () => PodActivationExit(controller).leave(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: PodActivationStageView(
                    controller: controller,
                    basalProblem: basal.problem,
                  ),
                ),
              ),
              ..._notices(controller),
              const SizedBox(height: 12),
              PodActivationActions(controller: controller, basal: basal),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _notices(PodActivationController controller) {
    final failureKey = controller.failureKey;
    return [
      if (controller.wasCancelled) const PumpNotice.declined(),
      if (failureKey != null)
        PumpNotice.problem(failureKey)
      else if (controller.failure != null)
        PumpNotice.failure(controller.failure!),
    ];
  }

  /// The pod schedule from the user's active basal profile.
  ///
  /// Converted up front so a profile the pod cannot hold is reported on the very
  /// first screen, rather than after the pod has already been primed and bound.
  PodBasalAdapter _basal(BuildContext context) =>
      PodBasalAdapter(context.watch<ProfileBasalState>().active);
}

/// The fingerprint that releases the cannula, asked at the button and spent at
/// the command.
///
/// Asking at the button is what the user expects: they tap "continue" and the
/// prompt is there, not half a minute later after a scan, a handshake and two
/// programming commands have run.
///
/// Consuming it at the command is what keeps it honest. [PodActivation] still
/// requires a confirmation callback and still refuses to move the needle without
/// one, so no path can reach the insertion unasked — and the answer is SINGLE
/// USE, so a confirmation given for one attempt cannot carry a later one.
class CannulaConfirmation {
  CannulaConfirmation({required this.reason, BiometricAuth? auth})
    : _auth = auth ?? BiometricAuth();

  /// What the biometric sheet says it is for.
  final String reason;

  final BiometricAuth _auth;

  bool _armed = false;

  /// Prompts now. Biometric only, no PIN fallback: driving a needle into the body
  /// is not something a pocket-tap should be able to do.
  Future<bool> ask() async {
    _armed = await _auth.confirm(reason);
    return _armed;
  }

  /// Hands the answer to the one command that needs it, and forgets it.
  Future<bool> consume() async {
    final armed = _armed;
    _armed = false;
    return armed;
  }
}
