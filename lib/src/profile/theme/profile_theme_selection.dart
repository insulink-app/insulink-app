import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/theme/profile_theme_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class ProfileThemeSelection extends StatelessWidget {
  const ProfileThemeSelection({super.key});

  @override
  Widget build(BuildContext context) {
    var themeState = Provider.of<ProfileThemeState>(context);
    return Container(
      alignment: Alignment.center,
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceEvenly,
        overflowAlignment: OverflowBarAlignment.center,
        children: [
          _buildThemeButton(
            themeState,
            ThemeMode.light,
            PhosphorIconsBold.sun,
            "profile.theme.light",
            context,
          ),
          _buildThemeButton(
            themeState,
            ThemeMode.dark,
            PhosphorIconsBold.moon,
            "profile.theme.dark",
            context,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton(
    ProfileThemeState themeState,
    ThemeMode mode,
    IconData icon,
    String label,
    BuildContext context,
  ) {
    var theme = Theme.of(context);
    final selected = themeState.themeMode == mode;
    return Container(
      margin: const EdgeInsets.all(10),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
              : theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
        ),
        onPressed: () async {
          themeState.setThemeMode(mode);
          await _saveTheme(mode);
        },
        child: SizedBox(
          width: 120,
          height: 65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.colorScheme.onSurface, size: 28),
              const SizedBox(height: 6),
              LocaleText(
                label,
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: "theme",
      value: mode == ThemeMode.dark ? "dark" : "light",
    );
  }
}
