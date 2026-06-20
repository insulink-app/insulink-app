import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_language_state.dart';
import 'package:provider/provider.dart';

class ProfileLanguageSelection extends StatelessWidget {
  const ProfileLanguageSelection({super.key});

  @override
  Widget build(BuildContext context) {
    var languageState = Provider.of<ProfileLanguageState>(context);
    return Container(
      alignment: Alignment.center,
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceEvenly,
        overflowAlignment: OverflowBarAlignment.center,
        children: [
          createLanguageButton(
            languageState,
            "assets/images/languages/en.webp",
            "en",
            languageState.getLanguage == "en",
            context,
          ),
          createLanguageButton(
            languageState,
            "assets/images/languages/de.webp",
            "de",
            languageState.getLanguage == "de",
            context,
          ),
        ],
      ),
    );
  }

  Container createLanguageButton(
    ProfileLanguageState languageState,
    String flag,
    String language,
    bool selected,
    BuildContext context,
  ) {
    var theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.all(10),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : theme.scaffoldBackgroundColor,
          padding: EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : theme.colorScheme.primary.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
        ),
        onPressed: () async {
          await changeLanguage(languageState, language, context);
          if (context.mounted) await Locales.change(context, language);
        },
        child: Container(
          width: 120,
          height: 65,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            image: DecorationImage(image: AssetImage(flag), fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Future<void> changeLanguage(
    ProfileLanguageState languageState,
    String language,
    BuildContext context,
  ) async {
    languageState.setLanguage(language);
    const storage = FlutterSecureStorage();
    await storage.write(key: "language", value: language);
  }
}
