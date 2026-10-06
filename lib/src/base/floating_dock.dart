import 'package:flutter/material.dart';
import 'package:insulink/src/base/nav_badge.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

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
    final colors = context.insulinkColors;
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var index = 0; index < pageBodies.length; index++)
            _tab(context, colors, index),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, InsulinkColors colors, int index) {
    final body = pageBodies[index];
    final label = Locales.string(context, body.name);
    final selected = index == selectedIndex;
    final count = badges[index];
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          selected
              ? _activeTab(colors, body, label)
              : _idleTab(colors, body, index),
          if (count != null && count != 0) NavBadge(count: count),
        ],
      ),
    );
  }

  /// The current tab as a pill: icon and label on the soft accent.
  Widget _activeTab(InsulinkColors colors, AppPageBody body, String label) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Icon(body.unselectedIcon, size: 22, color: colors.accentText),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.accentText,
            ),
          ),
        ],
      ),
    );
  }

  /// Any other tab: only its icon, muted, on a 48 px round target.
  Widget _idleTab(InsulinkColors colors, AppPageBody body, int index) {
    return SizedBox.square(
      dimension: 48,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelect(index),
          child: Icon(body.unselectedIcon, size: 22, color: colors.muted),
        ),
      ),
    );
  }
}
