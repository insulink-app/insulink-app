import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:provider/provider.dart';

/// Opens the bolus-calculator as a modal bottom sheet. The glucose field is
/// prefilled with the latest reading from [CgmController] when available.
Future<void> showInjectionSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const InjectionSheet(),
  );
}

/// Carbs + current-glucose inputs and the resulting suggested bolus. Glucose is
/// handled in mg/dL throughout to match the configured factors.
class InjectionSheet extends StatefulWidget {
  const InjectionSheet({super.key});

  @override
  State<InjectionSheet> createState() => _InjectionSheetState();
}

class _InjectionSheetState extends State<InjectionSheet> {
  final _carbsController = TextEditingController();
  late final TextEditingController _glucoseController;

  @override
  void initState() {
    super.initState();
    final current = context.read<CgmController>().currentMgdl;
    _glucoseController = TextEditingController(
      text: current != null ? '$current' : '',
    );
    _carbsController.addListener(_recompute);
    _glucoseController.addListener(_recompute);
  }

  @override
  void dispose() {
    _carbsController.dispose();
    _glucoseController.dispose();
    super.dispose();
  }

  void _recompute() => setState(() {});

  /// Suggested bolus in units, or null while the glucose input is empty/invalid.
  double? get _bolus {
    final glucose = int.tryParse(_glucoseController.text);
    if (glucose == null) {
      return null;
    }
    final carbs =
        double.tryParse(_carbsController.text.replaceAll(',', '.')) ?? 0;
    final bolus = context.read<ProfileBolusState>();
    final glucoseState = context.read<ProfileGlucoseState>();
    final target = ((glucoseState.targetLow + glucoseState.targetHigh) / 2)
        .round();
    return bolus.suggestedBolus(
      carbs: carbs,
      glucoseMgdl: glucose,
      targetMgdl: target,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bolus = _bolus;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          LocaleText(
            'injection.title',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _NumberField(
            controller: _carbsController,
            labelKey: 'injection.carbs',
            suffix: 'g',
          ),
          const SizedBox(height: 16),
          _NumberField(
            controller: _glucoseController,
            labelKey: 'injection.glucose',
            suffix: 'mg/dL',
          ),
          const SizedBox(height: 16),
          _BolusField(bolus: bolus),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: bolus == null ? null : () {},
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('injection.next'),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.labelKey,
    required this.suffix,
  });

  final TextEditingController controller;
  final String labelKey;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: Locales.string(context, labelKey),
        suffixText: suffix,
      ),
    );
  }
}

/// Read-only field showing the calculated bolus.
class _BolusField extends StatelessWidget {
  const _BolusField({required this.bolus});

  final double? bolus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = bolus;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: Locales.string(context, 'injection.bolus'),
        filled: true,
        fillColor: theme.colorScheme.primary.withValues(alpha: 0.06),
      ),
      child: Text(
        value == null
            ? '–'
            : Locales.string(
                context,
                'injection.bolus.value',
                params: [value.toStringAsFixed(1)],
              ),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
