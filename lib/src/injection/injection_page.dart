import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/injection/injection_confirm_page.dart';
import 'package:insulink/src/injection/injection_products_tab.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Opens the bolus-calculator as a modal bottom sheet. The glucose field is
/// prefilled with the latest reading from [CgmController] when available.
Future<void> showInjectionSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const InjectionSheet(),
  );
}

/// Carbs (a manual amount PLUS the ones summed from picked products) + current
/// glucose → the suggested, still-editable bolus. Glucose is handled in mg/dL
/// throughout to match the configured factors.
class InjectionSheet extends StatefulWidget {
  const InjectionSheet({super.key});

  @override
  State<InjectionSheet> createState() => _InjectionSheetState();
}

class _InjectionSheetState extends State<InjectionSheet> {
  final _carbsController = TextEditingController();
  final _bolusController = TextEditingController();
  late final TextEditingController _glucoseController;

  /// Products picked from the food database; their carbs add to the manual
  /// [_carbsController] amount.
  List<MealEntry> _productEntries = const [];

  /// Once the user types in the bolus field we stop overwriting it with the
  /// suggestion; [_settingBolus] guards our own programmatic writes.
  bool _bolusEdited = false;
  bool _settingBolus = false;

  @override
  void initState() {
    super.initState();
    final current = context.read<CgmController>().currentMgdl;
    _glucoseController = TextEditingController(
      text: current != null ? '$current' : '',
    );
    _carbsController.addListener(_recompute);
    _glucoseController.addListener(_recompute);
    _bolusController.addListener(_onBolusEdited);
    // Prefill the suggestion from the prefilled glucose (listeners don't fire for
    // the initial text); after the first frame so setState is legal.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _carbsController.dispose();
    _glucoseController.dispose();
    _bolusController.dispose();
    super.dispose();
  }

  void _onBolusEdited() {
    if (_settingBolus) {
      return;
    }
    _bolusEdited = true;
    setState(() {});
  }

  double get _manualCarbs =>
      double.tryParse(_carbsController.text.replaceAll(',', '.')) ?? 0;

  double get _productCarbs =>
      _productEntries.fold(0, (sum, entry) => sum + entry.carbs);

  double get _carbs => _manualCarbs + _productCarbs;

  int? get _glucose => int.tryParse(_glucoseController.text);

  /// Units still active from earlier boluses, read from the meal log.
  ///
  /// Deliberately `read`, not `watch`: [_suggested] reaches this from the field
  /// listeners, which run OUTSIDE build, where watch throws. Nothing is lost —
  /// this sheet is the only way to log a dose, so the meal log cannot change
  /// while it is open.
  double get _activeInsulin {
    final duration = context.read<ProfileBolusState>().insulinDuration;
    return ActiveInsulin(duration).units(context.read<MealState>().meals);
  }

  /// Suggested bolus in units, or null while glucose is empty/invalid.
  double? get _suggested {
    final glucose = _glucose;
    if (glucose == null) {
      return null;
    }
    final bolus = context.read<ProfileBolusState>();
    final glucoseState = context.read<ProfileGlucoseState>();
    return bolus.suggestedBolus(
      carbs: _carbs,
      glucoseMgdl: glucose,
      targetMgdl: glucoseState.targetMid,
      iobUnits: _activeInsulin,
    );
  }

  double? get _bolus =>
      double.tryParse(_bolusController.text.replaceAll(',', '.'));

  int get _maxBolus => context.read<ProfileBolusState>().maxBolus;

  /// Whether the entered bolus is above the user's configured maximum. The
  /// suggestion is deliberately NOT capped to it: silently rewriting the number
  /// would hide the conflict, so an over-max value blocks the sheet instead and
  /// the user lowers it themselves.
  bool get _exceedsMax => (_bolus ?? 0) > _maxBolus;

  /// Recompute the suggestion; overwrite the bolus field only while the user
  /// hasn't edited it themselves.
  void _recompute() {
    if (!_bolusEdited) {
      _settingBolus = true;
      _bolusController.text = _suggested?.toStringAsFixed(1) ?? '';
      _settingBolus = false;
    }
    setState(() {});
  }

