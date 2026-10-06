import 'package:flutter/material.dart';
import 'package:insulink/src/base/notice_banner.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A tinted line on the pump pages that stays until something replaces it.
///
/// Never timed out and never a snack bar: a pump failure, a status too old to act
/// on, or a declined fingerprint is exactly the kind of thing that must not
/// scroll away unread.
class PumpNotice extends StatelessWidget {
  const PumpNotice._({
    this.text,
    this.textKey,
    required this.icon,
    required this.tone,
  });

  /// Something the pod, or the link to it, refused or could not confirm. Carries
  /// raw diagnostic text from an exception, shown as detail rather than as
  /// instruction.
  const PumpNotice.failure(String message)
    : this._(
        text: message,
        icon: PhosphorIconsFill.warningCircle,
        tone: NoticeTone.danger,
      );

  /// A failure the user has to ACT on, where a raw exception string would be no
  /// help, so it names a locale key instead.
  const PumpNotice.problem(String key)
    : this._(
        textKey: key,
        icon: PhosphorIconsFill.warningCircle,
        tone: NoticeTone.danger,
      );

  /// The fingerprint in front of the cannula was declined. Deliberately not an
  /// error: nothing went wrong and the pod is untouched, so it explains rather
  /// than alarms.
  const PumpNotice.declined()
    : this._(
        textKey: 'pump.activate.confirm_declined',
        icon: PhosphorIconsBold.fingerprint,
        tone: NoticeTone.warning,
      );

  final String? text;
  final String? textKey;
  final IconData icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(icon: icon, tone: tone, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final style = InkText.label.copyWith(color: context.ink.text);
    final key = textKey;
    if (key != null) {
      return LocaleText(key, style: style);
    }
    return Text(
      text ?? Locales.string(context, 'pump.status.never_read'),
      style: style,
    );
  }
}
