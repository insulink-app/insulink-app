import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/overview_banner.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Prominent, tappable indicator shown on the overview while silent mode mutes
/// the alarm tones or the alarms outright. Tapping it turns silent mode back off
/// — alarms are safety relevant, so it's deliberately easy to clear from the
/// main screen.
class SilentBanner extends StatelessWidget {
  const SilentBanner(this.mode, {super.key});

  final SilentMode mode;

  @override
  Widget build(BuildContext context) {
    return OverviewBanner(
      icon: PhosphorIconsBold.bellSlash,
      titleKey: 'overview.silent.${mode.name}.title',
      hintKey: 'overview.silent.${mode.name}.hint',
      until: context.watch<ProfileSilentState>().window.until,
      onTap: () => context.read<ProfileSilentState>().setMode(SilentMode.off),
    );
  }
}

/// Shown while the service is scanning/connecting but no reading has arrived.
class SearchingView extends StatelessWidget {
  const SearchingView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          LocaleText(
            'overview.searching',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LocaleText(
            'overview.searching.hint',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Shown when no sensor is set up yet — points the user to the sensor page,
/// where pairing now happens.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
              ),
              child: Icon(
                PhosphorIconsBold.drop,
                size: 44,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(height: 24),
            LocaleText(
              'overview.empty.title',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            LocaleText(
              'overview.empty.body',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => openConnectionsPage(context),
              icon: const Icon(PhosphorIconsFill.drop, size: 18),
              label: LocaleText('overview.empty.action'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
