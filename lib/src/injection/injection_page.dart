import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/recovery_bolus.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/injection/carbs_on_board.dart';
import 'package:insulink/src/injection/photo_carbs.dart';
import 'package:insulink/src/injection/photo_carbs_notice.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/injection/injection_confirm_button.dart';
import 'package:insulink/src/injection/meal_camera_page.dart';
import 'package:insulink/src/injection/injection_products_tab.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_nutrients_strip.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/injection/injection_sheet_parts.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Starts the bolus flow on the meal camera; the photo, or the manual choice,
/// replaces it with [InjectionPage].
Future<void> startInjection(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          MealCameraPage(next: (estimate) => InjectionPage(estimate: estimate)),
    ),
  );
}

/// Calculator and confirmation on one page: carbs (a manual amount PLUS the
/// ones summed from picked products) + current glucose → the suggested,
/// still-editable bolus, confirmed right here. Glucose is handled in mg/dL
/// throughout to match the configured factors.
///
/// Opened with the camera's [estimate], the carbs are already filled in; opened
/// without one, the carbs field takes the focus for typing.
class InjectionPage extends StatefulWidget {
  const InjectionPage({super.key, this.estimate});

  final PhotoEstimate? estimate;

  @override
  State<InjectionPage> createState() => _InjectionPageState();
}

class _InjectionPageState extends State<InjectionPage> {
  final _carbsController = TextEditingController();
  final _bolusController = TextEditingController();
  late final TextEditingController _glucoseController;

  /// Products picked from the food database; their carbs add to the manual
  /// [_carbsController] amount.
  List<MealEntry> _productEntries = const [];

  /// The last photo estimate. It stays when the user types over the carbs
  /// field: a corrected total is still that plate, so its foods and its photo
  /// stay on the meal. Only another photo replaces it.
  PhotoEstimate? _photoEstimate;

  /// What the meal is logged with: the photo's foods and the picked products,
  /// so protein reaches the day's totals either way.
  List<MealEntry> get _mealEntries => [
    ...?_photoEstimate?.entries(),
    ..._productEntries,
  ];

  /// Once the user types in the bolus field we stop overwriting it with the
  /// suggestion; [_settingBolus] guards our own programmatic writes.
  bool _bolusEdited = false;
  bool _settingBolus = false;

  /// The cut after a long endurance bout, read once when the sheet opens.
  RecoveryBolus _recoveryBolus = const RecoveryBolus.none();

  @override
  void initState() {
    super.initState();
    final current = context.read<CgmController>().currentMgdl;
    _glucoseController = TextEditingController(
      text: current != null ? '$current' : '',
    );
    if (widget.estimate case final estimate?) {
      _takeEstimate(estimate);
    }
    _carbsController.addListener(_recompute);
    _glucoseController.addListener(_recompute);
    _bolusController.addListener(_onBolusEdited);
    // Prefill the suggestion from the prefilled glucose (listeners don't fire for
    // the initial text); after the first frame so setState is legal.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
    _refreshPumpInsulin();
    _loadRecoveryBolus();
  }

