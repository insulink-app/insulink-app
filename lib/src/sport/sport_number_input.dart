import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locales.dart';

/// Zahleneingabe per Tastatur statt nur +/-. Öffnet einen [Alert] mit
/// Zahlenfeld und ruft [onSubmit] mit dem geparsten, auf [min]..[max]
/// begrenzten Wert. [decimal] erlaubt Kommazahlen (z. B. Gewicht).
void showSportNumberInput(
  BuildContext context, {
  required String titleKey,
  required double initial,
  required double min,
  required double max,
  bool decimal = false,
  required void Function(double value) onSubmit,
}) {
  final controller = TextEditingController(
    text: decimal ? initial.toStringAsFixed(1) : initial.round().toString(),
  );
  Alert(
    icon: Icons.tag_rounded,
    content: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      child: TextField(
        controller: controller,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
          ),
        ],
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: Locales.string(context, titleKey),
        ),
      ),
    ),
    cancelButton: true,
    confirmButtonText: 'alert.ok',
    callback: () {
      final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
      if (parsed != null) {
        onSubmit(parsed.clamp(min, max).toDouble());
      }
    },
  ).show(context);
}
