import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One group of the bolus calculator: a 32 px icon tile and a title over the
/// group's fields, on a raised card inside the sheet. Kept quiet on purpose:
/// all cards alike, neutral icon tiles, and only the [emphasised] bolus tile
/// touched with the accent. The accent is for the "Next" button and the field
/// being typed in.
class InjectionCard extends StatelessWidget {
  const InjectionCard({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.children,
    this.emphasised = false,
  });

  final IconData icon;
  final String titleKey;
  final List<Widget> children;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised,
        borderRadius: BorderRadius.circular(InkRadius.tile),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 10,
            children: [
              _tile(colors),
              LocaleText(titleKey, style: InkText.rowTitle),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _tile(InsulinkColors colors) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: emphasised
            ? colors.accent.withValues(alpha: 0.14)
            : colors.text.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 18,
        color: emphasised ? colors.accent : colors.muted,
      ),
    );
  }
}

/// A number field of the calculator: sunk into the card in the page colour,
/// the unit muted on the right and always visible. [large] is the bolus:
/// 84 px high with the number at 52.
class InjectionNumberField extends StatelessWidget {
  const InjectionNumberField({
    super.key,
    required this.controller,
    required this.suffix,
    this.large = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String suffix;
  final bool large;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: InkText.bigValue.copyWith(
        fontSize: large ? 52 : 22,
        letterSpacing: large ? -1.5 : 0,
        color: colors.text,
      ),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: InkText.bigValue.copyWith(
          fontSize: large ? 52 : 22,
          color: colors.muted.withValues(alpha: 0.6),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: large ? 16 : 17,
        ),
        // `suffixText` hides while the field is empty and unfocused; a
        // `suffixIcon` is always shown, so the unit stays visible at all times.
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 18, left: 4),
          child: Text(
            suffix,
            style: (large ? InkText.section : InkText.body).copyWith(
              fontWeight: large ? FontWeight.w800 : FontWeight.w400,
              color: colors.muted,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        errorText: errorText,
      ),
    );
  }
}