  /// Reads the recovery cut, which is kept in storage by the service isolate's
  /// activity mode, and recomputes the suggestion with it.
  Future<void> _loadRecoveryBolus() async {
    final recovery = await RecoveryBolus.load(DateTime.now());
    if (mounted) {
      _recoveryBolus = recovery;
      _recompute();
    }
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
  double get _deliveredLastHour => context
      .read<PodController>()
      .store
      .bolusUnitsWithin(const Duration(hours: 1));

  /// Suggested bolus in units, or null while glucose is empty/invalid. Cut by
  /// [_recoveryBolus] after a long endurance bout.
  double? get _suggested {
    final glucose = _glucose;
    if (glucose == null) {
      return null;
    }
    final bolus = context.read<ProfileBolusState>();
    final glucoseState = context.read<ProfileGlucoseState>();
    return _recoveryBolus.reduce(
      bolus.suggestedBolus(
        carbs: _carbs,
        glucoseMgdl: glucose,
        targetMgdl: glucoseState.targetMid,
        iobUnits: _activeInsulin,
        cobGrams: const CarbsOnBoard().grams(context.read<MealState>().meals),
      ),
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
      _bolusController.text = _suggested == null
          ? ''
          : sportDecimal(_suggested!, 1);
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

  /// The bolus the confirm button may hand on: null while glucose is missing
  /// or the bolus is invalid or above the maximum, which disables it.
  double? get _confirmableBolus =>
      _glucose == null || _exceedsMax ? null : _bolus;

  /// Logs the confirmed meal, hands a pump dose to the dispatcher and closes.
  /// A handed over dose is not delivered yet: the dispatcher carries it from
  /// here and writes the insulin onto this exact meal once the pod names it.
  Future<void> _confirmed(BolusDeliveryResult outcome) async {
    final bolus = _bolus;
    final glucose = _glucose;
    if (bolus == null || glucose == null) {
      return;
    }
    final navigator = Navigator.of(context);
    final meal = await _record(context.read<MealState>(), glucose, outcome);
    if (outcome.isPending && mounted) {
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
      entries: _mealEntries,
      deliveredByPump: outcome.byPump,
    );
    await meals.addMeal(meal);
    return meal;
  }

  @override
  Widget build(BuildContext context) {
    final usesPump = _delivery.usesPump;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('injection.title'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  _mealCard(),
                  const SizedBox(height: 12),
                  _glucoseCard(),
                  const SizedBox(height: 12),
                  _bolusCard(context, usesPump),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: InjectionConfirmButton(
                bolus: _confirmableBolus,
                usesPump: usesPump,
                onConfirmed: _confirmed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The meal group: carbs typed by hand or estimated from a photo, plus any
  /// products picked from the food database, whose carbs add to that amount.
  /// With foods on the meal, their protein, fat and energy show below, since
  /// a fatty meal may call for a split bolus.
  Widget _mealCard() {
    return InjectionCard(
      icon: PhosphorIconsBold.forkKnife,
      titleKey: 'injection.carbs',
      trailing: PhotoCarbsButton(
        onEstimate: (estimate) => setState(() => _takeEstimate(estimate)),
      ),
      children: [
        InjectionNumberField(
          controller: _carbsController,
          suffix: 'g',
          autofocus: widget.estimate == null,
        ),
        if (_photoEstimate case final estimate?)
          PhotoCarbsNotice(estimate: estimate, onRecount: _recount),
        if (_photoEstimate == null) ...[
          const SizedBox(height: 10),
          InjectionProductsTab(
            onItemsChanged: _onProductItems,
            manualCarbs: _manualCarbs,
          ),
        ],
        if (_mealEntries.isNotEmpty) MealNutrientsStrip(meal: _draftMeal),
      ],
    );
  }

  /// The meal as it would be logged now, so the nutrient strip reads the same
  /// totals the meal log shows afterwards. Glucose and bolus play no part there.
  Meal get _draftMeal => Meal(
    time: DateTime.now(),
    carbs: _carbs,
    glucoseMgdl: 0,
    bolus: 0,
    entries: _mealEntries,
  );

  /// Writes the estimated carbs, rounded to whole grams, into the carbs field,
  /// replacing what was typed there. The field stays editable, and the listener
  /// recomputes the suggestion as for any typed value. The photo's foods take
  /// the place of the product picker, which is hidden from now on, so products
  /// picked before are dropped rather than counted on out of sight.
  void _takeEstimate(PhotoEstimate estimate) {
    _photoEstimate = estimate;
    _productEntries = const [];
    _carbsController.text = estimate.carbs.round().toString();
  }

  /// A corrected piece count moves the carbs field by the difference it makes,
  /// so a total the user typed over keeps its own correction: 70 typed, one
  /// macaroon of 12 g fewer, 58. Never below zero.
  void _recount(PhotoEstimateItem item, int count) {
    final recounted = _photoEstimate!.recounted(item, count);
    final corrected = _manualCarbs + recounted.carbs - _photoEstimate!.carbs;
    setState(() {
      _photoEstimate = recounted;
      _carbsController.text = corrected
          .clamp(0, double.infinity)
          .round()
          .toString();
    });
  }

  /// The current glucose group, prefilled from the latest reading.
  Widget _glucoseCard() {
    return InjectionCard(
      icon: PhosphorIconsBold.drop,
      titleKey: 'injection.glucose',
      children: [
        InjectionNumberField(controller: _glucoseController, suffix: 'mg/dL'),
      ],
    );
  }

  /// The suggested (still editable) bolus, followed by the active-insulin note
  /// that explains why the number was reduced; with a pod, where it goes.
  Widget _bolusCard(BuildContext context, bool usesPump) {
    return InjectionCard(
      icon: PhosphorIconsBold.syringe,
      titleKey: 'injection.bolus',
      emphasised: true,
      trailing: usesPump ? const InjectionPumpTag() : null,
      children: [
        InjectionNumberField(
          controller: _bolusController,
          suffix: Locales.string(context, 'injection.bolus.unit'),
          large: true,
          errorText: _exceedsMax
              ? Locales.string(
                  context,
                  'injection.bolus.exceeds_max',
                  params: ['$_maxBolus'],
                )
              : null,
        ),
        _activeInsulinNote(),
        if (_recoveryBolus.applies)
          _bolusNote(
            Locales.string(
              context,
              'injection.recovery_bolus',
              params: ['${_recoveryBolus.percent}'],
            ),
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
    return _bolusNote(
      Locales.string(
        context,
        'injection.active_insulin',
        params: [sportDecimal(units, 1)],
      ),
    );
  }

  /// One muted line under the bolus field that explains its number.
  Widget _bolusNote(String text) {
    final muted = context.ink.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Row(
        spacing: 8,
        children: [
          Icon(PhosphorIconsRegular.info, size: 16, color: muted),
          Expanded(
            child: Text(text, style: InkText.label.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }
}
