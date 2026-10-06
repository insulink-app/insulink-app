import 'package:flutter/material.dart';
import 'package:insulink/src/base/dock_tabs.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The floating navigation: a capsule with the tabs and, beside it, the round
/// bolus button.
///
/// It sits in the scaffold's navigation slot, so the page above ends where the
/// dock starts and nothing can scroll underneath it unreachable. The soft fade
/// the content runs out into is only PAINTED above the slot, over the last
/// strip of the page, and lets every touch through.
class FloatingDock extends StatelessWidget {
  const FloatingDock({
    super.key,
    required this.pageBodies,
    required this.selectedIndex,
    required this.badges,
    required this.onSelect,
  });

  final List<AppPageBody> pageBodies;
  final int selectedIndex;
  final Map<int, int> badges;
  final ValueChanged<int> onSelect;

  static const double _fade = 32;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return ColoredBox(
      color: colors.ground,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: -_fade,
            height: _fade,
            child: IgnorePointer(child: _fadeOut(colors)),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                spacing: 10,
                children: [
                  Expanded(child: _capsule(context, colors)),
                  const InjectionButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadeOut(InsulinkColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.ground.withValues(alpha: 0), colors.ground],
        ),
      ),
    );
  }

  Widget _capsule(BuildContext context, InsulinkColors colors) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: colors.dock,
        borderRadius: BorderRadius.circular(31),
        border: Border.all(color: colors.border),
        boxShadow: colors.dockShadow,
      ),
      child: DockTabs(
        pageBodies: pageBodies,
        selectedIndex: selectedIndex,
        badges: badges,
        onSelect: onSelect,
      ),
    );
  }
}
