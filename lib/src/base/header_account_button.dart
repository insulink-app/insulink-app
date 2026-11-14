import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_page.dart';
import 'package:insulink/src/request/server_reachability.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Header shortcut to the profile: a round badge with the first letter of the
/// stored name, or a person glyph while the name is empty. A dot at its foot
/// says whether the server answered the last request ([ServerReachability]):
/// green when it did, red when it did not, none before the first request.
class HeaderAccountButton extends StatelessWidget {
  const HeaderAccountButton({super.key});

  static const _storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: ServerReachability.shared,
      builder: (context, reachable, _) => _badge(context, reachable),
    );
  }

  Widget _badge(BuildContext context, bool? reachable) {
    final colors = context.ink;
    return Semantics(
      button: true,
      label: _label(context, reachable),
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _avatar(context, colors),
          if (reachable != null) _statusDot(colors, reachable),
        ],
      ),
    );
  }

  String _label(BuildContext context, bool? reachable) {
    final profile = Locales.string(context, 'profile.label');
    if (reachable == null) {
      return profile;
    }
    final status = Locales.string(
      context,
      reachable ? 'profile.server.online' : 'profile.server.offline',
    );
    return '$profile, $status';
  }

  /// Ringed in the page colour, so it stays legible on the badge's own rim.
  Widget _statusDot(InsulinkColors colors, bool reachable) {
    return Positioned(
      right: 0,
      bottom: 0,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: reachable ? colors.range : colors.low,
          border: Border.all(color: colors.ground, width: 2),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, InsulinkColors colors) {
    return SizedBox.square(
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
