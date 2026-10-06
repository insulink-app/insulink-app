import 'package:flutter/material.dart';
import 'package:insulink/src/injection/injection_page.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The round bolus button beside the navigation capsule: the accent filled
/// circle, carrying the dock's shadow, opening the bolus calculator.
class InjectionButton extends StatelessWidget {
  const InjectionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Semantics(
      button: true,
      label: Locales.string(context, 'injection.title'),
      excludeSemantics: true,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: colors.dockShadow,
        ),
        child: Material(
          color: colors.accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showInjectionSheet(context),
            child: Icon(
              PhosphorIconsRegular.syringe,
              size: 26,
              color: colors.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
