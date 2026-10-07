import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// What a dialog is about, which colours its icon disc and its action:
/// something to fill in or confirm (accent), something that throws away or
/// stops (danger), a plain notice (neutral).
enum InkDialogTone { accent, danger, neutral }

/// The one dialog of the app (`docs/redesign/DESIGN.md`, "Popups: Dialoge"):
/// a card floating at the foot of the screen, 12 px from the edges, radius 32,
/// over the page blurred and darkened. Centred icon disc, title, an optional
/// short sentence or a [content] widget (an input), then the action full
/// width and "Abbrechen" as a plain text button under it. A dialog with an
/// input sits right above the keyboard.
///
/// Every dialog goes through [show]; nothing builds one with `showDialog`.
class InkDialog extends StatelessWidget {
  const InkDialog({
    super.key,
    required this.icon,
    this.tone = InkDialogTone.accent,
    this.titleKey,
    this.title,
    this.messageKey,
    this.content,
    this.actionKey = 'alert.ok',
    this.onAction,
    this.actionEnabled,
    this.cancelKey,
    this.onCancel,
  }) : loading = false;

  /// A card with only a spinner, for a request in flight; it cannot be
  /// dismissed and is popped by whoever showed it.
  const InkDialog.loading({super.key})
    : icon = null,
      tone = InkDialogTone.neutral,
      titleKey = null,
      title = null,
      messageKey = null,
      content = null,
      actionKey = 'alert.ok',
      onAction = null,
      actionEnabled = null,
      cancelKey = null,
      onCancel = null,
      loading = true;

  final IconData? icon;
  final InkDialogTone tone;

  /// The title, as a locale key or already resolved.
  final String? titleKey;
  final String? title;

  /// The optional short sentence under the title.
  final String? messageKey;

  /// Anything else between title and buttons: an input, a longer explanation.
  final Widget? content;

  final String actionKey;

  /// Runs after the dialog has closed.
  final VoidCallback? onAction;

  /// Re-checked on every build; while false the action is dimmed and inert.
  final bool Function()? actionEnabled;

  /// The quiet second answer ("Abbrechen"); null shows none.
  final String? cancelKey;
  final VoidCallback? onCancel;

  final bool loading;

  /// Slides the card up and fades it in over the blurred page. The browser
  /// build gets no blur, only the scrim: CanvasKit re-blurs the whole screen
  /// every frame the dialog is up, which made each popup stutter there.
  Future<void> show(BuildContext context) {
    final scrim = context.ink.ground.withValues(alpha: 0.55);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: !loading,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: scrim,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => this,
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final dialog = FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
        return kIsWeb ? dialog : _blurred(animation, dialog);
      },
    );
  }

  Widget _blurred(Animation<double> animation, Widget dialog) {
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: 4 * animation.value,
        sigmaY: 4 * animation.value,
      ),
      child: dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(InkSpace.panelMargin),
            child: Material(
              color: colors.panelRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
                side: BorderSide(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                child: loading ? _spinner(colors) : _body(context, colors),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _spinner(InsulinkColors colors) {
    return SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator(color: colors.accent)),
    );
  }

  Widget _body(BuildContext context, InsulinkColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _disc(colors)),
        if (title != null || titleKey != null) ...[
          const SizedBox(height: 18),
          _title(),
        ],
        if (messageKey != null) ...[
          const SizedBox(height: 8),
          LocaleText(
            messageKey!,
            textAlign: TextAlign.center,
            style: InkText.body.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.muted,
            ),
          ),
        ],
        if (content != null) ...[
          const SizedBox(height: 18),
          _fieldTheme(context, colors, content!),
        ],
        const SizedBox(height: 24),
        _action(context, colors),
        if (cancelKey != null) ...[
          const SizedBox(height: 4),
          _cancel(context, colors),
        ],
      ],
    );
  }

  /// Inputs in a dialog: 56 high, radius 18, on the page colour, a 1.5 px
  /// accent rim while focused.
  Widget _fieldTheme(
    BuildContext context,
    InsulinkColors colors,
    Widget child,
  ) {
    final theme = Theme.of(context);
    OutlineInputBorder rim(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.ground,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: rim(colors.border, 1),
          enabledBorder: rim(colors.border, 1),
          focusedBorder: rim(colors.accent, 1.5),
        ),
      ),
      child: child,
    );
  }

  Widget _disc(InsulinkColors colors) {
    final glyph = switch (tone) {
      InkDialogTone.accent => colors.accentText,
      InkDialogTone.danger => colors.low,
      InkDialogTone.neutral => colors.text,
    };
    final fill = switch (tone) {
      InkDialogTone.accent => colors.accent.withValues(alpha: 0.16),
      InkDialogTone.danger => colors.low.withValues(alpha: 0.14),
      InkDialogTone.neutral => colors.text.withValues(alpha: 0.08),
    };
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      child: Icon(icon, size: 26, color: glyph),
    );
  }

  Widget _title() {
    final style = InkText.bigValue.copyWith(fontSize: 21, height: 1.25);
    if (title != null) {
      return Text(title!, textAlign: TextAlign.center, style: style);
    }
    return LocaleText(titleKey!, textAlign: TextAlign.center, style: style);
  }

  /// Full width, 52 high: the accent, or solid danger with the text in the
  /// page colour.
  Widget _action(BuildContext context, InsulinkColors colors) {
    final enabled = actionEnabled?.call() ?? true;
    final danger = tone == InkDialogTone.danger;
    return FilledButton(
      onPressed: enabled
          ? () {
              Navigator.pop(context);
              onAction?.call();
            }
          : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: danger ? colors.low : colors.accent,
        foregroundColor: danger ? colors.ground : colors.onAccent,
        disabledBackgroundColor: (danger ? colors.low : colors.accent)
            .withValues(alpha: 0.35),
        disabledForegroundColor: colors.ground,
      ),
      child: LocaleText(actionKey),
    );
  }

  Widget _cancel(BuildContext context, InsulinkColors colors) {
    return TextButton(
      onPressed: () {
        Navigator.pop(context);
        onCancel?.call();
      },
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: colors.muted,
      ),
      child: LocaleText(cancelKey!, style: InkText.button),
    );
  }
}
