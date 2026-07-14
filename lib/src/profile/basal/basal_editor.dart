import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/basal/basal_bar_chart.dart';
import 'package:insulink/src/profile/basal/basal_peak_row.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Full-screen editor for one basal-rate profile. Works on a local copy of the
/// profile: rename it, tap/drag a bar to set an hour, or shape a curve from a
/// daily total plus movable maxima. Nothing is persisted until the user taps the
/// explicit Save button; leaving with unsaved edits prompts save-or-discard.
class BasalEditor extends StatefulWidget {
  const BasalEditor({super.key, required this.index});

  final int index;

  @override
  State<BasalEditor> createState() => _BasalEditorState();
}

class _BasalEditorState extends State<BasalEditor> {
  late final ProfileBasalState _state = context.read<ProfileBasalState>();
  late final BasalProfile _profile = _state.profiles[widget.index].copy();
  late final TextEditingController _name = TextEditingController(
    text: _profile.name,
  );
  late final TextEditingController _total = TextEditingController(
    text: _profile.dailyTotal.toStringAsFixed(1),
  );
  int _selectedHour = 8;

  /// Set by any edit; drives the save-or-discard prompt on leave.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => _dirty = true);
  }

  double get _totalUnits =>
      double.tryParse(_total.text.replaceAll(',', '.')) ?? 0;

  void _setHour(int hour, double rate) {
    setState(() {
      _selectedHour = hour;
      _dirty = true;
      _profile.setHour(hour, rate);
    });
  }

  void _regenerate() {
    setState(() {
      _dirty = true;
      _profile.dailyTotal = _totalUnits;
      _profile.regenerate();
    });
  }

  void _addPeak() {
    setState(() => _profile.peaks.add(BasalPeak(14, 1.0)));
    _regenerate();
  }

  /// Commits the local copy to [ProfileBasalState] and leaves the editor.
  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      _profile.name = name;
    }
    _state.updateProfile(widget.index, _profile);
    Navigator.pop(context);
  }

  /// Back action: leave straight away when nothing changed, otherwise ask to
  /// save or discard.
  void _onBack() {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    Alert(
      icon: PhosphorIconsRegular.floppyDisk,
      description: 'profile.basal.unsaved',
      cancelButton: true,
      cancelButtonText: 'profile.basal.discard',
      confirmButtonText: 'profile.basal.save',
      callback: _save,
      cancelCallback: () => Navigator.pop(context),
    ).show(context);
  }

  @override
  void dispose() {
    _name.dispose();
    _total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(PhosphorIconsRegular.arrowLeft),
            onPressed: _onBack,
          ),
          title: LocaleText('profile.basal'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _nameField(),
            const SizedBox(height: 20),
            _totalLabel(),
            const SizedBox(height: 12),
            BasalBarChart(
              rates: _profile.rates,
              selectedHour: _selectedHour,
              onChanged: _setHour,
              onSelect: (hour) => setState(() => _selectedHour = hour),
            ),
            const SizedBox(height: 20),
            _card(child: _hourStepper()),
            const SizedBox(height: 16),
            _card(child: _generator()),
            const SizedBox(height: 24),
            _saveButton(),
          ],
        ),
      ),
    );
  }

  Widget _saveButton() {
    return FilledButton(
      onPressed: _save,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: LocaleText('profile.basal.save'),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _name,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: Locales.string(context, 'profile.basal.name'),
        prefixIcon: const Icon(PhosphorIconsRegular.tag),
      ),
    );
  }

  Widget _totalLabel() {
    return Text(
      Locales.string(
        context,
        'profile.basal.total',
        params: [_profile.total.toStringAsFixed(2)],
      ),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }

  /// A rounded, bordered container matching the settings cards elsewhere.
  Widget _card({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }

  Widget _hourStepper() {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CircleIconButton(
          icon: PhosphorIconsRegular.minus,
          accent: accent,
          onTap: () => _setHour(
            _selectedHour,
            _profile.rates[_selectedHour] - BasalProfile.step,
          ),
        ),
        Column(
          children: [
            Text(
              '${_selectedHour.toString().padLeft(2, '0')}:00',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Text(
              '${_profile.rates[_selectedHour].toStringAsFixed(2)} E/h',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
        CircleIconButton(
          icon: PhosphorIconsRegular.plus,
          accent: accent,
          onTap: () => _setHour(
            _selectedHour,
            _profile.rates[_selectedHour] + BasalProfile.step,
          ),
        ),
      ],
    );
  }

  Widget _generator() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIconsRegular.chartLineUp, size: 20, color: accent),
            const SizedBox(width: 8),
            LocaleText(
              'profile.basal.generate',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _totalField(),
        const SizedBox(height: 8),
        for (final peak in _profile.peaks) ...[
          Divider(height: 20, color: theme.dividerColor),
          BasalPeakRow(
            key: ObjectKey(peak),
            peak: peak,
            onChanged: _regenerate,
            onDelete: () {
              setState(() => _profile.peaks.remove(peak));
              _regenerate();
            },
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addPeak,
            icon: const Icon(PhosphorIconsRegular.plus),
            label: LocaleText('profile.basal.add_peak'),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalField() {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _total,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: Locales.string(context, 'profile.basal.daily_total'),
              suffixText: 'E',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _regenerate,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: LocaleText('profile.basal.apply'),
        ),
      ],
    );
  }
}
