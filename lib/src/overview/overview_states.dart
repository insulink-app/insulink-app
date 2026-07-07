import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/devices/devices_body.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:provider/provider.dart';

/// Prominent, tappable indicator shown on the overview while silent mode mutes
/// all alarms. Tapping it turns silent mode back off — alarms are safety
/// relevant, so it's deliberately easy to clear from the main screen.
class SilentBanner extends StatelessWidget {
  const SilentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFFE8A13A);
    return Material(
      color: accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<ProfileSilentState>().setSilent(false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_off_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(child: _text(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          'overview.silent.title',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        LocaleText(
          'overview.silent.hint',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
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
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
                CupertinoIcons.drop,
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
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => openDevicesPage(context),
              icon: const Icon(CupertinoIcons.drop_fill, size: 18),
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
