import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/backup/data_backup.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Profile topic for the data backup: what it contains and a button that saves
/// it as a file via [DataBackup].
class ProfileBackupExport extends StatefulWidget {
  const ProfileBackupExport({super.key});

  @override
  State<ProfileBackupExport> createState() => _ProfileBackupExportState();
}

class _ProfileBackupExportState extends State<ProfileBackupExport> {
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
          'profile.backup.description',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(PhosphorIconsBold.downloadSimple),
          label: const LocaleText('profile.backup.export'),
        ),
      ],
    );
  }
}
