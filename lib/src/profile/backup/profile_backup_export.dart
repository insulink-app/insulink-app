import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/button_loader.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/page_primary_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/backup/data_backup.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Profile topic for the data backup: what the file holds, a one-line hint
/// that it is not encrypted, and the export button at the foot of the page.
class ProfileBackupExport extends StatefulWidget {
  const ProfileBackupExport({super.key});

  @override
  State<ProfileBackupExport> createState() => _ProfileBackupExportState();
}

class _ProfileBackupExportState extends State<ProfileBackupExport> {
  static const _contents = [
    (icon: PhosphorIconsBold.drop, key: 'profile.backup.contents.glucose'),
    (icon: PhosphorIconsBold.syringe, key: 'profile.backup.contents.insulin'),
    (icon: PhosphorIconsBold.forkKnife, key: 'profile.backup.contents.life'),
    (icon: PhosphorIconsBold.sliders, key: 'profile.backup.contents.settings'),
  ];

  bool _busy = false;

  /// Runs the export and reports success or failure; a cancelled save dialog
  /// stays silent.
  Future<void> _export() async {
    setState(() => _busy = true);
    final outcome = await const DataBackup()
        .export()
        .then((saved) => saved ? AlertType.success : null)
        .catchError((Object error) => AlertType.error);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (outcome != null) {
      _report(outcome);
    }
  }

  void _report(AlertType outcome) {
    Alert(
      type: outcome,
      description: outcome == AlertType.success
          ? 'profile.backup.saved'
          : 'profile.backup.failed',
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LocaleText(
          'profile.backup.intro',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 16),
        InkPanel.list(
          rows: [
            for (final item in _contents)
              ListRow(
                icon: item.icon,
                title: Locales.string(context, item.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _hint(),
        const Spacer(),
        const SizedBox(height: 24),
        _button(),
      ],
    );
  }

  Widget _hint() {
    final muted = context.ink.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        spacing: 8,
        children: [
          Icon(PhosphorIconsBold.lockSimpleOpen, size: 16, color: muted),
          Expanded(
            child: LocaleText(
              'profile.backup.hint',
              style: InkText.caption.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button() {
    return PagePrimaryButton(
      onPressed: _busy ? null : _export,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 10,
        children: [
          _busy
              ? const ButtonLoader()
              : const Icon(PhosphorIconsBold.downloadSimple),
          LocaleText(
            _busy ? 'profile.backup.loading' : 'profile.backup.export',
          ),
        ],
      ),
    );
  }
}
