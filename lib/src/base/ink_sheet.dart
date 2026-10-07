import 'package:flutter/material.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Opens the app's one kind of bottom sheet. [builder] returns an [InkSheet]
/// (or a widget that builds one), which draws the handle, title, close button
/// and margins.
///
/// Every sheet goes through here; nothing calls `showModalBottomSheet`
/// directly. Always scroll-controlled with a safe area, so a tall sheet grows
/// with its content and never slides under the status bar.
Future<T?> showInkSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: builder,
  );
}

/// The chrome every sheet shares (`docs/redesign/DESIGN.md`, "Popups:
/// Bottom-Sheets"): panel colour, radius 28 on top, the grab handle, the title
/// on the left and a round close button on the right (alone, without a title),
/// then the content 12 px from the edges, lifted above the keyboard.
class InkSheet extends StatelessWidget {
  const InkSheet({super.key, required this.child, this.titleKey, this.title});

  final Widget child;
  final String? titleKey;

  /// A title that is more than a locale key (e.g. a sheet's own header row).
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            InkSpace.panelMargin,
            10,
            InkSpace.panelMargin,
            InkSpace.panelMargin,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const GrabHandle(),
              const SizedBox(height: 8),
              _header(context, colors),
              const SizedBox(height: 12),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, InsulinkColors colors) {
    final heading =
        title ??
        (titleKey == null
            ? null
            : LocaleText(
                titleKey!,
                style: InkText.bigValue.copyWith(fontSize: 20),
              ));
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: heading ?? const SizedBox.shrink(),
          ),
        ),
        InkSheetCloseButton(colors: colors),
      ],
    );
  }
}

/// The round 40 px close button at the top right of every sheet.
class InkSheetCloseButton extends StatelessWidget {
  const InkSheetCloseButton({super.key, required this.colors});

  final InsulinkColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: Locales.string(context, 'alert.close'),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: InkSpace.minTouch,
        child: Center(
          child: Material(
            color: colors.panelRaised,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox.square(
                dimension: 40,
                child: Icon(PhosphorIconsBold.x, size: 18, color: colors.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