  void _onProductItems(List<MealEntry> items) {
    _productEntries = items;
    _recompute();
  }

  Future<void> _next() async {
    final bolus = _bolus;
    final glucose = _glucose;
    if (bolus == null || glucose == null || bolus > _maxBolus) {
      return;
    }
    final navigator = Navigator.of(context);
    final meals = context.read<MealState>();
    final confirmed = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => InjectionConfirmPage(
          carbs: _carbs,
          glucoseMgdl: glucose,
          bolus: bolus,
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await meals.addMeal(
        Meal(
          time: DateTime.now(),
          carbs: _carbs,
          glucoseMgdl: glucose,
          bolus: bolus,
          entries: _productEntries,
        ),
      );
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
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
          const SizedBox(height: 20),
          _mealCard(),
          const SizedBox(height: 16),
          _glucoseCard(),
          const SizedBox(height: 16),
          _bolusCard(context),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_bolus == null || _glucose == null || _exceedsMax)
                ? null
                : _next,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('injection.next'),
          ),
        ],
      ),
    );
  }

  /// The meal group: carbs typed by hand plus any products picked from the food
  /// database, whose carbs add to the manual amount.
  Widget _mealCard() {
    return _InjectionCard(
      icon: PhosphorIconsBold.forkKnife,
      titleKey: 'injection.carbs',
      children: [
        _NumberField(controller: _carbsController, suffix: 'g'),
        const SizedBox(height: 16),
        LocaleText(
          'injection.products_tab',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        InjectionProductsTab(onItemsChanged: _onProductItems),
      ],
    );
  }

  /// The current glucose group, prefilled from the latest reading.
  Widget _glucoseCard() {
    return _InjectionCard(
      icon: PhosphorIconsBold.drop,
      titleKey: 'injection.glucose',
      children: [
        _NumberField(controller: _glucoseController, suffix: 'mg/dL'),
      ],
    );
  }

  /// The suggested (still editable) bolus, preceded by the active-insulin note
  /// that explains why the number was reduced.
  Widget _bolusCard(BuildContext context) {
    return _InjectionCard(
      icon: PhosphorIconsBold.syringe,
      titleKey: 'injection.bolus',
      children: [
        _activeInsulinNote(),
        _NumberField(
          controller: _bolusController,
          suffix: Locales.string(context, 'injection.bolus.unit'),
          highlight: true,
          errorText: _exceedsMax
              ? Locales.string(
                  context,
                  'injection.bolus.exceeds_max',
                  params: ['$_maxBolus'],
                )
              : null,
        ),
      ],
    );
  }

  /// States the active insulin the suggestion below was reduced by, so the number
  /// in the bolus field is never an unexplained one. Hidden while nothing is
  /// active: "0.0 U on board" carries no information and would only make the
  /// sheet look busier.
  Widget _activeInsulinNote() {
    final units = _activeInsulin;
    if (units <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        Locales.string(
          context,
          'injection.active_insulin',
          params: [units.toStringAsFixed(1)],
        ),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// A titled, boxed group inside the bolus sheet: an icon + section title over
/// the fields that belong together, so the sheet reads as distinct steps
/// instead of one flat stack of inputs.
class _InjectionCard extends StatelessWidget {
  const _InjectionCard({
    required this.icon,
    required this.titleKey,
    required this.children,
  });

  final IconData icon;
  final String titleKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              LocaleText(
                titleKey,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.suffix,
    this.highlight = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String suffix;
  final bool highlight;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: highlight
          ? TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            )
          : null,
      decoration: InputDecoration(
        // `suffixText` hides while the field is empty and unfocused; a
        // `suffixIcon` is always shown, so the unit stays visible at all times.
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: Text(
            suffix,
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        errorText: errorText,
        // The bolus field overrides the fill with the brand tint; the others
        // inherit the theme's raised-surface fill (passing false would strip it).
        filled: highlight ? true : null,
        fillColor: highlight ? scheme.tintPanel : null,
      ),
    );
  }
}
