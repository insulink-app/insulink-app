import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';

import '../../alert/alert.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locales.dart';
import 'libre3_nfc_scan_sheet.dart';

/// Runs one Libre 3 NFC activation with its "hold the sensor" bottom sheet:
/// shows the sheet, drives [CgmController.activateLibre3], flips the sheet to
/// "success" the moment the NFC read lands (before the slower BLE start), and
/// surfaces a failure as an error alert. Cancelling the sheet aborts the scan.
///
/// Shared by the pairing form and the backend-restore offer — a restored Libre 3
/// needs a scan too, because its BLE PIN is reissued on every NFC scan.
class Libre3ScanFlow {
  Libre3ScanFlow({required this.controller, this.accountId = ''});

  final CgmController controller;

  /// LibreView account id, only for taking over a sensor Abbott's app activated.
  final String accountId;

  /// True once the sensor is activated and reading; false if the scan failed or
  /// the user cancelled the sheet.
  ///
  /// The sheet closes itself shortly after the NFC read lands, while the slower
  /// BLE start is still running — so a closed sheet only counts as a cancel while
  /// the scan has NOT succeeded ([scanned]), otherwise the success would abort
  /// its own activation and swallow a later failure.
  Future<bool> run(BuildContext context) async {
    final navigator = Navigator.of(context);
    final failed = Locales.string(context, 'sensor.pair.libre.failed');
    final phase = ValueNotifier(Libre3ScanPhase.scanning);
    var finished = false;
    var scanned = false;
    var cancelled = false;
    var sheetOpen = true;
    showInkSheet<void>(
      context: context,
      builder: (_) => Libre3NfcScanSheet(
        phase: phase,
        onCancel: navigator.maybePop,
        onClose: navigator.maybePop,
      ),
    ).whenComplete(() {
      sheetOpen = false;
      if (!finished && !scanned) {
        cancelled = true;
        controller.cancelLibre3Scan();
      }
      phase.dispose();
    });
    final error = await controller.activateLibre3(
      accountId: accountId,
      onActivated: () {
        if (!cancelled) {
          scanned = true;
          phase.value = Libre3ScanPhase.success;
        }
      },
    );
    finished = true;
    if (cancelled) {
      return false;
    }
    if (error == null) {
      return true;
    }
    if (sheetOpen) {
      navigator.maybePop();
    }
    if (navigator.mounted) {
      _reportFailure(navigator.context, '$failed\n$error');
    }
    return false;
  }

  /// An activation failure is a dead end the user has to read and answer (scan
  /// again, or give up), and it carries the driver's own error text — so it gets
  /// a modal that waits, not a notice that times out while the phone is still
  /// held against the sensor.
  ///
  /// Posted against the navigator's context: [run] is long-async (NFC, then a
  /// BLE start), and this class is not a widget, so it has no `mounted` of its
  /// own to check the caller's context against.
  void _reportFailure(BuildContext context, String message) {
    Alert(
      type: AlertType.error,
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, height: 1.35),
      ),
    ).show(context);
  }
}
