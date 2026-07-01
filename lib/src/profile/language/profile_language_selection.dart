import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/language/profile_language_state.dart';
import 'package:provider/provider.dart';

/// Language picker as a plain list of rows: a small flag, the language name and
/// a check on the active one — simpler than the old big flag buttons.
class ProfileLanguageSelection extends StatelessWidget {
  const ProfileLanguageSelection({super.key});

  static const _languages = [
    ("de", "assets/images/languages/de.webp"),
    ("en", "assets/images/languages/en.webp"),
  ];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<ProfileLanguageState>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (code, flag) in _languages) _row(context, state, code, flag),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ProfileLanguageState state,
    String code,
    String flag,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = state.getLanguage == code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _change(context, state, code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(flag, width: 34, height: 24, fit: BoxFit.cover),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: LocaleText(
                    "profile.language.$code",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    ProfileLanguageState state,
    String code,
  ) async {
    state.setLanguage(code);
    await const FlutterSecureStorage().write(key: "language", value: code);
    if (context.mounted) {
      await Locales.change(context, code);
    }
  }
}
