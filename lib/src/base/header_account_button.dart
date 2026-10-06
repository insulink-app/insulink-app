import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_page.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Header shortcut to the profile: a round badge with the first letter of the
/// stored name, or a person glyph while the name is empty.
class HeaderAccountButton extends StatelessWidget {
  const HeaderAccountButton({super.key});

  static const _storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    final colors = context.insulinkColors;
    return Semantics(
      button: true,
      label: Locales.string(context, 'profile.label'),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: HeaderIconButton.size,
        child: Material(
          color: colors.accentSoft,
          shape: CircleBorder(side: BorderSide(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => ProfilePage())),
            child: Center(child: _initial(colors)),
          ),
        ),
      ),
    );
  }

  Widget _initial(InsulinkColors colors) {
    return FutureBuilder<String?>(
      future: _storage.read(key: "name"),
      builder: (context, snapshot) {
        final name = (snapshot.data ?? "").trim();
        if (name.isEmpty) {
          return Icon(
            PhosphorIconsBold.user,
            size: 20,
            color: colors.accentText,
          );
        }
        return Text(
          name[0].toUpperCase(),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: colors.accentText,
          ),
        );
      },
    );
  }
}
