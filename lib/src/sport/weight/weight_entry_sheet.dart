import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Eingabe-Sheet für einen neuen Gewichtseintrag (kg, Zeitpunkt = jetzt).
// ponytail: nur „jetzt" — ein Datumswähler wäre nachrüstbar, wenn rückwirkendes
// Erfassen gebraucht wird.
Future<void> showWeightEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<SportState>(),
      child: const _WeightEntrySheet(),
    ),
  );
}

class _WeightEntrySheet extends StatefulWidget {
  const _WeightEntrySheet();

  @override
  State<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<_WeightEntrySheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _kg {
    final value = double.tryParse(_controller.text.replaceAll(',', '.'));
    return (value != null && value > 0) ? value : null;
  }

  void _save() {
    context.read<SportState>().addWeight(_kg!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kg = _kg;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          LocaleText(
            'sport.weight.add',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: Locales.string(context, 'sport.weight'),
              suffixText: 'kg',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: kg == null ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: LocaleText('alert.done'),
          ),
        ],
      ),
    );
  }
}
