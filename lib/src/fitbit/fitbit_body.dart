import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_importer.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:provider/provider.dart';

/// Fitbit device page (Devices tab). "Connecting" just grants Health Connect
/// read access — the Fitbit itself is paired in the Fitbit app, which syncs its
/// data into Health Connect.
class FitbitBodyContent extends StatelessWidget {
  const FitbitBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final fitbit = context.watch<FitbitState>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _statusCard(context, fitbit),
        const SizedBox(height: 20),
        if (!fitbit.connected) ...[
          LocaleText(
            'fitbit.hint',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
        ],
        _actionButton(context, fitbit),
      ],
    );
  }

  Widget _statusCard(BuildContext context, FitbitState fitbit) {
    final scheme = Theme.of(context).colorScheme;
    final statusKey = fitbit.connected
        ? 'fitbit.status.connected'
        : 'fitbit.status.disconnected';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            fitbit.connected ? Icons.watch : Icons.watch_off,
            color: scheme.primary,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: LocaleText(
              statusKey,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, FitbitState fitbit) {
    if (fitbit.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (fitbit.connected) {
      return OutlinedButton(
        onPressed: fitbit.disconnect,
        child: LocaleText('fitbit.disconnect'),
      );
    }
    return FilledButton(
      onPressed: () => _connect(context, fitbit),
      child: LocaleText('fitbit.connect'),
    );
  }

  Future<void> _connect(BuildContext context, FitbitState fitbit) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = Locales.string(context, 'fitbit.denied');
    final unavailable = Locales.string(context, 'fitbit.unavailable');
    final result = await fitbit.connect();
    final message = switch (result) {
      FitbitImportResult.success => null,
      FitbitImportResult.denied => denied,
      FitbitImportResult.unavailable => unavailable,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
