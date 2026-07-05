import 'package:flutter/material.dart';

import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';

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
    final error = await widget.controller.activateLibre3(
      accountId: _account.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      final message = Locales.string(context, 'sensor.pair.libre.failed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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
