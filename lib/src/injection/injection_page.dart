import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/injection/injection_confirm_page.dart';
import 'package:insulink/src/injection/injection_products_tab.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
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

/// Carbs (manual OR summed from picked products) + current glucose → the
/// suggested, still-editable bolus. Glucose is handled in mg/dL throughout to
/// match the configured factors.
class InjectionSheet extends StatefulWidget {
  const InjectionSheet({super.key});

  @override
  State<InjectionSheet> createState() => _InjectionSheetState();
}

class _InjectionSheetState extends State<InjectionSheet> {
  static const _storage = FlutterSecureStorage();
  static const _kTab = 'injection_carb_tab';

  final _carbsController = TextEditingController();
  final _bolusController = TextEditingController();
  late final TextEditingController _glucoseController;

  /// 0 = manual carbs, 1 = products from the food database. Restored from and
  /// persisted to secure storage.
  int _tab = 0;
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
    _loadTab();
    // Prefill the suggestion from the prefilled glucose (listeners don't fire for
    // the initial text); after the first frame so setState is legal.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  Future<void> _loadTab() async {
    final stored = int.tryParse(await _storage.read(key: _kTab) ?? '');
    if (mounted && (stored == 0 || stored == 1)) {
      setState(() => _tab = stored!);
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

  void _selectTab(int tab) {
    setState(() => _tab = tab);
    _storage.write(key: _kTab, value: '$tab');
    _recompute();
  }

  double get _carbs {
    if (_tab == 1) {
      return _productEntries.fold(0, (sum, entry) => sum + entry.carbs);
    }
    return double.tryParse(_carbsController.text.replaceAll(',', '.')) ?? 0;
  }

  int? get _glucose => int.tryParse(_glucoseController.text);

  /// Suggested bolus in units, or null while glucose is empty/invalid.
  double? get _suggested {
    final glucose = _glucose;
    if (glucose == null) {
      return null;
    }
    final bolus = context.read<ProfileBolusState>();
    final glucoseState = context.read<ProfileGlucoseState>();
    final target = ((glucoseState.targetLow + glucoseState.targetHigh) / 2)
        .round();
    return bolus.suggestedBolus(
      carbs: _carbs,
      glucoseMgdl: glucose,
      targetMgdl: target,
    );
  }

  double? get _bolus =>
      double.tryParse(_bolusController.text.replaceAll(',', '.'));

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
    if (bolus == null || glucose == null) {
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
          entries: _tab == 1 ? _productEntries : const [],
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
          _tabs(),
          const SizedBox(height: 24),
          IndexedStack(
            index: _tab,
            sizing: StackFit.loose,
            children: [
              _NumberField(
                controller: _carbsController,
                labelKey: 'injection.carbs',
                suffix: 'g',
              ),
              InjectionProductsTab(onItemsChanged: _onProductItems),
            ],
          ),
          const SizedBox(height: 24),
          _NumberField(
            controller: _glucoseController,
            labelKey: 'injection.glucose',
            suffix: 'mg/dL',
          ),
          const SizedBox(height: 24),
          _NumberField(
            controller: _bolusController,
            labelKey: 'injection.bolus',
            suffix: Locales.string(context, 'injection.bolus.unit'),
            highlight: true,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_bolus == null || _glucose == null) ? null : _next,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('injection.next'),
          ),
        ],
      ),
    );
  }

  /// iOS-style segmented control matching the app's other switches
  /// (e.g. the glucose-unit selector).
  Widget _tabs() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(theme, 0, 'injection.carbs_tab')),
          Expanded(child: _segment(theme, 1, 'injection.products_tab')),
        ],
      ),
    );
  }

  Widget _segment(ThemeData theme, int tab, String labelKey) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () => _selectTab(tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: LocaleText(
          labelKey,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.surface
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.labelKey,
    required this.suffix,
    this.highlight = false,
  });

  final TextEditingController controller;
  final String labelKey;
  final String suffix;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: highlight
          ? TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            )
          : null,
      decoration: InputDecoration(
        labelText: Locales.string(context, labelKey),
        suffixText: suffix,
        // Only the bolus field overrides the theme fill; leave the others to
        // inherit the app's default filled style (passing false would strip it).
        filled: highlight ? true : null,
        fillColor: highlight ? scheme.primary.withValues(alpha: 0.06) : null,
      ),
    );
  }
}
