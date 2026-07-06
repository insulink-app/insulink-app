import 'package:flutter/material.dart';

import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import 'libre3_nfc_scan_sheet.dart';

/// Libre 3 pairing: an optional LibreView account id (for taking over a sensor
/// Abbott's app already activated) and an NFC "scan sensor" button that runs
/// [CgmController.activateLibre3].
class Libre3PairingFields extends StatefulWidget {
  const Libre3PairingFields({super.key, required this.controller});

  final CgmController controller;

  @override
  State<Libre3PairingFields> createState() => _Libre3PairingFieldsState();
}

class _Libre3PairingFieldsState extends State<Libre3PairingFields> {
  final _account = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final phase = ValueNotifier(Libre3ScanPhase.scanning);
    var finished = false;
    var cancelled = false;
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => Libre3NfcScanSheet(
        phase: phase,
        controller: widget.controller,
        onCancel: navigator.maybePop,
        onClose: navigator.maybePop,
      ),
    ).whenComplete(() {
      if (!finished) {
        cancelled = true;
        widget.controller.cancelLibre3Scan();
        if (mounted) {
          setState(() => _busy = false);
        }
      }
      phase.dispose();
    });
    final error = await widget.controller.activateLibre3(
      accountId: _account.text.trim(),
      // Flip to the success/connecting view as soon as the NFC read lands, not
      // after the slower BLE service start.
      onActivated: () {
        if (!cancelled) {
          phase.value = Libre3ScanPhase.success;
        }
      },
    );
    finished = true;
    if (!mounted || cancelled) {
      return;
    }
    setState(() => _busy = false);
    if (error == null) {
      return;
    }
    navigator.pop();
    final message = Locales.string(context, 'sensor.pair.libre.failed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$message\n$error'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'sensor.pair.libre.hint',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _account,
          decoration: InputDecoration(
            labelText: Locales.string(context, 'sensor.pair.libre.account'),
            helperText: Locales.string(
              context,
              'sensor.pair.libre.account_hint',
            ),
            helperMaxLines: 2,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _activate,
          icon: const Icon(Icons.nfc, size: 20),
          label: LocaleText(
            _busy ? 'sensor.pair.libre.scanning' : 'sensor.pair.libre.activate',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
      ],
    );
  }
}
