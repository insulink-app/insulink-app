import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/injection/injection_confirm_page.dart';
import 'package:insulink/src/injection/injection_products_tab.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
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
    _refreshPumpInsulin();
  }

  /// Re-reads the pod store before anything is suggested from it.
  ///
  /// The automation runs in the background SERVICE isolate and the store serves
  /// its getters from a cache that is per isolate. Without this the calculator
  /// would subtract whatever automated insulin this isolate happened to know
  /// about when the app started, which for a sheet opened hours later is none.
  Future<void> _refreshPumpInsulin() async {
    await context.read<PodController>().store.reload();
    if (mounted) {
      _recompute();
    }
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

  /// Everything still working, not just the user's own doses.
  ///
  /// It used to be the meal log alone. While the automation runs an elevated
  /// temporary basal, the insulin it has added is real and was invisible here, so
  /// the suggestion carried a full correction on top of it. That is the stacking
  /// hypo this calculator exists to prevent, arriving through the one door it was
  /// not watching. [InsulinOnBoard] is now the single answer both the calculator
  /// and the automation ask.
  ///
  /// Deliberately `read`, not `watch`: [_suggested] reaches this from the field
  /// listeners, which run OUTSIDE build, where watch throws. Nothing is lost —
  /// this sheet is the only way to log a dose, so the meal log cannot change
  /// while it is open.
  InsulinOnBoardParts get _onBoard {
    final duration = context.read<ProfileBolusState>().insulinDuration;
    return InsulinOnBoard(duration).parts(
      context.read<MealState>().meals,
      pod: context.read<PodController>().store,
    );
  }

  double get _activeInsulin => _onBoard.total;

  /// Bolus units the pod actually put out within the past hour.
  ///
  /// What the delivery guard's rolling ceiling is about, and NOT the same as
  /// insulin on board: on board reaches back a whole insulin duration and now
  /// also carries what the automation added, so using it here would refuse a
  /// legitimate meal bolus because of basal given two hours ago.
  double get _deliveredLastHour =>
      context.read<PodController>().store.bolusUnitsWithin(
            const Duration(hours: 1),
          );

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

  /// How the confirmed bolus reaches the body: through a paired pod when there is
  /// one, otherwise only into the log, exactly as before pump support existed.
  ///
  /// The pod's own limits sit underneath, but the ceilings passed here are the
  /// user's own [ProfileBolusState] settings, so the number the sheet already
  /// enforces is the number the pump enforces too.
  BolusDelivery get _delivery {
    final bolusSettings = context.read<ProfileBolusState>();
    return BolusDelivery(
      controller: context.read<PodController>(),
      maxBolusUnits: bolusSettings.maxBolus.toDouble(),
      maxUnitsPerHour: bolusSettings.maxBolus.toDouble(),
    );
  }

  Future<void> _next() async {
    final bolus = _bolus;
    final glucose = _glucose;
    if (bolus == null || glucose == null || bolus > _maxBolus) {
      return;
    }
    final navigator = Navigator.of(context);
    final meals = context.read<MealState>();
    final outcome = await navigator.push<BolusDeliveryResult>(
      MaterialPageRoute<BolusDeliveryResult>(
        builder: (_) => InjectionConfirmPage(
          carbs: _carbs,
          glucoseMgdl: glucose,
          bolus: bolus,
          delivery: _delivery,
          deliveredLastHour: _deliveredLastHour,
        ),
      ),
    );
    if (outcome == null || !mounted) {
      return;
    }
    final meal = await _record(meals, glucose, outcome);
    if (outcome.isPending && mounted) {
      // Handed over, not delivered: the dispatcher carries it from here and
      // writes the insulin onto this exact meal once the pod names it back.
      context.read<BolusDispatcher>().submit(
            delivery: _delivery,
            units: bolus,
            deliveredLastHour: _deliveredLastHour,
            meal: meal,
          );
    }
    if (mounted) {
      navigator.pop();
    }
  }

  /// Writes the meal.
  ///
  /// The carbs are certain — the user ate them — so the meal is always recorded.
  /// The insulin is only recorded at [BolusDeliveryResult.recordedUnits], which
  /// is zero unless a dose is known to have gone in. A refused or unconfirmed
  /// pump dose therefore logs the meal WITHOUT insulin: understating it can be
  /// corrected by logging the dose afterwards, whereas insulin in the log that
  /// never reached the body would suppress the next dose through IOB.
  Future<Meal> _record(
    MealState meals,
    int glucose,
    BolusDeliveryResult outcome,
  ) async {
    final meal = Meal(
      time: DateTime.now(),
      carbs: _carbs,
      glucoseMgdl: glucose,
      bolus: outcome.recordedUnits,
      entries: _productEntries,
      deliveredByPump: outcome.byPump,
    );
    await meals.addMeal(meal);
    return meal;
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
        InjectionProductsTab(
          onItemsChanged: _onProductItems,
          manualCarbs: _manualCarbs,
        ),
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
  /// The insulin already working, as ONE number.
  ///
  /// Not split into what came from a dose and what came from the pump. The
  /// suggestion below is computed from the total, so the total is what explains
  /// it; a breakdown here invites doing arithmetic on a sheet where the only
  /// question is how much to give now. The split is on the active-insulin page
  /// for anyone who wants it.
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
