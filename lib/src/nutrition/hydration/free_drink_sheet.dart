import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

/// Bottom sheet to enter a free drink amount in millilitres, in the app's sheet
/// style. Returns the amount, or null if dismissed.
Future<int?> showFreeDrinkSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FreeDrinkSheet(),
  );
}

class _FreeDrinkSheet extends StatefulWidget {
  const _FreeDrinkSheet();

  @override
  State<_FreeDrinkSheet> createState() => _FreeDrinkSheetState();
}

class _FreeDrinkSheetState extends State<_FreeDrinkSheet> {
  final TextEditingController _controller = TextEditingController();

  int get _ml => int.tryParse(_controller.text) ?? 0;

  void _submit() {
    if (_ml > 0) {
      Navigator.pop(context, _ml);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 18),
          LocaleText(
            'nutrition.hydration.free_title',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          _field(accent),
          const SizedBox(height: 20),
          _addButton(accent),
        ],
      ),
    );
  }

  Widget _field(Color accent) {
    return TextField(
      controller: _controller,
      autofocus: true,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      cursorColor: accent,
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: accent,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        suffixText: 'ml',
        hintText: Locales.string(context, 'nutrition.hydration.free_hint'),
        hintStyle: TextStyle(
          fontWeight: FontWeight.w400,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        filled: true,
        fillColor: accent.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _addButton(Color accent) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _ml > 0 ? _submit : null,
      child: LocaleText(
        'nutrition.hydration.add',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }
}
